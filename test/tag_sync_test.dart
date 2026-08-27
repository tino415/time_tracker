// Does tagging a block actually reach the other devices?
//
// The set travels inside its change — there is no independent version on the
// join row — so a tag edit only leaves this device if the *change* is marked
// dirty. setChangeActivity says exactly that and bumps; add/remove do not.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/data/drift_repositories.dart';
import 'package:time_tracker/data/sync_store.dart';

void main() {
  late AppDatabase db;
  late DriftActivityRepository activities;
  late DriftChangeRepository changes;
  late SyncStore store;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    activities = DriftActivityRepository(db);
    changes = DriftChangeRepository(db);
    store = SyncStore(db);
  });

  tearDown(() => db.close());

  /// Everything still owed to the server.
  Future<Set<String>> pending() async =>
      (await store.pendingChanges()).map((c) => c.syncId).toSet();

  /// Pretend the last sync succeeded, so what a test does next is the only
  /// thing outstanding.
  Future<void> synced() async {
    await db.update(db.activityChanges).write(const ActivityChangesCompanion(dirty: Value(false)));
  }

  test('tagging a synced block leaves something to push', () async {
    final a = await activities.createActivity(name: 'A', color: '#111111');
    final b = await activities.createActivity(name: 'B', color: '#222222');
    final change = await changes.switchTo(a.syncId);
    await synced();

    await changes.addActivityToChange(change.syncId, b.syncId);

    // Without this the "forgot to switch" correction lives on one device and
    // every other one keeps showing the block as untagged, forever.
    expect(await pending(), {change.syncId});
  });

  test('untagging a synced block leaves something to push', () async {
    final a = await activities.createActivity(name: 'A', color: '#111111');
    final b = await activities.createActivity(name: 'B', color: '#222222');
    final change = await changes.switchTo(a.syncId);
    await changes.addActivityToChange(change.syncId, b.syncId);
    await synced();

    await changes.removeActivityFromChange(change.syncId, b.syncId);

    expect(await pending(), {change.syncId});
  });

  test('a refused untag pushes nothing', () async {
    // The empty-set guard makes this a no-op, and a no-op must not dirty the
    // row — that would push an unchanged block on every sync.
    final a = await activities.createActivity(name: 'A', color: '#111111');
    final change = await changes.switchTo(a.syncId);
    await synced();

    await changes.removeActivityFromChange(change.syncId, a.syncId);

    expect(await pending(), isEmpty);
  });
}
