// "Start now, name it later".
//
// The property that matters is the one the whole feature exists for: the
// boundary opens at the tap, and answering it later must NOT move that boundary
// — so the seconds spent deciding belong to the activity finally chosen, not to
// whatever was running before.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/data/drift_repositories.dart';
import 'package:time_tracker/data/tracker_controller.dart';
import 'package:time_tracker/domain/unsorted.dart';

void main() {
  late AppDatabase db;
  late DriftActivityRepository activities;
  late DriftChangeRepository changes;
  late TrackerController controller;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    activities = DriftActivityRepository(db);
    changes = DriftChangeRepository(db);
    controller = TrackerController(activities, changes);
  });

  tearDown(() => db.close());

  group('ensureUnsorted', () {
    test('creates the catch-all once, under a fixed id', () async {
      final first = await activities.ensureUnsorted();
      final second = await activities.ensureUnsorted();

      expect(first.syncId, kUnsortedActivityId);
      expect(second.syncId, first.syncId);
      // A fixed id is what makes two devices converge on one catch-all instead
      // of each creating their own.
      expect(await activities.loadActivities(), hasLength(1));
    });

    test('revives a deleted catch-all rather than failing on the primary key', () async {
      await activities.ensureUnsorted();
      await activities.deleteActivity(kUnsortedActivityId);

      final revived = await activities.ensureUnsorted();

      expect(revived.syncId, kUnsortedActivityId);
      expect((await activities.loadActivities()).single.deletedAt, isNull);
    });

    test('corrects the superseded name, and bumps the version so peers see it',
        () async {
      // A device that created the catch-all before the rename holds the old
      // label, and it is the *stored* name every screen now reads — so left
      // alone that device would keep showing a different word from a fresh one.
      await activities.ensureUnsorted();
      await activities.renameActivity(kUnsortedActivityId, kUnsortedLegacyName);
      final stale = (await activities.loadActivities()).single;

      final fixed = await activities.ensureUnsorted();

      expect(fixed.name, kUnsortedName);
      // Through the version, or the correction would sit on this device only.
      expect(fixed.version, greaterThan(stale.version));
    });

    test('never overwrites a name the user chose', () async {
      // The correction recognises exactly one superseded default. Anything else
      // is a deliberate edit, and healing over it would undo that edit on every
      // app start — silently, and for good.
      await activities.ensureUnsorted();
      await activities.renameActivity(kUnsortedActivityId, 'Inbox');

      final after = await activities.ensureUnsorted();

      expect(after.name, 'Inbox');
    });
  });

  group('startUnsorted', () {
    test('opens a boundary immediately, tracking the catch-all', () async {
      await controller.startUnsorted();

      final current = await changes.currentChange();
      expect(current, isNotNull);
      expect(await changes.activityIdsForChange(current!.syncId), [kUnsortedActivityId]);
    });

    test('starts a second unnamed block rather than merging into the first', () async {
      // Reported from wearing the watch: two unnamed blocks in a row are two
      // different things to name later, and merging them loses that with no way
      // to separate it after. This was once the exception to a no-op guard on
      // switchTo; the argument turned out to generalise, so the guard went and
      // both now follow one rule.
      await controller.startUnsorted(at: DateTime(2026, 1, 5, 9));
      await controller.startUnsorted(at: DateTime(2026, 1, 5, 10));

      final rows = await changes.loadChanges();
      expect(rows, hasLength(2));
      expect(rows.map((c) => c.changedAt).toSet(), hasLength(2));
      for (final row in rows) {
        expect(await changes.activityIdsForChange(row.syncId), [kUnsortedActivityId]);
      }
    });

    test('a named activity now follows the same rule', () async {
      // The inverse of what this once asserted. startUnsorted used to be the
      // lone exception to a guard that refused to re-open a running activity;
      // both paths now open a boundary, so the unnamed case is no longer
      // special — it just does not offer the undo, because a second unnamed
      // block is the intent rather than a slip.
      final work = await activities.createActivity(name: 'Deep work', color: '#4F8FEE');
      await controller.switchTo(work.syncId);
      await controller.switchTo(work.syncId);

      expect(await changes.loadChanges(), hasLength(2));
    });
  });

  group('assignBlock', () {
    test('re-points the block without moving its boundary', () async {
      final at = DateTime(2026, 1, 5, 9, 30);
      await activities.ensureUnsorted();
      final unnamed = await changes.switchTo(kUnsortedActivityId, at: at);
      final work = await activities.createActivity(name: 'Deep work', color: '#4F8FEE');

      await controller.assignBlock(unnamed.syncId, work.syncId);

      final rows = await changes.loadChanges();
      // One boundary, still at the original instant: this is the whole point —
      // the time spent deciding belongs to "Deep work", not to what came before.
      expect(rows, hasLength(1));
      expect(rows.single.changedAt, at);
      expect(await changes.activityIdsForChange(unnamed.syncId), [work.syncId]);
    });

    test('the catch-all is replaced, not accumulated', () async {
      await activities.ensureUnsorted();
      final unnamed = await changes.switchTo(kUnsortedActivityId);
      final work = await activities.createActivity(name: 'Deep work', color: '#4F8FEE');

      await controller.assignBlock(unnamed.syncId, work.syncId);

      // Leaving the catch-all tagged would make the block look like a
      // "forgot to switch" block and halve the attribution.
      final ids = await changes.activityIdsForChange(unnamed.syncId);
      expect(ids, [work.syncId]);
      expect(ids, isNot(contains(kUnsortedActivityId)));
    });

    test('bumps recency, so the named activity surfaces next time', () async {
      await activities.ensureUnsorted();
      final unnamed = await changes.switchTo(kUnsortedActivityId);
      final work = await activities.createActivity(name: 'Deep work', color: '#4F8FEE');

      await controller.assignBlock(unnamed.syncId, work.syncId);

      final stored = (await activities.loadActivities())
          .firstWhere((a) => a.syncId == work.syncId);
      expect(stored.lastUsedAt, isNotNull);
    });

    test('bumps the change version so the re-point actually syncs', () async {
      await activities.ensureUnsorted();
      final unnamed = await changes.switchTo(kUnsortedActivityId);
      final work = await activities.createActivity(name: 'Deep work', color: '#4F8FEE');
      final before = (await changes.loadChanges()).single.version;

      await controller.assignBlock(unnamed.syncId, work.syncId);

      // The set travels inside its change, so without a version bump the edit
      // would never leave the device.
      expect((await changes.loadChanges()).single.version, greaterThan(before));
    });

    test('an unknown activity leaves the block alone', () async {
      await activities.ensureUnsorted();
      final unnamed = await changes.switchTo(kUnsortedActivityId);

      await controller.assignBlock(unnamed.syncId, 'no-such-activity');

      // Never strip a block down to an empty set — something is always tracking.
      expect(await changes.activityIdsForChange(unnamed.syncId), [kUnsortedActivityId]);
    });
  });

  group('isUnsortedSet', () {
    test('only a lone catch-all counts as unanswered', () async {
      final unsorted = await activities.ensureUnsorted();
      final work = await activities.createActivity(name: 'Deep work', color: '#4F8FEE');

      expect(isUnsortedSet([unsorted]), isTrue);
      expect(isUnsortedSet([work]), isFalse);
      // Tagged with a real activity as well — that block has been answered.
      expect(isUnsortedSet([unsorted, work]), isFalse);
      expect(isUnsortedSet([]), isFalse);
    });
  });
}
