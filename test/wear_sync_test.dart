// The watch/phone exchange, against the real Drift repositories with a fake
// transport. A real exchange needs two paired devices, so the bridge is the
// seam: everything either side *decides* is exercised here, and only the
// delivery itself is left to the manual pass.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/data/drift_repositories.dart';
import 'package:time_tracker/data/wear_sync.dart';
import 'package:time_tracker/domain/wear_protocol.dart';

import 'support/fake_wear_bridge.dart';

void main() {
  late AppDatabase db;
  late DriftActivityRepository activities;
  late DriftChangeRepository changes;
  late FakeWearBridge bridge;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    activities = DriftActivityRepository(db);
    changes = DriftChangeRepository(db);
    bridge = FakeWearBridge();
  });

  tearDown(() async {
    bridge.dispose();
    await db.close();
  });

  WearSyncService serviceFor({required bool isWatch}) => WearSyncService(
        bridge: bridge,
        activities: activities,
        changes: changes,
        isWatch: isWatch,
      );

  group('phone side', () {
    test('answers a snapshot request with the bookmarked set', () async {
      final work = await activities.createActivity(
        name: 'Deep work',
        color: '#4F8FEE',
        bookmarked: true,
      );
      await activities.createActivity(name: 'Not bookmarked', color: '#111111');

      final service = serviceFor(isWatch: false);
      await service.start();
      bridge.sent.clear(); // the catalogue stream pushes one on start
      await bridge.receive(const SnapshotRequest());

      final snapshot = bridge.sent.whereType<BookmarkSnapshot>().last;
      expect(snapshot.activities.map((a) => a.syncId), [work.syncId]);
      expect(snapshot.activities.single.name, 'Deep work');
      service.dispose();
    });

    test('reports the running activity, and nothing for a tagged block', () async {
      final a = await activities.createActivity(name: 'A', color: '#111111', bookmarked: true);
      final b = await activities.createActivity(name: 'B', color: '#222222', bookmarked: true);
      final change = await changes.switchTo(a.syncId);

      final service = serviceFor(isWatch: false);
      await service.start();
      await bridge.receive(const SnapshotRequest());
      expect(bridge.sent.whereType<BookmarkSnapshot>().last.currentActivityId, a.syncId);

      // A "forgot to switch" block tracks two activities at once, which the
      // watch cannot represent — it must show nothing selected rather than
      // arbitrarily picking one.
      await changes.addActivityToChange(change.syncId, b.syncId);
      await bridge.receive(const SnapshotRequest());
      expect(bridge.sent.whereType<BookmarkSnapshot>().last.currentActivityId, isNull);

      service.dispose();
    });

    test('applies a relayed switch and bumps recency', () async {
      final a = await activities.createActivity(name: 'A', color: '#111111', bookmarked: true);
      final service = serviceFor(isWatch: false);
      await service.start();

      final at = DateTime.fromMillisecondsSinceEpoch(1770000000000);
      await bridge.receive(SwitchRequest(
        changeSyncId: 'from-watch',
        activityId: a.syncId,
        at: at,
      ));

      final rows = await changes.loadChanges();
      expect(rows.single.syncId, 'from-watch');
      expect(rows.single.changedAt, at);
      expect(await changes.activityIdsForChange('from-watch'), [a.syncId]);
      expect((await activities.loadActivities()).single.lastUsedAt, isNotNull);

      service.dispose();
    });

    test('a switch delivered twice opens one boundary', () async {
      final a = await activities.createActivity(name: 'A', color: '#111111', bookmarked: true);
      final service = serviceFor(isWatch: false);
      await service.start();

      final request = SwitchRequest(
        changeSyncId: 'from-watch',
        activityId: a.syncId,
        at: DateTime.fromMillisecondsSinceEpoch(1770000000000),
      );
      // Once live, once replayed out of the native queue after a restart.
      await bridge.receive(request);
      await bridge.receive(request);

      expect((await changes.loadChanges()).length, 1);
      service.dispose();
    });

    test('a switch naming an unknown activity is ignored, not half-applied', () async {
      final service = serviceFor(isWatch: false);
      await service.start();

      await bridge.receive(SwitchRequest(
        changeSyncId: 'from-watch',
        activityId: 'deleted-since',
        at: DateTime.fromMillisecondsSinceEpoch(1770000000000),
      ));

      expect(await changes.loadChanges(), isEmpty);
      service.dispose();
    });

    test('re-sends the snapshot when the peer becomes reachable', () async {
      await activities.createActivity(name: 'A', color: '#111111', bookmarked: true);
      final service = serviceFor(isWatch: false);
      await service.start();
      bridge.sent.clear();

      await bridge.becomes(WearReachability.reachable);

      expect(bridge.sent.whereType<BookmarkSnapshot>(), isNotEmpty);
      service.dispose();
    });
  });

  group('watch side', () {
    test('asks for a snapshot on start, and drains the native queue', () async {
      final service = serviceFor(isWatch: true);
      await service.start();

      expect(bridge.drainCount, 1);
      expect(bridge.sent.single, isA<SnapshotRequest>());
      service.dispose();
    });

    test('adopts a snapshot into the local catalogue', () async {
      final service = serviceFor(isWatch: true);
      await service.start();

      await bridge.receive(const BookmarkSnapshot(activities: [
        WearActivity(syncId: 'a', name: 'Deep work', color: '#4F8FEE'),
        WearActivity(syncId: 'b', name: 'Email', color: '#EE7C4F'),
      ]));

      final local = await activities.loadActivities();
      expect(local.map((a) => a.syncId).toSet(), {'a', 'b'});
      expect(local.every((a) => a.bookmarked), isTrue);
      service.dispose();
    });

    test('a later snapshot updates names and drops removed bookmarks', () async {
      final service = serviceFor(isWatch: true);
      await service.start();

      await bridge.receive(const BookmarkSnapshot(activities: [
        WearActivity(syncId: 'a', name: 'Deep work', color: '#4F8FEE'),
        WearActivity(syncId: 'b', name: 'Email', color: '#EE7C4F'),
      ]));
      await bridge.receive(const BookmarkSnapshot(activities: [
        WearActivity(syncId: 'a', name: 'Focus', color: '#000000'),
      ]));

      final local = {for (final a in await activities.loadActivities()) a.syncId: a};
      expect(local['a']!.name, 'Focus');
      expect(local['a']!.color, '#000000');
      expect(local['a']!.bookmarked, isTrue);
      // Still present — the snapshot says what is bookmarked, not what exists.
      expect(local['b']!.bookmarked, isFalse);
      expect(local['b']!.deletedAt, isNull);

      service.dispose();
    });

    test('an unchanged snapshot does not churn versions', () async {
      final service = serviceFor(isWatch: true);
      await service.start();

      const snapshot = BookmarkSnapshot(activities: [
        WearActivity(syncId: 'a', name: 'Deep work', color: '#4F8FEE'),
      ]);
      await bridge.receive(snapshot);
      final first = (await activities.loadActivities()).single.version;
      await bridge.receive(snapshot);

      // Every reconnect re-sends the set; bumping version each time would make
      // every activity look freshly edited to a future sync.
      expect((await activities.loadActivities()).single.version, first);
      service.dispose();
    });

    test('a tap writes locally and relays under the same id', () async {
      final service = serviceFor(isWatch: true);
      await service.start();
      await bridge.receive(const BookmarkSnapshot(activities: [
        WearActivity(syncId: 'a', name: 'Deep work', color: '#4F8FEE'),
      ]));
      bridge.sent.clear();

      await service.requestSwitch('a', at: DateTime.fromMillisecondsSinceEpoch(1770000000000));

      final local = await changes.loadChanges();
      expect(local, hasLength(1));
      final relayed = bridge.sent.whereType<SwitchRequest>().single;
      // Same id on both sides: that is what makes the phone's apply idempotent
      // and lets the two databases converge on one row.
      expect(relayed.changeSyncId, local.single.syncId);
      expect(relayed.activityId, 'a');
      expect(relayed.at, local.single.changedAt);

      service.dispose();
    });

    test('a tap still records locally when the phone is unreachable', () async {
      // The fake accepts sends regardless; the real bridge swallows the failure.
      // Either way the local row must exist, so the watch shows the truth and a
      // later sync can reconcile.
      final service = serviceFor(isWatch: true);
      await service.start();
      await bridge.receive(const BookmarkSnapshot(activities: [
        WearActivity(syncId: 'a', name: 'Deep work', color: '#4F8FEE'),
      ]));

      await service.requestSwitch('a');

      expect(await changes.loadChanges(), hasLength(1));
      service.dispose();
    });

    test('re-asks for a snapshot when the phone becomes reachable', () async {
      final service = serviceFor(isWatch: true);
      await service.start();
      bridge.sent.clear();

      await bridge.becomes(WearReachability.reachable);
      expect(bridge.sent.whereType<SnapshotRequest>(), hasLength(1));

      // Losing the peer is not a reason to send anything.
      bridge.sent.clear();
      await bridge.becomes(WearReachability.notPaired);
      expect(bridge.sent, isEmpty);

      service.dispose();
    });

    test('applies messages the native queue parked while the app was dead', () async {
      bridge.pending = [
        const BookmarkSnapshot(activities: [
          WearActivity(syncId: 'a', name: 'Deep work', color: '#4F8FEE'),
        ]),
      ];

      final service = serviceFor(isWatch: true);
      await service.start();
      await bridge.pump();

      expect((await activities.loadActivities()).single.syncId, 'a');
      service.dispose();
    });
  });
}
