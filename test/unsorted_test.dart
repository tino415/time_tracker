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
      // different things to name later. switchTo's no-op guard would collapse
      // them, silently merging unrelated work with no way to separate it after.
      await controller.startUnsorted(at: DateTime(2026, 1, 5, 9));
      await controller.startUnsorted(at: DateTime(2026, 1, 5, 10));

      final rows = await changes.loadChanges();
      expect(rows, hasLength(2));
      expect(rows.map((c) => c.changedAt).toSet(), hasLength(2));
      for (final row in rows) {
        expect(await changes.activityIdsForChange(row.syncId), [kUnsortedActivityId]);
      }
    });

    test('a named activity still refuses to re-open what is running', () async {
      // The guard that startUnsorted bypasses must stay in place elsewhere:
      // re-tapping a running activity would split its block for nothing.
      final work = await activities.createActivity(name: 'Deep work', color: '#4F8FEE');
      await controller.switchTo(work.syncId);
      await controller.switchTo(work.syncId);

      expect(await changes.loadChanges(), hasLength(1));
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
