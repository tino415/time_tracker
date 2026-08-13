// The watch/phone exchange, against the real Drift repositories with a fake
// transport. A real exchange needs two paired devices, so the bridge is the
// seam: everything either side *decides* is exercised here, and only the
// delivery itself is left to the manual pass.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/data/drift_repositories.dart';
import 'package:time_tracker/data/sync_store.dart';
import 'package:time_tracker/data/wear_sync.dart';
import 'package:time_tracker/domain/unsorted.dart';
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
        syncStore: SyncStore(db),
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
      final sent = bridge.sent.whereType<BookmarkSnapshot>().last.current!;
      expect(sent.activity.syncId, a.syncId);
      // The watch needs the boundary itself, not just which activity: it
      // reproduces that change locally and runs its own elapsed clock from it.
      expect(sent.changeId, change.syncId);
      expect(sent.startedAt, change.changedAt);

      // A "forgot to switch" block tracks two activities at once, which the
      // watch cannot represent — it must show nothing rather than arbitrarily
      // picking one.
      await changes.addActivityToChange(change.syncId, b.syncId);
      await bridge.receive(const SnapshotRequest());
      expect(bridge.sent.whereType<BookmarkSnapshot>().last.current, isNull);

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

    test('a change that failed to send is re-sent by the next change', () async {
      // The reported bug: a rename never reached the watch. The push happened
      // while nothing was reachable, the phone recorded that state as sent, and
      // no later edit re-sent it.
      final a = await activities.createActivity(name: 'A', color: '#111111', bookmarked: true);
      final service = serviceFor(isWatch: false);
      await service.start();

      bridge.deliverable = false;
      await activities.renameActivity(a.syncId, 'Renamed while out of range');
      await bridge.pump();
      expect(bridge.sent, isEmpty);

      bridge.deliverable = true;
      await activities.setColor(a.syncId, '#222222');
      await bridge.pump();

      // The rename must be in what finally goes out — the snapshot is a full
      // state, so one delivered push carries every missed edit.
      final snapshot = bridge.sent.whereType<BookmarkSnapshot>().last;
      expect(snapshot.activities.single.name, 'Renamed while out of range');
      service.dispose();
    });

    test('an undelivered snapshot is not remembered as sent', () async {
      await activities.createActivity(name: 'A', color: '#111111', bookmarked: true);
      final service = serviceFor(isWatch: false);
      await service.start();

      bridge.deliverable = false;
      await bridge.receive(const SnapshotRequest());
      expect(bridge.sent, isEmpty);

      // Same state, now reachable: it must go out rather than be deduped away
      // against a push that never landed.
      bridge.deliverable = true;
      await bridge.receive(const SnapshotRequest());
      expect(bridge.sent.whereType<BookmarkSnapshot>(), isNotEmpty);
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
      await bridge.pump();

      expect(bridge.drainCount, 1);
      expect(bridge.sent.single, isA<SnapshotRequest>());
      service.dispose();
    });

    test('keeps asking when the request cannot be delivered', () async {
      // Capability discovery may not be finished when the watch app opens, so
      // the first request goes to nobody. One shot at startup would leave the
      // watch blank until something else happened to trigger a push.
      bridge.deliverable = false;
      final service = serviceFor(isWatch: true);
      await service.start();
      await bridge.pump();
      expect(bridge.sent, isEmpty);

      bridge.deliverable = true;
      // The retry is on a timer; fake_async is not available here, so just check
      // that a reachability event re-asks immediately.
      await bridge.becomes(WearReachability.reachable);
      expect(bridge.sent.whereType<SnapshotRequest>(), isNotEmpty);
      service.dispose();
    });

    test('stops asking once a snapshot arrives', () async {
      final service = serviceFor(isWatch: true);
      await service.start();
      await bridge.pump();
      bridge.sent.clear();

      await bridge.receive(const BookmarkSnapshot(activities: []));
      await bridge.pump();

      // Nothing further: the loop exists to get a first snapshot, not to poll.
      expect(bridge.sent.whereType<SnapshotRequest>(), isEmpty);
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

    test('reproduces the phone\'s current block locally', () async {
      // The bug this exists for: the watch showed "nothing tracked" while the
      // phone was tracking, because the snapshot's current block was decoded
      // and then thrown away.
      final service = serviceFor(isWatch: true);
      await service.start();

      final startedAt = DateTime.fromMillisecondsSinceEpoch(1770000000000);
      await bridge.receive(BookmarkSnapshot(
        activities: const [WearActivity(syncId: 'a', name: 'Deep work', color: '#4F8FEE')],
        current: CurrentBlock(
          changeId: 'phone-change',
          startedAt: startedAt,
          activity: const WearActivity(syncId: 'a', name: 'Deep work', color: '#4F8FEE'),
        ),
      ));

      final rows = await changes.loadChanges();
      expect(rows.single.syncId, 'phone-change');
      // Same instant as the phone's, so the watch's elapsed clock matches
      // rather than restarting from when the snapshot arrived.
      expect(rows.single.changedAt, startedAt);
      expect(await changes.activityIdsForChange('phone-change'), ['a']);

      service.dispose();
    });

    test('tracks an activity the phone has not bookmarked', () async {
      // `activities` carries only bookmarks, so without the activity travelling
      // inside the current block there would be no row to point it at.
      final service = serviceFor(isWatch: true);
      await service.start();

      await bridge.receive(BookmarkSnapshot(
        activities: const [],
        current: CurrentBlock(
          changeId: 'phone-change',
          startedAt: DateTime.fromMillisecondsSinceEpoch(1770000000000),
          activity: const WearActivity(syncId: 'z', name: 'Ad hoc', color: '#123456'),
        ),
      ));

      final local = await activities.loadActivities();
      expect(local.single.syncId, 'z');
      // Tracked is not the same as pinned — it must not appear as a bookmark
      // tile on the watch.
      expect(local.single.bookmarked, isFalse);
      expect(await changes.activityIdsForChange('phone-change'), ['z']);

      service.dispose();
    });

    test('a block named on the phone stops showing as unnamed', () async {
      // The reported bug: start unnamed on the phone, name it, and the watch
      // still said "unnamed". The snapshot re-points the *same* change, and the
      // relayed-switch path skipped it as already applied.
      final service = serviceFor(isWatch: true);
      await service.start();

      final startedAt = DateTime.fromMillisecondsSinceEpoch(1770000000000);
      await bridge.receive(BookmarkSnapshot(
        activities: const [],
        current: CurrentBlock(
          changeId: 'phone-change',
          startedAt: startedAt,
          activity: const WearActivity(
              syncId: kUnsortedActivityId, name: 'Unsorted', color: '#9A9B95'),
        ),
      ));
      expect(await changes.activityIdsForChange('phone-change'), [kUnsortedActivityId]);

      // Named on the phone: same change, different activity.
      await bridge.receive(BookmarkSnapshot(
        activities: const [],
        current: CurrentBlock(
          changeId: 'phone-change',
          startedAt: startedAt,
          activity: const WearActivity(syncId: 'a', name: 'Deep work', color: '#4F8FEE'),
        ),
      ));

      expect(await changes.activityIdsForChange('phone-change'), ['a']);
      // Still one boundary, still at the original instant — naming does not
      // restart the clock.
      final rows = await changes.loadChanges();
      expect(rows, hasLength(1));
      expect(rows.single.changedAt, startedAt);

      service.dispose();
    });

    test('adopts a retimed block without duplicating it', () async {
      final service = serviceFor(isWatch: true);
      await service.start();

      CurrentBlock at(int millis) => CurrentBlock(
            changeId: 'phone-change',
            startedAt: DateTime.fromMillisecondsSinceEpoch(millis),
            activity: const WearActivity(syncId: 'a', name: 'Deep work', color: '#4F8FEE'),
          );

      await bridge.receive(BookmarkSnapshot(activities: const [], current: at(1770000000000)));
      // The phone dragged the boundary in the calendar.
      await bridge.receive(BookmarkSnapshot(activities: const [], current: at(1770000600000)));

      final rows = await changes.loadChanges();
      expect(rows, hasLength(1));
      expect(rows.single.changedAt, DateTime.fromMillisecondsSinceEpoch(1770000600000));
      service.dispose();
    });

    test('re-applying the same snapshot does not open a second boundary', () async {
      final service = serviceFor(isWatch: true);
      await service.start();

      final snapshot = BookmarkSnapshot(
        activities: const [WearActivity(syncId: 'a', name: 'Deep work', color: '#4F8FEE')],
        current: CurrentBlock(
          changeId: 'phone-change',
          startedAt: DateTime.fromMillisecondsSinceEpoch(1770000000000),
          activity: const WearActivity(syncId: 'a', name: 'Deep work', color: '#4F8FEE'),
        ),
      );
      await bridge.receive(snapshot);
      await bridge.receive(snapshot);

      expect(await changes.loadChanges(), hasLength(1));
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

    test('keeps asking after a successful send — delivery is not an answer', () async {
      // The bug that made this feature look broken on two device deploys, and
      // that no test held: the retry stopped when `send` reported true.
      //
      // True only means the peer *device* took the message. That succeeds with
      // the phone app closed, because Android wakes its listener service to
      // receive it — and that service drops snapshot requests rather than
      // replaying stale ones. So the watch asked once into a void, believed it
      // had asked, and never asked again.
      //
      // Slow on purpose: the first retry is two seconds, and the point is what
      // happens *after* a send that succeeded.
      final service = serviceFor(isWatch: true);
      await service.start();
      await pumpEventQueue();

      final asked = bridge.sent.whereType<SnapshotRequest>().length;
      expect(asked, greaterThanOrEqualTo(1));
      expect(bridge.deliverable, isTrue, reason: 'the sends here are succeeding');

      await Future<void>.delayed(const Duration(seconds: 3));
      expect(bridge.sent.whereType<SnapshotRequest>().length, greaterThan(asked),
          reason: 'a delivered but unanswered request must be repeated');

      // A snapshot is an answer, and does stop it.
      await bridge.receive(const BookmarkSnapshot(activities: []));
      final settled = bridge.sent.whereType<SnapshotRequest>().length;
      await Future<void>.delayed(const Duration(seconds: 3));
      expect(bridge.sent.whereType<SnapshotRequest>().length, settled);

      service.dispose();
    });

    test('re-asks for a snapshot when the phone becomes reachable', () async {
      final service = serviceFor(isWatch: true);
      await service.start();
      // The opening request reads the credential version before it sends, so it
      // lands a turn later — clearing without draining first leaves it in flight
      // and it arrives after, looking like a second request.
      await pumpEventQueue();
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
