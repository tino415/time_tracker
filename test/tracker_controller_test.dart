// TrackerController against the real Drift repositories (in-memory): the switch
// action's recency bump and its no-op guard for re-picking what already runs,
// plus the calendar edits (move a boundary, split a block, merge into previous).

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/data/drift_repositories.dart';
import 'package:time_tracker/data/tracker_controller.dart';
import 'package:time_tracker/domain/block.dart';

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

  test('switchTo opens a block and bumps recency', () async {
    final a = await activities.createActivity(name: 'Work', color: '#333333');
    await controller.switchTo(a.syncId);

    final current = await changes.currentChange();
    expect(await changes.activityIdsForChange(current!.syncId), [a.syncId]);
    expect((await activities.loadActivities()).single.lastUsedAt, isNotNull);
  });

  // Inverted deliberately. This used to pin a no-op guard, on the reasoning that
  // the two halves would be indistinguishable — but a comment lives on the
  // change, one per block, so splitting is how the second stretch of the same
  // work gets its own note.
  test('re-picking the running activity opens a second boundary', () async {
    final a = await activities.createActivity(name: 'Work', color: '#333333');
    await controller.switchTo(a.syncId);
    final first = await changes.currentChange();

    final outcome = await controller.switchTo(a.syncId);

    expect((await changes.watchChanges().first).length, 2);
    expect((await changes.currentChange())!.syncId, isNot(first!.syncId));
    // Reported, so the screen can offer to take it back — the accidental
    // double-tap is answered by making the split visible, not by refusing it.
    expect(outcome.splitSameActivity, isTrue);
    expect(outcome.changeId, (await changes.currentChange())!.syncId);
  });

  test('undoing the split restores the single block', () async {
    final a = await activities.createActivity(name: 'Work', color: '#333333');
    await controller.switchTo(a.syncId);
    final first = await changes.currentChange();

    final outcome = await controller.switchTo(a.syncId);
    await controller.mergeIntoPrevious(outcome.changeId);

    expect(await changes.loadChanges(), hasLength(1));
    expect((await changes.currentChange())!.syncId, first!.syncId);
  });

  test('narrowing a two-activity block is not reported as a same-activity split', () async {
    final a = await activities.createActivity(name: 'A', color: '#333333');
    final b = await activities.createActivity(name: 'B', color: '#444444');
    await controller.switchTo(a.syncId);
    // A tagged ("forgot to switch") block tracks two activities, so switching to
    // one of them is a real change: it narrows the set back down to that one.
    // Never a fumble, so it must not offer an undo.
    await changes.addActivityToChange((await changes.currentChange())!.syncId, b.syncId);

    final outcome = await controller.switchTo(a.syncId);

    expect((await changes.watchChanges().first).length, 2);
    expect(await changes.activityIdsForChange((await changes.currentChange())!.syncId), [a.syncId]);
    expect(outcome.splitSameActivity, isFalse);
  });

  test('an explicit timestamp is never reported as a fumble', () async {
    // A split or a retime passes `at`. It is deliberate by construction, so
    // offering to undo it would be noise on every calendar edit.
    final a = await activities.createActivity(name: 'Work', color: '#333333');
    await controller.switchTo(a.syncId, at: DateTime(2026, 1, 5, 9));

    final outcome = await controller.switchTo(a.syncId, at: DateTime(2026, 1, 5, 10));

    expect(outcome.splitSameActivity, isFalse);
  });

  test('an explicit timestamp always makes a boundary', () async {
    final a = await activities.createActivity(name: 'Work', color: '#333333');
    await controller.switchTo(a.syncId, at: DateTime(2026, 1, 5, 9));
    await controller.switchTo(a.syncId, at: DateTime(2026, 1, 5, 10));

    expect((await changes.watchChanges().first).length, 2);
  });

  test('switching to a different activity always opens a boundary', () async {
    final a = await activities.createActivity(name: 'A', color: '#333333');
    final b = await activities.createActivity(name: 'B', color: '#444444');
    await controller.switchTo(a.syncId);
    await controller.switchTo(b.syncId);

    expect((await changes.watchChanges().first).length, 2);
  });

  // ---- calendar edits ------------------------------------------------------

  DateTime at(int hour, [int minute = 0]) => DateTime(2026, 1, 5, hour, minute);
  final now = DateTime(2026, 1, 5, 20);

  /// Three consecutive boundaries at 09:00 / 12:00 / 15:00.
  Future<List<String>> seedDay() async {
    final a = await activities.createActivity(name: 'A', color: '#333333');
    final b = await activities.createActivity(name: 'B', color: '#444444');
    final c = await activities.createActivity(name: 'C', color: '#555555');
    await controller.switchTo(a.syncId, at: at(9));
    await controller.switchTo(b.syncId, at: at(12));
    await controller.switchTo(c.syncId, at: at(15));
    // loadChanges is newest first; return oldest first.
    return (await changes.loadChanges()).reversed.map((c) => c.syncId).toList();
  }

  Future<DateTime> boundaryOf(String id) async =>
      (await changes.loadChanges()).firstWhere((c) => c.syncId == id).changedAt;

  group('moveBoundary', () {
    test('retimes a boundary between its neighbours', () async {
      final ids = await seedDay();
      await controller.moveBoundary(ids[1], at(13), now: now);

      expect(await boundaryOf(ids[1]), at(13));
      // The neighbours are untouched — one boundary moved, two blocks resized.
      expect(await boundaryOf(ids[0]), at(9));
      expect(await boundaryOf(ids[2]), at(15));
    });

    test('a drag past the previous boundary is clamped, not reordered', () async {
      final ids = await seedDay();
      await controller.moveBoundary(ids[1], at(7), now: now, minBlock: const Duration(minutes: 5));

      expect(await boundaryOf(ids[1]), at(9, 5));
      // Order is preserved, so no block silently changed owner.
      final ascending = (await changes.loadChanges()).reversed.map((c) => c.syncId);
      expect(ascending, ids);
    });

    test('a drag past the next boundary is clamped too', () async {
      final ids = await seedDay();
      await controller.moveBoundary(ids[1], at(18), now: now, minBlock: const Duration(minutes: 5));

      expect(await boundaryOf(ids[1]), at(14, 55));
    });

    test('the newest boundary cannot be dragged onto the present', () async {
      // It stops a minute short of `now` rather than on it: the running block
      // ends at the present, so landing there would leave it zero-length — too
      // short to draw, and with no boundary left to grab and drag back.
      final ids = await seedDay();
      await controller.moveBoundary(ids[2], at(23), now: now);

      expect(await boundaryOf(ids[2]), now.subtract(const Duration(minutes: 1)));
    });

    test('the earliest boundary can move freely backwards', () async {
      final ids = await seedDay();
      await controller.moveBoundary(ids[0], at(5), now: now);

      expect(await boundaryOf(ids[0]), at(5));
    });

    test('an unknown id is a no-op', () async {
      final ids = await seedDay();
      await controller.moveBoundary('nope', at(13), now: now);

      expect(await boundaryOf(ids[1]), at(12));
    });
  });

  group('splitBlock', () {
    test('splits a block in two, tracking the new activity from the cut', () async {
      final ids = await seedDay();
      final d = await activities.createActivity(name: 'D', color: '#666666');
      final blocks = await derivedBlocks(changes, activities, now);
      final middle = blocks.firstWhere((b) => b.change.syncId == ids[1]);

      await controller.splitBlock(block: middle, at: at(13), activityId: d.syncId, now: now);

      final ascending = (await changes.loadChanges()).reversed.toList();
      expect(ascending.map((c) => c.changedAt), [at(9), at(12), at(13), at(15)]);
      final cut = ascending[2];
      expect(await changes.activityIdsForChange(cut.syncId), [d.syncId]);
      // A split is a switch, so it counts as usage of the new activity.
      expect(
        (await activities.loadActivities()).firstWhere((a) => a.syncId == d.syncId).lastUsedAt,
        isNotNull,
      );
    });

    test('refuses a cut outside the block', () async {
      final ids = await seedDay();
      final d = await activities.createActivity(name: 'D', color: '#666666');
      final blocks = await derivedBlocks(changes, activities, now);
      final middle = blocks.firstWhere((b) => b.change.syncId == ids[1]);

      await controller.splitBlock(block: middle, at: at(16), activityId: d.syncId, now: now);

      expect((await changes.loadChanges()).length, 3);
    });

    test('refuses a cut that would leave a half shorter than minBlock', () async {
      final ids = await seedDay();
      final d = await activities.createActivity(name: 'D', color: '#666666');
      final blocks = await derivedBlocks(changes, activities, now);
      final middle = blocks.firstWhere((b) => b.change.syncId == ids[1]);

      await controller.splitBlock(
        block: middle,
        at: at(12, 2),
        activityId: d.syncId,
        now: now,
        minBlock: const Duration(minutes: 5),
      );

      expect((await changes.loadChanges()).length, 3);
    });
  });

  group('mergeIntoPrevious', () {
    test('deletes the opening boundary so the previous block absorbs it', () async {
      final ids = await seedDay();
      await controller.mergeIntoPrevious(ids[1]);

      final ascending = (await changes.loadChanges()).reversed.toList();
      expect(ascending.map((c) => c.syncId), [ids[0], ids[2]]);
      // The first block now runs 09:00 -> 15:00.
      expect(ascending.first.changedAt, at(9));
    });

    test('the earliest block has no boundary to delete', () async {
      final ids = await seedDay();
      await controller.mergeIntoPrevious(ids[0]);

      expect((await changes.loadChanges()).length, 3);
    });
  });

  group('swapWithPrevious', () {
    test('the labels change places and the boundaries do not', () async {
      final ids = await seedDay();
      final before = [for (final id in ids) await changes.activityIdsForChange(id)];

      await controller.swapWithPrevious(ids[1]);

      expect(await changes.activityIdsForChange(ids[0]), before[1]);
      expect(await changes.activityIdsForChange(ids[1]), before[0]);
      // The whole point: a three-hour block and a five-minute one trade names
      // without either changing length.
      expect(await boundaryOf(ids[0]), at(9));
      expect(await boundaryOf(ids[1]), at(12));
      expect(await boundaryOf(ids[2]), at(15));
    });

    test('the note travels with the activity it describes', () async {
      final ids = await seedDay();
      await changes.setComment(ids[0], 'called Peter');
      await changes.setComment(ids[1], 'wrote it up');

      await controller.swapWithPrevious(ids[1]);

      final rows = await changes.loadChanges();
      expect(rows.firstWhere((c) => c.syncId == ids[0]).comment, 'wrote it up');
      expect(rows.firstWhere((c) => c.syncId == ids[1]).comment, 'called Peter');
    });

    test('doing it twice puts everything back', () async {
      final ids = await seedDay();
      final before = [for (final id in ids) await changes.activityIdsForChange(id)];

      await controller.swapWithPrevious(ids[1]);
      await controller.swapWithPrevious(ids[1]);

      // This is what lets undo be the same call rather than a second unwind
      // path that could disagree with the first.
      expect(await changes.activityIdsForChange(ids[0]), before[0]);
      expect(await changes.activityIdsForChange(ids[1]), before[1]);
    });

    test('both rows come out at one version, above whichever was higher', () async {
      final ids = await seedDay();
      // Give the earlier block a history, so the two sit far apart in version
      // space — the state that lets a peer take the pair apart by being newer
      // than only one of them.
      final d = await activities.createActivity(name: 'D', color: '#666666');
      for (var i = 0; i < 4; i++) {
        await changes.setComment(ids[0], 'note $i');
      }
      await changes.replaceActivityInChange(
        ids[0],
        (await changes.activityIdsForChange(ids[0])).single,
        d.syncId,
      );
      final before = await changes.loadChanges();
      final highest = before.map((c) => c.version).reduce((a, b) => a > b ? a : b);

      await controller.swapWithPrevious(ids[1]);

      final after = await changes.loadChanges();
      final a = after.firstWhere((c) => c.syncId == ids[0]).version;
      final b = after.firstWhere((c) => c.syncId == ids[1]).version;
      expect(a, b);
      expect(a, greaterThan(highest));
    });

    test('both rows are marked for pushing', () async {
      final ids = await seedDay();
      await controller.swapWithPrevious(ids[1]);

      final rows = await changes.loadChanges();
      // The set travels inside the change for sync, so an edit that leaves both
      // versions alone never reaches the other device.
      expect(rows.firstWhere((c) => c.syncId == ids[0]).dirty, isTrue);
      expect(rows.firstWhere((c) => c.syncId == ids[1]).dirty, isTrue);
    });

    test('the earliest block has nothing before it', () async {
      final ids = await seedDay();
      final before = await changes.activityIdsForChange(ids[0]);

      expect(await controller.swapWithPrevious(ids[0]), isNull);
      expect(await changes.activityIdsForChange(ids[0]), before);
    });

    test('it names the pair it traded, so undo does not re-derive one', () async {
      final ids = await seedDay();

      final swapped = await controller.swapWithPrevious(ids[1]);

      expect(swapped, (ids[0], ids[1]));
    });

    test('undo refuses once one of the pair has been merged away', () async {
      final ids = await seedDay();
      final swapped = (await controller.swapWithPrevious(ids[1]))!;
      final survivorSet = await changes.activityIdsForChange(ids[0]);

      // Merging deletes the later block's boundary. Undo still holds both ids,
      // and without a tombstone guard it would move a label back onto the
      // survivor and re-push the deleted row as a fresh edit.
      await controller.mergeIntoPrevious(ids[1]);

      expect(await controller.swapPair(swapped.$1, swapped.$2), isFalse);
      expect(await changes.activityIdsForChange(ids[0]), survivorSet);
    });

    test('undo puts back the pair it was given, not the current neighbour', () async {
      final ids = await seedDay();
      final before = [for (final id in ids) await changes.activityIdsForChange(id)];
      final swapped = (await controller.swapWithPrevious(ids[2]))!;

      // A block lands between the two while the snackbar is up — a relayed
      // switch from the watch looks exactly like this. Re-deriving "the previous
      // block" here would trade with the newcomer and leave the first mistake.
      final d = await activities.createActivity(name: 'D', color: '#666666');
      await controller.switchTo(d.syncId, at: at(13));

      await controller.swapPair(swapped.$1, swapped.$2);

      expect(await changes.activityIdsForChange(ids[1]), before[1]);
      expect(await changes.activityIdsForChange(ids[2]), before[2]);
    });

    test('two blocks carrying the same label are left alone', () async {
      final a = await activities.createActivity(name: 'A', color: '#333333');
      await controller.switchTo(a.syncId, at: at(9));
      await controller.switchTo(a.syncId, at: at(12));
      final ids = (await changes.loadChanges()).reversed.map((c) => c.syncId).toList();
      final versions = {for (final c in await changes.loadChanges()) c.syncId: c.version};

      await controller.swapWithPrevious(ids[1]);

      // Nothing changed, so nothing may be dirtied: otherwise every sync would
      // re-send two identical blocks.
      for (final c in await changes.loadChanges()) {
        expect(c.version, versions[c.syncId], reason: c.syncId);
      }
    });
  });
}

/// Derive the timeline the way the UI does, so edit tests operate on real Blocks.
Future<List<Block>> derivedBlocks(
  DriftChangeRepository changes,
  DriftActivityRepository activities,
  DateTime now,
) async {
  final rows = await changes.loadChanges();
  final links = await changes.watchChangeActivityLinks().first;
  final byChange = <String, List<String>>{};
  for (final l in links) {
    (byChange[l.activityChangeId] ??= []).add(l.activityId);
  }
  return deriveBlocks(
    changes: rows,
    activityIdsByChange: byChange,
    activitiesById: {for (final a in await activities.loadActivities()) a.syncId: a},
  );
}
