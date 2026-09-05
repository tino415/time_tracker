// The watch/phone exchange, against the real Drift repositories with a fake
// transport. A real exchange needs two paired devices, so the bridge is the
// seam: everything either side *decides* is exercised here, and only the
// delivery itself is left to the manual pass.

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/data/drift_repositories.dart';
import 'package:time_tracker/data/sync_store.dart';
import 'package:time_tracker/data/wear_outbox.dart';
import 'package:time_tracker/data/wear_sync.dart';
import 'package:time_tracker/domain/unsorted.dart';
import 'package:time_tracker/domain/wear_protocol.dart';

import 'support/fake_wear_bridge.dart';

void main() {
  // One test pairs a watch database with a phone one, each on its own executor,
  // so drift's shared-executor warning does not apply. Same reason as
  // sync_service_test.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

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

  WearSyncService serviceFor({required bool isWatch, Future<void> Function()? onSyncRequested}) =>
      WearSyncService(
        bridge: bridge,
        activities: activities,
        changes: changes,
        syncStore: SyncStore(db),
        outbox: WearOutboxStore(db),
        isWatch: isWatch,
        onSyncRequested: onSyncRequested,
      );

  group('phone side', () {
    test('syncs when the watch asks it to', () async {
      // The watch's fallback for having no network of its own. The phone runs
      // the round trip its own manual button would.
      var runs = 0;
      final service = serviceFor(isWatch: false, onSyncRequested: () async => runs++);
      await service.start();

      await bridge.receive(const SyncNowRequest());

      expect(runs, 1);
      service.dispose();
    });

    test('a sync request on a build with no backend is inert', () async {
      // Nothing to sync to, so no handler is wired in. Arriving anyway has to be
      // survivable rather than fatal — the peer may be a build that has one.
      final service = serviceFor(isWatch: false);
      await service.start();

      await bridge.receive(const SyncNowRequest());

      // Absorbed: nothing is sent in reply, and nothing is thrown.
      expect(bridge.sent.whereType<SyncNowRequest>(), isEmpty);
      service.dispose();
    });

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

    test('the snapshot carries the block\'s version, not just its instant', () async {
      final a = await activities.createActivity(name: 'A', color: '#111111', bookmarked: true);
      final change = await changes.switchTo(a.syncId);
      // A block the phone has already worked on, so its version is somewhere
      // the watch could not have guessed.
      for (var i = 0; i < 5; i++) {
        await changes.setComment(change.syncId, 'note $i');
      }
      final stored = (await changes.changeById(change.syncId))!;

      final service = serviceFor(isWatch: false);
      await service.start();
      await bridge.receive(const SnapshotRequest());

      final sent = bridge.sent.whereType<BookmarkSnapshot>().last.current!;
      expect(stored.version, greaterThan(1));
      expect(sent.version, stored.version);
      service.dispose();
    });

    test('applies a relayed switch and bumps recency', () async {
      final a = await activities.createActivity(name: 'A', color: '#111111', bookmarked: true);
      final service = serviceFor(isWatch: false);
      await service.start();

      final at = DateTime.fromMillisecondsSinceEpoch(1770000000000);
      await bridge.receive(SwitchRequest(changeSyncId: 'from-watch', activityId: a.syncId, at: at));

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

      await bridge.receive(
        SwitchRequest(
          changeSyncId: 'from-watch',
          activityId: 'deleted-since',
          at: DateTime.fromMillisecondsSinceEpoch(1770000000000),
        ),
      );

      expect(await changes.loadChanges(), isEmpty);
      service.dispose();
    });

    test('applies a relayed assign', () async {
      final a = await activities.createActivity(name: 'A', color: '#111111', bookmarked: true);
      final b = await activities.createActivity(name: 'B', color: '#222222', bookmarked: true);
      final change = await changes.switchTo(a.syncId);
      final service = serviceFor(isWatch: false);
      await service.start();

      await bridge.receive(
        AssignRequest(changeSyncId: change.syncId, activityId: b.syncId, version: 2),
      );

      expect(await changes.activityIdsForChange(change.syncId), [b.syncId]);
      service.dispose();
    });

    test('applies a relayed retime', () async {
      final a = await activities.createActivity(name: 'A', color: '#111111', bookmarked: true);
      final change = await changes.switchTo(
        a.syncId,
        at: DateTime.fromMillisecondsSinceEpoch(1770000000000),
      );
      final service = serviceFor(isWatch: false);
      await service.start();

      final at = DateTime.fromMillisecondsSinceEpoch(1770000300000);
      await bridge.receive(RetimeRequest(changeSyncId: change.syncId, at: at, version: 2));

      expect((await changes.loadChanges()).single.changedAt, at);
      service.dispose();
    });

    test('a retime that would cross the previous boundary is clamped, not applied raw', () async {
      // The watch can be working from a stale snapshot, so trusting its math
      // could reorder two blocks that are already on the record. Clamping has
      // to happen again here, on receipt, not just on the watch that sent it.
      final a = await activities.createActivity(name: 'A', color: '#111111', bookmarked: true);
      final b = await activities.createActivity(name: 'B', color: '#222222', bookmarked: true);
      await changes.switchTo(a.syncId, at: DateTime.fromMillisecondsSinceEpoch(1770000000000));
      final second = await changes.switchTo(
        b.syncId,
        at: DateTime.fromMillisecondsSinceEpoch(1770000600000), // 10 minutes later
      );

      final service = serviceFor(isWatch: false);
      await service.start();

      // Ask to drag the second boundary to well before the first one.
      await bridge.receive(
        RetimeRequest(
          changeSyncId: second.syncId,
          at: DateTime.fromMillisecondsSinceEpoch(1769999000000),
          version: 2,
        ),
      );

      final rows = {for (final c in await changes.loadChanges()) c.syncId: c};
      // Clamped to just after the earlier boundary, not the raw requested
      // instant, and never crossing it into the earlier block.
      expect(rows[second.syncId]!.changedAt, DateTime.fromMillisecondsSinceEpoch(1770000060000));
      service.dispose();
    });

    test('an assign delivered twice re-points once', () async {
      final a = await activities.createActivity(name: 'A', color: '#111111', bookmarked: true);
      final b = await activities.createActivity(name: 'B', color: '#222222', bookmarked: true);
      final change = await changes.switchTo(a.syncId);
      final service = serviceFor(isWatch: false);
      await service.start();

      final request = AssignRequest(changeSyncId: change.syncId, activityId: b.syncId, version: 2);
      await bridge.receive(request);
      await bridge.receive(request);

      expect(await changes.activityIdsForChange(change.syncId), [b.syncId]);
      service.dispose();
    });

    test('a retime delivered twice lands once, not drifting further each time', () async {
      // The absolute timestamp is what makes a queue replay safe — this proves
      // that property rather than trusting the idea behind it.
      final a = await activities.createActivity(name: 'A', color: '#111111', bookmarked: true);
      final change = await changes.switchTo(
        a.syncId,
        at: DateTime.fromMillisecondsSinceEpoch(1770000000000),
      );
      final service = serviceFor(isWatch: false);
      await service.start();

      final request = RetimeRequest(
        changeSyncId: change.syncId,
        at: DateTime.fromMillisecondsSinceEpoch(1770000300000),
        version: 2,
      );
      await bridge.receive(request);
      await bridge.receive(request);

      expect(
        (await changes.loadChanges()).single.changedAt,
        DateTime.fromMillisecondsSinceEpoch(1770000300000),
      );
      service.dispose();
    });

    test('an assign naming an unknown change is a no-op, not a crash', () async {
      final a = await activities.createActivity(name: 'A', color: '#111111', bookmarked: true);
      final service = serviceFor(isWatch: false);
      await service.start();

      await bridge.receive(
        AssignRequest(changeSyncId: 'missing', activityId: a.syncId, version: 2),
      );

      expect(await changes.loadChanges(), isEmpty);
      service.dispose();
    });

    test('a retime naming an unknown change is a no-op, not a crash', () async {
      final service = serviceFor(isWatch: false);
      await service.start();

      await bridge.receive(
        RetimeRequest(
          changeSyncId: 'missing',
          at: DateTime.fromMillisecondsSinceEpoch(1770000000000),
          version: 2,
        ),
      );

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

    test('caches every snapshot it builds, including one that failed to send', () async {
      // The cache is what WearListenerService answers a snapshot_request from
      // while the app is dead, so a push that never reached the watch still
      // has to leave the best available answer on disk — delivery tracking is
      // about when to re-send, not about what belongs in the cache.
      await activities.createActivity(name: 'A', color: '#111111', bookmarked: true);
      bridge.deliverable = false;
      final service = serviceFor(isWatch: false);
      await service.start();
      await bridge.pump();

      expect(bridge.sent, isEmpty);
      expect(bridge.cached, isNotEmpty);
      final cached = bridge.cached.last;
      expect((cached['activities'] as List).single, {
        'syncId': anything,
        'name': 'A',
        'color': '#111111',
      });
      service.dispose();
    });

    test('caches current: null for a multi-activity block, same as it sends', () async {
      final a = await activities.createActivity(name: 'A', color: '#111111', bookmarked: true);
      final b = await activities.createActivity(name: 'B', color: '#222222', bookmarked: true);
      final change = await changes.switchTo(a.syncId);
      await changes.addActivityToChange(change.syncId, b.syncId);

      final service = serviceFor(isWatch: false);
      await service.start();
      await bridge.pump();

      expect(bridge.cached, isNotEmpty);
      expect(bridge.cached.last['current'], isNull);
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

      await bridge.receive(
        const BookmarkSnapshot(
          activities: [
            WearActivity(syncId: 'a', name: 'Deep work', color: '#4F8FEE'),
            WearActivity(syncId: 'b', name: 'Email', color: '#EE7C4F'),
          ],
        ),
      );

      final local = await activities.loadActivities();
      expect(local.map((a) => a.syncId).toSet(), {'a', 'b'});
      expect(local.every((a) => a.bookmarked), isTrue);
      service.dispose();
    });

    test('switching to a snapshot activity offers the server nothing', () async {
      // A snapshot carries name and colour only, so an adopted row's parentId is
      // null — a gap in what the watch was told, not a fact about the activity.
      // The recency bump that rides along with a switch marked the row dirty,
      // which offered that gap to the server as this device's own edit; the push
      // is version-LWW, so it won, and the parent link the phone set was gone.
      //
      // Cosmetic until the watch could sync on its own. With a sync button it is
      // one tap from routine, which is why this is pinned before the button.
      final service = serviceFor(isWatch: true);
      await service.start();
      await bridge.receive(
        const BookmarkSnapshot(
          activities: [WearActivity(syncId: 'a', name: 'Deep work', color: '#4F8FEE')],
        ),
      );

      await service.requestSwitch('a');

      final pending = await SyncStore(db).pendingActivities();
      expect(pending.map((a) => a.syncId), isNot(contains('a')));
      service.dispose();
    });

    test('asks the phone to sync when it has no route out', () async {
      final service = serviceFor(isWatch: true);
      await service.start();
      await bridge.pump(); // the snapshot request start() sends
      bridge.sent.clear();

      await service.requestSyncNow();

      expect(bridge.sent.whereType<SyncNowRequest>(), hasLength(1));
      service.dispose();
    });

    test('ignores a sync request, rather than bouncing it back', () async {
      // The watch is the device least likely to have a network. Honouring the
      // request here would hand the round trip to it, which is the wrong way
      // round and would loop against a phone doing the same.
      var runs = 0;
      final service = serviceFor(isWatch: true, onSyncRequested: () async => runs++);
      await service.start();

      await bridge.receive(const SyncNowRequest());

      expect(runs, 0);
      service.dispose();
    });

    test('reproduces the phone\'s current block locally', () async {
      // The bug this exists for: the watch showed "nothing tracked" while the
      // phone was tracking, because the snapshot's current block was decoded
      // and then thrown away.
      final service = serviceFor(isWatch: true);
      await service.start();

      final startedAt = DateTime.fromMillisecondsSinceEpoch(1770000000000);
      await bridge.receive(
        BookmarkSnapshot(
          activities: const [WearActivity(syncId: 'a', name: 'Deep work', color: '#4F8FEE')],
          current: CurrentBlock(
            changeId: 'phone-change',
            startedAt: startedAt,
            activity: const WearActivity(syncId: 'a', name: 'Deep work', color: '#4F8FEE'),
          ),
        ),
      );

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

      await bridge.receive(
        BookmarkSnapshot(
          activities: const [],
          current: CurrentBlock(
            changeId: 'phone-change',
            startedAt: DateTime.fromMillisecondsSinceEpoch(1770000000000),
            activity: const WearActivity(syncId: 'z', name: 'Ad hoc', color: '#123456'),
          ),
        ),
      );

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
      await bridge.receive(
        BookmarkSnapshot(
          activities: const [],
          current: CurrentBlock(
            changeId: 'phone-change',
            startedAt: startedAt,
            activity: const WearActivity(
              syncId: kUnsortedActivityId,
              name: 'Unsorted',
              color: '#9A9B95',
            ),
          ),
        ),
      );
      expect(await changes.activityIdsForChange('phone-change'), [kUnsortedActivityId]);

      // Named on the phone: same change, different activity.
      await bridge.receive(
        BookmarkSnapshot(
          activities: const [],
          current: CurrentBlock(
            changeId: 'phone-change',
            startedAt: startedAt,
            activity: const WearActivity(syncId: 'a', name: 'Deep work', color: '#4F8FEE'),
          ),
        ),
      );

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

    test('seeds the block on the sender\'s version, not the column default', () async {
      final service = serviceFor(isWatch: true);
      await service.start();

      await bridge.receive(
        BookmarkSnapshot(
          activities: const [],
          current: CurrentBlock(
            changeId: 'phone-change',
            startedAt: DateTime.fromMillisecondsSinceEpoch(1770000000000),
            version: 7,
            activity: const WearActivity(syncId: 'a', name: 'Deep work', color: '#4F8FEE'),
          ),
        ),
      );

      expect((await changes.changeById('phone-change'))!.version, 7);
      service.dispose();
    });

    test('a later snapshot raises the version, an older one does not lower it', () async {
      final service = serviceFor(isWatch: true);
      await service.start();

      CurrentBlock at(int version) => CurrentBlock(
        changeId: 'phone-change',
        startedAt: DateTime.fromMillisecondsSinceEpoch(1770000000000),
        version: version,
        activity: const WearActivity(syncId: 'a', name: 'Deep work', color: '#4F8FEE'),
      );

      await bridge.receive(BookmarkSnapshot(activities: const [], current: at(3)));
      await bridge.receive(BookmarkSnapshot(activities: const [], current: at(5)));
      expect((await changes.changeById('phone-change'))!.version, 5);

      // A snapshot that crossed with a correction made here is behind it, and
      // must not cost that correction its rank before it has been relayed.
      await bridge.receive(BookmarkSnapshot(activities: const [], current: at(4)));
      expect((await changes.changeById('phone-change'))!.version, 5);

      service.dispose();
    });

    test('a snapshot from a peer that sends no version leaves the version alone', () async {
      // An older phone against a newer watch: the snapshot is still worth
      // drawing, so the block is taken without one rather than refused.
      final service = serviceFor(isWatch: true);
      await service.start();

      await bridge.receive(
        BookmarkSnapshot(
          activities: const [],
          current: CurrentBlock(
            changeId: 'phone-change',
            startedAt: DateTime.fromMillisecondsSinceEpoch(1770000000000),
            activity: const WearActivity(syncId: 'a', name: 'Deep work', color: '#4F8FEE'),
          ),
        ),
      );

      final row = (await changes.changeById('phone-change'))!;
      expect(row.changedAt, DateTime.fromMillisecondsSinceEpoch(1770000000000));
      expect(row.version, 1);
      service.dispose();
    });

    test('a correction to a block learned from a snapshot is not refused as stale', () async {
      // The whole point of seeding the version. The phone is at 6 on a block it
      // has been editing; the watch learns that block from a snapshot and
      // nudges its start. Seeded at the column default the watch would relay
      // version 2, the phone would read it as five edits behind its own, and
      // the correction would be dropped — every time, for good.
      final phoneDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(phoneDb.close);
      final phoneActivities = DriftActivityRepository(phoneDb);
      final phoneChanges = DriftChangeRepository(phoneDb);

      final work = await phoneActivities.createActivity(name: 'Deep work', color: '#4F8FEE');
      final onPhone = await phoneChanges.switchTo(
        work.syncId,
        at: DateTime.fromMillisecondsSinceEpoch(1770000000000),
      );
      for (var i = 0; i < 5; i++) {
        await phoneChanges.setComment(onPhone.syncId, 'note $i');
      }
      final before = (await phoneChanges.changeById(onPhone.syncId))!;

      final service = serviceFor(isWatch: true);
      await service.start();
      await bridge.receive(
        BookmarkSnapshot(
          activities: const [],
          current: CurrentBlock(
            changeId: before.syncId,
            startedAt: before.changedAt,
            version: before.version,
            activity: WearActivity(syncId: work.syncId, name: 'Deep work', color: '#4F8FEE'),
          ),
        ),
      );
      bridge.sent.clear();

      final nudged = before.changedAt.subtract(const Duration(minutes: 5));
      await service.requestRetime(changeSyncId: before.syncId, at: nudged);

      final relayed = bridge.sent.whereType<RetimeRequest>().single;
      expect(relayed.version, before.version + 1);

      // The phone's own rows are dirty on a pair with no account, so an equal
      // version would lose the tie. Only a genuinely newer one gets through.
      final adopted = await phoneChanges.applyRelayedRetime(
        changeSyncId: relayed.changeSyncId,
        at: relayed.at,
        version: relayed.version,
      );
      expect(adopted, isTrue);
      expect((await phoneChanges.changeById(onPhone.syncId))!.changedAt, nudged);

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

      await bridge.receive(
        const BookmarkSnapshot(
          activities: [
            WearActivity(syncId: 'a', name: 'Deep work', color: '#4F8FEE'),
            WearActivity(syncId: 'b', name: 'Email', color: '#EE7C4F'),
          ],
        ),
      );
      await bridge.receive(
        const BookmarkSnapshot(
          activities: [WearActivity(syncId: 'a', name: 'Focus', color: '#000000')],
        ),
      );

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

      const snapshot = BookmarkSnapshot(
        activities: [WearActivity(syncId: 'a', name: 'Deep work', color: '#4F8FEE')],
      );
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
      await bridge.receive(
        const BookmarkSnapshot(
          activities: [WearActivity(syncId: 'a', name: 'Deep work', color: '#4F8FEE')],
        ),
      );
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

    test('requestAssign re-points the local block and relays an AssignRequest', () async {
      final service = serviceFor(isWatch: true);
      await service.start();
      await bridge.receive(
        const BookmarkSnapshot(
          activities: [
            WearActivity(syncId: 'a', name: 'Deep work', color: '#4F8FEE'),
            WearActivity(syncId: 'b', name: 'Email', color: '#EE7C4F'),
          ],
        ),
      );
      await service.requestSwitch('a', at: DateTime.fromMillisecondsSinceEpoch(1770000000000));
      final changeId = (await changes.loadChanges()).single.syncId;
      bridge.sent.clear();

      await service.requestAssign(changeSyncId: changeId, activityId: 'b');

      expect(await changes.activityIdsForChange(changeId), ['b']);
      final relayed = bridge.sent.whereType<AssignRequest>().single;
      // Same id as the local row, the same reason SwitchRequest's does: it is
      // what lets the phone's apply land on this row rather than a new one.
      expect(relayed.changeSyncId, changeId);
      expect(relayed.activityId, 'b');

      service.dispose();
    });

    test('requestRetime moves the local start and relays a RetimeRequest', () async {
      final service = serviceFor(isWatch: true);
      await service.start();
      await bridge.receive(
        const BookmarkSnapshot(
          activities: [WearActivity(syncId: 'a', name: 'Deep work', color: '#4F8FEE')],
        ),
      );
      final start = DateTime.fromMillisecondsSinceEpoch(1770000000000);
      await service.requestSwitch('a', at: start);
      final changeId = (await changes.loadChanges()).single.syncId;
      bridge.sent.clear();

      final retimed = start.subtract(const Duration(minutes: 5));
      await service.requestRetime(changeSyncId: changeId, at: retimed);

      expect((await changes.loadChanges()).single.changedAt, retimed);
      final relayed = bridge.sent.whereType<RetimeRequest>().single;
      expect(relayed.changeSyncId, changeId);
      expect(relayed.at, retimed);

      service.dispose();
    });

    test('a tap still records locally when the phone is unreachable', () async {
      // The fake accepts sends regardless; the real bridge swallows the failure.
      // Either way the local row must exist, so the watch shows the truth and a
      // later sync can reconcile.
      final service = serviceFor(isWatch: true);
      await service.start();
      await bridge.receive(
        const BookmarkSnapshot(
          activities: [WearActivity(syncId: 'a', name: 'Deep work', color: '#4F8FEE')],
        ),
      );

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
      expect(
        bridge.sent.whereType<SnapshotRequest>().length,
        greaterThan(asked),
        reason: 'a delivered but unanswered request must be repeated',
      );

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

    test('caches its own state on a local change, without sending anything', () async {
      // The watch has nobody to push a snapshot to, but a widget or watch-face
      // complication reads this cache the same way the phone's
      // WearListenerService does — so a local tap has to land there too.
      final service = serviceFor(isWatch: true);
      await service.start();
      await bridge.pump();
      bridge.cached.clear();

      await service.startUnsorted();
      await bridge.pump();

      expect(bridge.cached, isNotEmpty);
      final cached = bridge.cached.last['current'] as Map;
      expect(cached['activity'], {
        'syncId': kUnsortedActivityId,
        'name': anything,
        'color': anything,
      });
      expect(bridge.sent.whereType<BookmarkSnapshot>(), isEmpty);
      service.dispose();
    });

    test('applies messages the native queue parked while the app was dead', () async {
      bridge.pending = [
        const BookmarkSnapshot(
          activities: [WearActivity(syncId: 'a', name: 'Deep work', color: '#4F8FEE')],
        ),
      ];

      final service = serviceFor(isWatch: true);
      await service.start();
      await bridge.pump();

      expect((await activities.loadActivities()).single.syncId, 'a');
      service.dispose();
    });
  });

  // What happens to a tap made out of range. Before the outbox these were
  // written locally and then dropped on the floor: `send` reported them
  // undelivered and every caller ignored the answer. On a pair with no sync
  // account — which is every pair until someone makes one — the relay is the
  // only route between the two databases, so dropped meant lost.
  group('watch side, out of range', () {
    late WearOutboxStore outbox;

    setUp(() => outbox = WearOutboxStore(db));

    /// A started watch service with the peer already gone.
    Future<WearSyncService> unreachableWatch() async {
      final service = serviceFor(isWatch: true);
      await service.start();
      await bridge.pump();
      bridge.deliverable = false;
      bridge.sent.clear();
      return service;
    }

    test('a switch made with nobody listening is parked, not lost', () async {
      final a = await activities.createActivity(name: 'A', color: '#111111', bookmarked: true);
      final service = await unreachableWatch();

      await service.requestSwitch(a.syncId);

      expect(bridge.sent, isEmpty, reason: 'there was nobody to send it to');
      expect(await outbox.pending(), hasLength(1));
      // And it is already true locally — the watch's own screen was never
      // waiting on the phone.
      expect((await changes.loadChanges()).single.syncId, isNotEmpty);
      service.dispose();
    });

    test('the backlog goes out when the peer comes back', () async {
      final a = await activities.createActivity(name: 'A', color: '#111111', bookmarked: true);
      final service = await unreachableWatch();
      await service.requestSwitch(a.syncId);

      bridge.deliverable = true;
      await bridge.becomes(WearReachability.reachable);

      expect(bridge.sent.whereType<SwitchRequest>(), hasLength(1));
      expect(await outbox.pending(), isEmpty, reason: 'delivered, so no longer parked');
      service.dispose();
    });

    test('a second reconnect does not send it again', () async {
      final a = await activities.createActivity(name: 'A', color: '#111111', bookmarked: true);
      final service = await unreachableWatch();
      await service.requestSwitch(a.syncId);

      bridge.deliverable = true;
      await bridge.becomes(WearReachability.reachable);
      await bridge.becomes(WearReachability.reachable);

      expect(bridge.sent.whereType<SwitchRequest>(), hasLength(1));
      service.dispose();
    });

    test('two taps made out of range arrive in the order they were made', () async {
      final a = await activities.createActivity(name: 'A', color: '#111111', bookmarked: true);
      final b = await activities.createActivity(name: 'B', color: '#222222', bookmarked: true);
      final service = await unreachableWatch();

      await service.requestSwitch(a.syncId, at: DateTime.fromMillisecondsSinceEpoch(1770000000000));
      await service.requestSwitch(b.syncId, at: DateTime.fromMillisecondsSinceEpoch(1770000060000));

      bridge.deliverable = true;
      await bridge.becomes(WearReachability.reachable);

      final relayed = bridge.sent.whereType<SwitchRequest>().toList();
      expect(relayed.map((m) => m.activityId), [a.syncId, b.syncId]);
      service.dispose();
    });

    test('a peer that disappears mid-drain leaves the rest parked', () async {
      final a = await activities.createActivity(name: 'A', color: '#111111', bookmarked: true);
      final service = await unreachableWatch();
      await service.requestSwitch(a.syncId, at: DateTime.fromMillisecondsSinceEpoch(1770000000000));
      await service.requestSwitch(a.syncId, at: DateTime.fromMillisecondsSinceEpoch(1770000060000));
      expect(await outbox.pending(), hasLength(2));

      // Reachable long enough for one message, then gone again.
      bridge.deliverable = true;
      bridge.deliverableCount = 1;
      await bridge.becomes(WearReachability.reachable);

      expect(bridge.sent.whereType<SwitchRequest>(), hasLength(1));
      expect(await outbox.pending(), hasLength(1), reason: 'the second is still waiting');
      service.dispose();
    });

    test('a backlog from a previous run goes out on start', () async {
      // The watch app is killed constantly. A backlog that only drains on a
      // reachability event would sit there until the next disconnect.
      final a = await activities.createActivity(name: 'A', color: '#111111', bookmarked: true);
      await outbox.add(
        SwitchRequest(
          changeSyncId: 'from-last-run',
          activityId: a.syncId,
          at: DateTime.fromMillisecondsSinceEpoch(1770000000000),
        ),
      );

      final service = serviceFor(isWatch: true);
      await service.start();
      await bridge.pump();

      expect(bridge.sent.whereType<SwitchRequest>().single.changeSyncId, 'from-last-run');
      service.dispose();
    });

    test('only the newest correction to a block is kept while waiting', () async {
      // Nudging the start a few times out of range should relay where it ended
      // up, not every step it took to get there.
      final a = await activities.createActivity(name: 'A', color: '#111111', bookmarked: true);
      final change = await changes.switchTo(
        a.syncId,
        at: DateTime.fromMillisecondsSinceEpoch(1770000600000),
      );
      final service = await unreachableWatch();

      await service.requestNudge(changeSyncId: change.syncId, by: const Duration(minutes: -1));
      await service.requestNudge(changeSyncId: change.syncId, by: const Duration(minutes: -1));
      await service.requestNudge(changeSyncId: change.syncId, by: const Duration(minutes: -1));

      expect(await outbox.pending(), hasLength(1));

      bridge.deliverable = true;
      await bridge.becomes(WearReachability.reachable);

      final relayed = bridge.sent.whereType<RetimeRequest>().single;
      // Three minutes earlier, in one message.
      expect(relayed.at, DateTime.fromMillisecondsSinceEpoch(1770000420000));
      service.dispose();
    });
  });

  // The rule that makes replaying a correction safe. A correction says "set it
  // to this", which is a valid thing to say twice and about a row that keeps
  // moving — so the receiver compares versions the way it does for a row pulled
  // from the sync server, rather than applying it as a fresh local edit.
  group('a relayed correction is adopted, not re-applied', () {
    late DateTime start;

    setUp(() => start = DateTime.fromMillisecondsSinceEpoch(1770000000000));

    test('a stale correction loses to an unpushed newer one made here', () async {
      // The case the outbox introduces: the watch corrected the block while out
      // of range, the phone corrected it too, and the watch's version arrives
      // late. Re-applying it would bump it past the phone's and win everywhere.
      final a = await activities.createActivity(name: 'A', color: '#111111', bookmarked: true);
      final change = await changes.switchTo(a.syncId, at: start);
      final service = serviceFor(isWatch: false);
      await service.start();

      // The phone's own correction: version 2, not yet pushed anywhere.
      await changes.setChangedAt(change.syncId, start.add(const Duration(minutes: 10)));
      expect((await changes.changeById(change.syncId))!.version, 2);

      // The watch's, made independently from the same starting point, so it
      // carries the same version.
      await bridge.receive(
        RetimeRequest(
          changeSyncId: change.syncId,
          at: start.add(const Duration(minutes: 5)),
          version: 2,
        ),
      );

      final row = (await changes.changeById(change.syncId))!;
      expect(row.changedAt, start.add(const Duration(minutes: 10)), reason: 'ours stands');
      expect(row.version, 2, reason: 'and was not bumped past by the loser');
      service.dispose();
    });

    test('a strictly newer correction is adopted, at the version it came with', () async {
      final a = await activities.createActivity(name: 'A', color: '#111111', bookmarked: true);
      final change = await changes.switchTo(a.syncId, at: start);
      final service = serviceFor(isWatch: false);
      await service.start();

      await bridge.receive(
        RetimeRequest(
          changeSyncId: change.syncId,
          at: start.add(const Duration(minutes: 5)),
          version: 4,
        ),
      );

      final row = (await changes.changeById(change.syncId))!;
      expect(row.changedAt, start.add(const Duration(minutes: 5)));
      // Taken as-is rather than bumped to 5. Bumping is what would make an old
      // value outrank a new one just by passing through this device.
      expect(row.version, 4);
      service.dispose();
    });

    test('an adopted correction is still owed to the server', () async {
      // Unlike a row pulled from the server, this value has never been there —
      // and on a pair with no account it never will be unless it stays dirty.
      final a = await activities.createActivity(name: 'A', color: '#111111', bookmarked: true);
      final change = await changes.switchTo(a.syncId, at: start);
      await db
          .update(db.activityChanges)
          .write(const ActivityChangesCompanion(dirty: Value(false)));

      final service = serviceFor(isWatch: false);
      await service.start();
      await bridge.receive(
        RetimeRequest(
          changeSyncId: change.syncId,
          at: start.add(const Duration(minutes: 5)),
          version: 4,
        ),
      );

      expect((await changes.changeById(change.syncId))!.dirty, isTrue);
      service.dispose();
    });

    test('the same correction delivered twice changes nothing the second time', () async {
      final a = await activities.createActivity(name: 'A', color: '#111111', bookmarked: true);
      final change = await changes.switchTo(a.syncId, at: start);
      final service = serviceFor(isWatch: false);
      await service.start();

      final request = RetimeRequest(
        changeSyncId: change.syncId,
        at: start.add(const Duration(minutes: 5)),
        version: 4,
      );
      await bridge.receive(request);
      await bridge.receive(request);

      final row = (await changes.changeById(change.syncId))!;
      expect(row.changedAt, start.add(const Duration(minutes: 5)));
      expect(row.version, 4, reason: 'a replay is a no-op, not a second edit');
      service.dispose();
    });

    test('a stale assign loses too, leaving the block pointing where it was', () async {
      final a = await activities.createActivity(name: 'A', color: '#111111', bookmarked: true);
      final b = await activities.createActivity(name: 'B', color: '#222222', bookmarked: true);
      final c = await activities.createActivity(name: 'C', color: '#333333', bookmarked: true);
      final change = await changes.switchTo(a.syncId, at: start);
      final service = serviceFor(isWatch: false);
      await service.start();

      await changes.setChangeActivity(change.syncId, c.syncId);
      expect((await changes.changeById(change.syncId))!.version, 2);

      await bridge.receive(
        AssignRequest(changeSyncId: change.syncId, activityId: b.syncId, version: 2),
      );

      expect(await changes.activityIdsForChange(change.syncId), [c.syncId]);
      service.dispose();
    });
  });
}
