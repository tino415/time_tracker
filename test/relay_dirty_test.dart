// Relay-applied writes are the peer's statements, not this device's edits.
//
// `dirty` means "this device changed it, so it owes the server a push". Applying
// what the phone sent over the Wear relay is not that, and marking it so made
// the watch offer the server rows it had merely been *told about*.
//
// Never a correctness bug — pushes are version-checked and the content comes
// from the phone either way — so nothing observable was wrong, which is exactly
// why it needed a test that looks at the flag rather than at behaviour.
//
// `applyPeerCurrentBlock` already followed this rule ("adopting a peer's state
// is not a local edit"); these pin the two paths that did not.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/data/drift_repositories.dart';
import 'package:time_tracker/data/sync_store.dart';
import 'package:time_tracker/domain/wear_protocol.dart';

void main() {
  late AppDatabase db;
  late DriftActivityRepository activities;
  late SyncStore store;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    activities = DriftActivityRepository(db);
    store = SyncStore(db);
  });

  tearDown(() => db.close());

  /// Everything this device would push on the next sync.
  Future<Set<String>> pending() async =>
      (await store.pendingActivities()).map((a) => a.syncId).toSet();

  /// Whatever a fresh row owes the server, cleared — so what a test *adds* is
  /// the only thing left pending.
  Future<void> settle() async {
    await db.update(db.activities).write(const ActivitiesCompanion(dirty: Value(false)));
  }

  test('a relayed activity arrives owing the server nothing', () async {
    await activities.ensurePeerActivity(
      const WearActivity(syncId: 'peer-1', name: 'Deep work', color: '#4F8FEE'),
    );

    expect(await pending(), isEmpty);
  });

  test('updating a relayed activity does not make it ours', () async {
    await activities.ensurePeerActivity(
      const WearActivity(syncId: 'peer-1', name: 'Deep work', color: '#4F8FEE'),
    );
    await settle();

    // The phone renamed it and re-sent. The watch adopts the new name and still
    // owes nothing: the phone is already pushing this.
    await activities.ensurePeerActivity(
      const WearActivity(syncId: 'peer-1', name: 'Deeper work', color: '#4F8FEE'),
    );

    expect((await activities.loadActivities()).single.name, 'Deeper work');
    expect(await pending(), isEmpty);
  });

  test('a bookmark snapshot leaves nothing to push', () async {
    await activities.applyBookmarkSnapshot(const [
      WearActivity(syncId: 'peer-1', name: 'Deep work', color: '#4F8FEE'),
      WearActivity(syncId: 'peer-2', name: 'Email', color: '#EE7C4F'),
    ]);
    await settle();

    // A second snapshot that changes a name and drops one bookmark — both
    // writes, both the phone's.
    await activities.applyBookmarkSnapshot(const [
      WearActivity(syncId: 'peer-1', name: 'Deeper work', color: '#4F8FEE'),
    ]);

    final rows = await activities.loadActivities();
    expect(rows.firstWhere((a) => a.syncId == 'peer-1').name, 'Deeper work');
    expect(rows.firstWhere((a) => a.syncId == 'peer-2').bookmarked, isFalse);
    expect(await pending(), isEmpty);
  });

  test('this device\'s own edits are still pushed', () async {
    // The other half of the rule: dropping the flag everywhere would be worse
    // than setting it everywhere, because the edit would never leave.
    await activities.ensurePeerActivity(
      const WearActivity(syncId: 'peer-1', name: 'Deep work', color: '#4F8FEE'),
    );
    await settle();

    await activities.renameActivity('peer-1', 'Renamed here');

    expect(await pending(), {'peer-1'});
  });
}
