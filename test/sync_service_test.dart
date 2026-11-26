// The sync engine against the real database, with an in-memory stand-in for the
// server that implements the same acceptance rule as the Worker.
//
// Two devices are modelled as two databases talking to one fake server — which
// is the only way to test convergence, the property the whole design exists for.

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/data/drift_repositories.dart';
import 'package:time_tracker/data/sync_service.dart';
import 'package:time_tracker/data/sync_store.dart';
import 'package:time_tracker/data/sync_transport.dart';
import 'package:time_tracker/domain/sync_protocol.dart';

/// An in-memory twin of worker/src/index.js: same acceptance rule, same shared
/// `seq` order across both tables, same "echo the push back" behaviour.
class FakeServer implements SyncTransport {
  FakeServer({this.pageSize});

  /// The Worker's MAX_PAGE; null sends every row in one page.
  final int? pageSize;

  final activities = <String, ActivityDto>{};
  final changes = <String, ChangeDto>{};
  final _seq = <String, int>{};
  int _next = 1;

  int exchanges = 0;
  int claims = 0;

  /// Set to make the next exchange fail, as an unreachable network would.
  bool offline = false;

  @override
  Future<void> claimAccount() async {
    claims++;
    if (offline) throw const SyncException('unreachable');
  }

  @override
  Future<SyncResponse> exchange(SyncRequest request) async {
    exchanges++;
    if (offline) throw const SyncException('unreachable');

    final cursor = int.tryParse(request.cursor ?? '0') ?? 0;
    final rejected = <String>[];

    for (final dto in request.activities) {
      final stored = activities[dto.syncId];
      if (stored != null &&
          !acceptsPush(storedVersion: stored.version, incomingVersion: dto.version)) {
        rejected.add(dto.syncId);
        continue;
      }
      activities[dto.syncId] = dto;
      _seq[dto.syncId] = _next++;
    }
    for (final dto in request.changes) {
      final stored = changes[dto.syncId];
      if (stored != null &&
          !acceptsPush(storedVersion: stored.version, incomingVersion: dto.version)) {
        rejected.add(dto.syncId);
        continue;
      }
      changes[dto.syncId] = dto;
      _seq[dto.syncId] = _next++;
    }

    // Ordered by `seq`, like the Worker's "rows with seq > cursor, oldest
    // first" — and not by insertion, which would hide the case this order
    // creates: a row edited twice moves to the *end*, so a parent edited after
    // its child is delivered after it.
    final outActivities = _page(
      [
        for (final e in activities.entries)
          if ((_seq[e.key] ?? 0) > cursor) e.value,
      ]..sort((a, b) => (_seq[a.syncId] ?? 0).compareTo(_seq[b.syncId] ?? 0)),
    );
    final outChanges = _page(
      [
        for (final e in changes.entries)
          if ((_seq[e.key] ?? 0) > cursor) e.value,
      ]..sort((a, b) => (_seq[a.syncId] ?? 0).compareTo(_seq[b.syncId] ?? 0)),
    );

    final sent = [
      ...outActivities.map((a) => _seq[a.syncId] ?? 0),
      ...outChanges.map((c) => _seq[c.syncId] ?? 0),
    ];
    final highest = sent.isEmpty ? cursor : sent.reduce((a, b) => a > b ? a : b);
    // Like the Worker, the cursor stops where both lists are complete.
    final complete = [
      _lastSeqIfCut(outActivities.map((a) => a.syncId)),
      _lastSeqIfCut(outChanges.map((c) => c.syncId)),
    ].nonNulls;
    final nextCursor = [highest, ...complete].reduce((a, b) => a < b ? a : b);

    return SyncResponse(
      cursor: '$nextCursor',
      activities: outActivities,
      changes: outChanges,
      rejected: rejected,
    );
  }

  List<T> _page<T>(List<T> rows) {
    final size = pageSize;
    return size == null || rows.length <= size ? rows : rows.sublist(0, size);
  }

  int? _lastSeqIfCut(Iterable<String> syncIds) =>
      syncIds.length == pageSize ? _seq[syncIds.last] : null;
}

/// One device: its own database, repositories and sync service.
class Device {
  Device(this.server, {this.backend = 'https://example.test/'}) {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    activities = DriftActivityRepository(db);
    changes = DriftChangeRepository(db);
    store = SyncStore(db);
    sync = SyncService(store: store, transport: server, backend: backend);
  }

  final FakeServer server;

  /// Which server this device believes it is talking to.
  final String backend;
  late final AppDatabase db;
  late final DriftActivityRepository activities;
  late final DriftChangeRepository changes;
  late final SyncStore store;
  late final SyncService sync;

  Future<void> close() => db.close();
}

void main() {
  // Two databases *is* the point here — they model two devices, and each has its
  // own executor, so drift's shared-executor warning does not apply.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late FakeServer server;
  late Device phone;

  setUp(() {
    server = FakeServer();
    phone = Device(server);
  });

  tearDown(() => phone.close());

  // Observed in the wild (2026-08-10): one device sat on the same cursor for a
  // day, pushing its own blocks and receiving nothing, because a parent it did
  // not have yet was delivered *after* the child pointing at it. The insert
  // failed the foreign key, the exception left the loop before the cursor moved,
  // and every later sync replayed the same page and failed identically.
  test('a parent edited after its child still applies to a device that has neither', () async {
    final web = Device(server);
    final work = await web.activities.createActivity(name: 'Work', color: '#4F8FEE');
    await web.activities.createActivity(name: 'Payout', color: '#F4B740', parentId: work.syncId);
    await web.sync.syncNow();

    // Touching the parent moves it to the end of the server's order — so a
    // device syncing from scratch is offered the child first.
    await web.activities.renameActivity(work.syncId, 'Work & co');
    await web.sync.syncNow();

    await phone.sync.syncNow();

    final rows = await phone.db.select(phone.db.activities).get();
    expect(rows.map((r) => r.name), containsAll(<String>['Work & co', 'Payout']));
    // The cursor has to move, or the next sync replays this page forever.
    expect(await phone.store.cursor(), isNot('0'));

    await web.close();
  });

  test('a first sync pushes everything the device already has', () async {
    await phone.activities.createActivity(name: 'Deep work', color: '#4F8FEE');

    final result = await phone.sync.syncNow();

    expect(result.pushed, 1);
    expect(server.activities.values.single.name, 'Deep work');
    // Pushed rows come back in the same response and are adopted, which is how
    // a rejected push learns the winning version.
    expect(result.pulled, 1);
  });

  test('a synced row is not pushed again', () async {
    await phone.activities.createActivity(name: 'Deep work', color: '#4F8FEE');
    await phone.sync.syncNow();

    final second = await phone.sync.syncNow();

    expect(second.pushed, 0);
    expect(second.pulled, 0);
  });

  test('editing a synced row makes it pending again', () async {
    final a = await phone.activities.createActivity(name: 'Deep work', color: '#4F8FEE');
    await phone.sync.syncNow();

    await phone.activities.renameActivity(a.syncId, 'Focus');
    final result = await phone.sync.syncNow();

    expect(result.pushed, 1);
    expect(server.activities[a.syncId]!.name, 'Focus');
    expect(server.activities[a.syncId]!.version, 2);
  });

  test('a second device pulls what the first pushed', () async {
    final watch = Device(server);
    addTearDown(watch.close);

    final a = await phone.activities.createActivity(name: 'Deep work', color: '#4F8FEE');
    await phone.changes.switchTo(a.syncId, at: DateTime(2026, 1, 5, 9));
    await phone.sync.syncNow();

    final result = await watch.sync.syncNow();

    expect(result.pulled, 2); // the activity and the change
    final pulled = await watch.activities.loadActivities();
    expect(pulled.single.name, 'Deep work');
    // The set travels inside its change, so it arrives whole.
    final changes = await watch.changes.loadChanges();
    expect(await watch.changes.activityIdsForChange(changes.single.syncId), [a.syncId]);
  });

  test('a second device pulls 1200 changes in one sync', () async {
    final paged = FakeServer(pageSize: 500);
    final web = Device(paged);
    final watch = Device(paged);
    addTearDown(web.close);
    addTearDown(watch.close);

    final a = await web.activities.createActivity(name: 'Deep work', color: '#4F8FEE');
    for (var i = 0; i < 1200; i++) {
      await web.changes.switchTo(a.syncId, at: DateTime(2026, 1, 5).add(Duration(minutes: i)));
    }
    await web.sync.syncNow();

    final result = await watch.sync.syncNow();

    expect((await watch.changes.loadChanges()).length, 1200);
    expect(result.pulled, 1201);
  });

  test('a pulled row is not echoed back as a local edit', () async {
    final watch = Device(server);
    addTearDown(watch.close);

    await phone.activities.createActivity(name: 'Deep work', color: '#4F8FEE');
    await phone.sync.syncNow();
    await watch.sync.syncNow();

    // Adopting must not mark the row dirty, or two devices would ratchet each
    // other's versions upward forever.
    expect(await watch.store.pendingActivities(), isEmpty);
    final second = await watch.sync.syncNow();
    expect(second.pushed, 0);
  });

  test('a deletion propagates as a tombstone', () async {
    final watch = Device(server);
    addTearDown(watch.close);

    final a = await phone.activities.createActivity(name: 'Deep work', color: '#4F8FEE');
    await phone.sync.syncNow();
    await watch.sync.syncNow();

    await phone.activities.deleteActivity(a.syncId);
    await phone.sync.syncNow();
    await watch.sync.syncNow();

    // Gone from the live list, but the row survives so the deletion cannot be
    // undone by a stale peer re-pushing the old version.
    expect(await watch.activities.loadActivities(), isEmpty);
    final raw = await watch.db.select(watch.db.activities).getSingle();
    expect(raw.deletedAt, isNotNull);
  });

  test('concurrent edits converge on the later arrival', () async {
    final watch = Device(server);
    addTearDown(watch.close);

    final a = await phone.activities.createActivity(name: 'Deep work', color: '#4F8FEE');
    await phone.sync.syncNow();
    await watch.sync.syncNow();

    // Both edit the same row from version 1, offline. Both become version 2.
    await phone.activities.renameActivity(a.syncId, 'From phone');
    await watch.activities.renameActivity(a.syncId, 'From watch');

    await phone.sync.syncNow();
    await watch.sync.syncNow();
    // The phone now pulls whatever won.
    await phone.sync.syncNow();

    final onPhone = (await phone.activities.loadActivities()).single.name;
    final onWatch = (await watch.activities.loadActivities()).single.name;

    // One edit is lost — that is the documented trade. What must hold is that
    // both devices agree, and on the value the server kept.
    expect(onPhone, onWatch);
    expect(onPhone, server.activities[a.syncId]!.name);
    expect(onPhone, 'From watch'); // the later arrival
  });

  test('a stale push is rejected and the winning version adopted', () async {
    final watch = Device(server);
    addTearDown(watch.close);

    final a = await phone.activities.createActivity(name: 'Deep work', color: '#4F8FEE');
    await phone.sync.syncNow();
    await watch.sync.syncNow();

    // The phone gets two edits ahead while the watch is offline.
    await phone.activities.renameActivity(a.syncId, 'Second');
    await phone.sync.syncNow();
    await phone.activities.renameActivity(a.syncId, 'Third');
    await phone.sync.syncNow();

    // The watch's single edit is version 2 against the server's 3.
    await watch.activities.renameActivity(a.syncId, 'From watch');
    final result = await watch.sync.syncNow();

    expect(result.rejected, 1);
    // Rejected, and the newer row came back in the same response — so the watch
    // is left agreeing with the server rather than stuck re-pushing forever.
    expect((await watch.activities.loadActivities()).single.name, 'Third');
    final after = await watch.sync.syncNow();
    expect(after.pushed, 0);
  });

  test('an offline sync leaves everything pending for next time', () async {
    await phone.activities.createActivity(name: 'Deep work', color: '#4F8FEE');
    server.offline = true;

    await expectLater(phone.sync.syncNow(), throwsA(isA<SyncException>()));

    // Nothing was marked clean and the cursor did not move: the local database
    // is authoritative, and a failed sync has to be inert.
    expect(await phone.store.pendingActivities(), hasLength(1));
    expect(await phone.store.cursor(), isNull);

    server.offline = false;
    expect((await phone.sync.syncNow()).pushed, 1);
  });

  test('an edit made while a sync is in flight is not marked clean', () async {
    final a = await phone.activities.createActivity(name: 'Deep work', color: '#4F8FEE');
    await phone.sync.syncNow();

    // markSynced clears only rows still at the version that was pushed. Bumping
    // the row to v3 after v2 went out means v3 must survive as pending.
    await phone.activities.renameActivity(a.syncId, 'Second'); // v2
    await phone.store.markSynced(
      activityVersions: {a.syncId: 1}, // a stale ack, as if v1 had been in flight
      changeVersions: const {},
    );

    expect(await phone.store.pendingActivities(), hasLength(1));
  });

  test('a change referencing an unknown activity keeps the change', () async {
    // Pages are capped server-side, so a change can arrive before the activity
    // it names. Dropping the change would lose a boundary permanently; dropping
    // the link is repaired by the next sync.
    final watch = Device(server);
    addTearDown(watch.close);

    await watch.store.applyRemoteChange(
      ChangeDto(
        syncId: 'c1',
        changedAt: DateTime(2026, 1, 5, 9),
        version: 1,
        activityIds: const ['not-here-yet'],
      ),
    );

    final changes = await watch.changes.loadChanges();
    expect(changes, hasLength(1));
    expect(await watch.changes.activityIdsForChange('c1'), isEmpty);
  });

  test('switching backend re-offers everything instead of silently skipping', () async {
    // Found in real use: a phone that had synced against a local worker was
    // pointed at the deployed one and reported "0 up, 0 down" forever. Its
    // cursor was a position in the *old* server's sequence, so it asked for rows
    // after a number the new server had never issued, and its rows were marked
    // clean against a server that had never seen them.
    await phone.activities.createActivity(name: 'Deep work', color: '#4F8FEE');
    await phone.sync.syncNow();
    expect(server.activities, hasLength(1));

    // Same device and database, a different backend.
    final elsewhere = FakeServer();
    final moved = SyncService(
      store: phone.store,
      transport: elsewhere,
      backend: 'https://somewhere-else.test/',
    );

    final result = await moved.syncNow();

    expect(result.pushed, 1, reason: 'the new server has never seen this row');
    expect(elsewhere.activities.values.single.name, 'Deep work');
    // And the cursor restarted, so rows already on the new server come down
    // rather than being skipped.
    expect(await phone.store.cursor(), isNot('0'));
  });

  test('an unchanged backend does not reset anything', () async {
    await phone.activities.createActivity(name: 'Deep work', color: '#4F8FEE');
    await phone.sync.syncNow();

    final second = await phone.sync.syncNow();

    // Resetting on every sync would re-push the whole database each time.
    expect(second.pushed, 0);
    expect(second.pulled, 0);
  });

  test('concurrent syncNow calls collapse into one', () async {
    await phone.activities.createActivity(name: 'Deep work', color: '#4F8FEE');

    final results = await Future.wait([phone.sync.syncNow(), phone.sync.syncNow()]);

    // Two in flight would push the same rows twice and race on the cursor. One
    // sync is the push and the empty round that finds the cursor unmoved.
    expect(server.exchanges, 2);
    expect(results.where((r) => r.pushed > 0), hasLength(1));
  });
}
