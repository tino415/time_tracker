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

  test('re-picking the running activity does not open a second boundary', () async {
    final a = await activities.createActivity(name: 'Work', color: '#333333');
    await controller.switchTo(a.syncId);
    final first = await changes.currentChange();

    await controller.switchTo(a.syncId);

    expect((await changes.watchChanges().first).length, 1);
    expect((await changes.currentChange())!.syncId, first!.syncId);
  });

  test('the guard only covers a single-activity block', () async {
    final a = await activities.createActivity(name: 'A', color: '#333333');
    final b = await activities.createActivity(name: 'B', color: '#444444');
    await controller.switchTo(a.syncId);
    // A tagged ("forgot to switch") block tracks two activities, so switching to
    // one of them is a real change: it narrows the set back down to that one.
    await changes.addActivityToChange((await changes.currentChange())!.syncId, b.syncId);

    await controller.switchTo(a.syncId);

    expect((await changes.watchChanges().first).length, 2);
    expect(await changes.activityIdsForChange((await changes.currentChange())!.syncId), [a.syncId]);
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
      await controller.moveBoundary(ids[1], at(7), now: now,
          minBlock: const Duration(minutes: 5));

      expect(await boundaryOf(ids[1]), at(9, 5));
      // Order is preserved, so no block silently changed owner.
      final ascending = (await changes.loadChanges()).reversed.map((c) => c.syncId);
      expect(ascending, ids);
    });

    test('a drag past the next boundary is clamped too', () async {
      final ids = await seedDay();
      await controller.moveBoundary(ids[1], at(18), now: now,
          minBlock: const Duration(minutes: 5));

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
