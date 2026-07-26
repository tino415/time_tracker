// Integration tests for the Drift repositories against an in-memory database —
// verifies switch / tag / untag / soft-delete and the reactive join stream that
// feeds block derivation.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/data/drift_repositories.dart';

void main() {
  late AppDatabase db;
  late DriftActivityRepository activities;
  late DriftChangeRepository changes;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    activities = DriftActivityRepository(db);
    changes = DriftChangeRepository(db);
  });

  tearDown(() => db.close());

  test('createActivity + watch returns live rows in name order', () async {
    await activities.createActivity(name: 'Beta', color: '#111111');
    await activities.createActivity(name: 'Alpha', color: '#222222');
    final list = await activities.loadActivities();
    expect(list.map((a) => a.name), ['Alpha', 'Beta']);
  });

  test('switchTo opens a change with the single activity as its set', () async {
    final a = await activities.createActivity(name: 'Work', color: '#333333');
    final change = await changes.switchTo(a.syncId);

    final current = await changes.currentChange();
    expect(current!.syncId, change.syncId);
    expect(await changes.activityIdsForChange(change.syncId), [a.syncId]);
  });

  test('addActivityToChange tags a block; untag respects the last-one guard', () async {
    final a = await activities.createActivity(name: 'A', color: '#333333');
    final b = await activities.createActivity(name: 'B', color: '#444444');
    final change = await changes.switchTo(a.syncId);

    await changes.addActivityToChange(change.syncId, b.syncId);
    expect((await changes.activityIdsForChange(change.syncId)).toSet(), {a.syncId, b.syncId});

    // Adding again is idempotent (insertOrIgnore on the composite PK).
    await changes.addActivityToChange(change.syncId, b.syncId);
    expect((await changes.activityIdsForChange(change.syncId)).length, 2);

    await changes.removeActivityFromChange(change.syncId, b.syncId);
    expect(await changes.activityIdsForChange(change.syncId), [a.syncId]);

    // The last activity cannot be removed — a block always tracks something.
    await changes.removeActivityFromChange(change.syncId, a.syncId);
    expect(await changes.activityIdsForChange(change.syncId), [a.syncId]);
  });

  test('deleteChange soft-deletes (tombstone) and drops it from the live stream', () async {
    final a = await activities.createActivity(name: 'A', color: '#333333');
    final c1 = await changes.switchTo(a.syncId, at: DateTime(2026, 1, 5, 9));
    await changes.switchTo(a.syncId, at: DateTime(2026, 1, 5, 10));

    await changes.deleteChange(c1.syncId);
    final live = await changes.watchChanges().first;
    expect(live.map((c) => c.syncId), isNot(contains(c1.syncId)));
    expect(live.length, 1);
  });

  test('edits bump version for LWW sync', () async {
    final a = await activities.createActivity(name: 'A', color: '#333333');
    expect(a.version, 1);
    await activities.renameActivity(a.syncId, 'A2');
    final after = (await activities.loadActivities()).single;
    expect(after.name, 'A2');
    expect(after.version, 2);
  });

  test('setBookmarked / touchUsed round-trip', () async {
    final a = await activities.createActivity(name: 'A', color: '#333333');
    await activities.setBookmarked(a.syncId, true);
    final used = DateTime(2026, 1, 5, 12);
    await activities.touchUsed(a.syncId, used);
    final after = (await activities.loadActivities()).single;
    expect(after.bookmarked, isTrue);
    expect(after.lastUsedAt, used);
  });

  test('watchChangeActivityLinks reflects tags reactively', () async {
    final a = await activities.createActivity(name: 'A', color: '#333333');
    final b = await activities.createActivity(name: 'B', color: '#444444');
    final change = await changes.switchTo(a.syncId);
    await changes.addActivityToChange(change.syncId, b.syncId);

    final links = await changes.watchChangeActivityLinks().first;
    expect(links.where((l) => l.activityChangeId == change.syncId).map((l) => l.activityId).toSet(),
        {a.syncId, b.syncId});
  });
}
