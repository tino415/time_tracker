// TrackerController against the real Drift repositories (in-memory): the switch
// action's recency bump and its no-op guard for re-picking what already runs.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/data/drift_repositories.dart';
import 'package:time_tracker/data/tracker_controller.dart';

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
}
