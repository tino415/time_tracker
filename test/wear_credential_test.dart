// Handing the watch a sync account, and taking it away again.
//
// The credential is the one thing that cannot travel through the sync server,
// because it is what grants access to it — so it moves over the Wear relay and
// needs its own ordering rule there. It carries a version, and newest wins: the
// same rule as the rest of the data model.
//
// Two properties matter more than the mechanics.
//
// The token must not be on the wire routinely. It is offered only to a peer that
// says it has something older, so a watch that is current is told nothing.
//
// And revocation must reach a watch that was away. That is why leaving the
// account is a *grant of null* at a higher version rather than a deletion —
// something merely absent can neither travel nor win.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/data/drift_repositories.dart';
import 'package:time_tracker/data/sync_store.dart';
import 'package:time_tracker/data/wear_sync.dart';
import 'package:time_tracker/domain/wear_protocol.dart';

import 'support/fake_wear_bridge.dart';

const _token = 'a-token-worth-32-chars-or-so';

void main() {
  late AppDatabase db;
  late SyncStore store;
  late FakeWearBridge bridge;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    store = SyncStore(db);
    bridge = FakeWearBridge();
  });

  tearDown(() async {
    bridge.dispose();
    await db.close();
  });

  WearSyncService serviceFor({required bool isWatch}) => WearSyncService(
        bridge: bridge,
        activities: DriftActivityRepository(db),
        changes: DriftChangeRepository(db),
        syncStore: store,
        isWatch: isWatch,
      );

  List<SyncCredential> credentials() => bridge.sent.whereType<SyncCredential>().toList();

  /// Start the phone side and get past its opening traffic.
  ///
  /// The token stream delivers on subscribe, so a bare `clear()` races it and
  /// the first assertion sees a credential nobody asked for.
  Future<WearSyncService> startedPhone() async {
    final service = serviceFor(isWatch: false);
    await service.start();
    await pumpEventQueue();
    bridge.sent.clear();
    return service;
  }

  group('phone side', () {
    test('answers a watch that is behind', () async {
      await store.grantCredential(_token);
      final service = await startedPhone();

      await bridge.receive(const SnapshotRequest(credentialVersion: 0));

      expect(credentials().last.token, _token);
      expect(credentials().last.version, 1);
      service.dispose();
    });

    test('tells a watch that is current nothing', () async {
      await store.grantCredential(_token);
      final service = await startedPhone();

      await bridge.receive(const SnapshotRequest(credentialVersion: 1));

      // The whole point of the version: no bearer token on the wire during
      // ordinary use, which is many snapshot requests a day.
      expect(credentials(), isEmpty);
      // The snapshot itself still goes, so the watch is not left stale.
      expect(bridge.sent.whereType<BookmarkSnapshot>(), isNotEmpty);
      service.dispose();
    });

    test('offers the revocation to a watch still holding the old grant', () async {
      await store.grantCredential(_token);
      await store.grantCredential(null); // what forget() does
      final service = await startedPhone();

      await bridge.receive(const SnapshotRequest(credentialVersion: 1));

      // A watch that was off the wrist when the account was left asks on its
      // next start, and this is where it finds out.
      expect(credentials().last.token, isNull);
      expect(credentials().last.version, 2);
      service.dispose();
    });

    test('pushes a change unprompted, so a watch present hears at once', () async {
      final service = await startedPhone();

      await store.grantCredential(_token);
      await pumpEventQueue();

      expect(credentials().last.token, _token);
      service.dispose();
    });
  });

  group('watch side', () {
    test('adopts a newer credential at the version it came with', () async {
      final service = serviceFor(isWatch: true);
      await service.start();

      await bridge.receive(const SyncCredential(token: _token, version: 4));

      expect(await store.token(), _token);
      // The peer's version, not a fresh one: adopting is not an edit, so it must
      // not look newer than what it came from.
      expect(await store.credentialVersion(), 4);
      service.dispose();
    });

    test('a stale grant cannot undo a revocation', () async {
      // The listener parks messages while the app is down and drains them on
      // next start, so late delivery is real rather than theoretical. Without a
      // version this would quietly re-grant a token that had been taken away.
      await store.adoptCredential(null, 5); // revoked, and we know it
      final service = serviceFor(isWatch: true);
      await service.start();

      await bridge.receive(const SyncCredential(token: _token, version: 3));

      expect(await store.token(), isNull);
      expect(await store.credentialVersion(), 5);
      service.dispose();
    });

    test('asks with the version it holds', () async {
      await store.adoptCredential(_token, 7);
      final service = serviceFor(isWatch: true);
      await service.start();
      await pumpEventQueue();

      final asked = bridge.sent.whereType<SnapshotRequest>().last;
      expect(asked.credentialVersion, 7);
      service.dispose();
    });

    test('never sends a credential back', () async {
      final service = serviceFor(isWatch: true);
      await service.start();
      bridge.sent.clear();

      await bridge.receive(const SyncCredential(token: _token, version: 1));

      // A watch cannot hand the phone an account. Honouring it in that direction
      // would let a lost watch dictate which server the phone talks to.
      expect(credentials(), isEmpty);
      service.dispose();
    });
  });

  /// Start the watch side and get past its opening snapshot request.
  ///
  /// It asks as soon as it starts, so a bare `clear()` races that and the first
  /// assertion counts a request nobody prompted.
  Future<WearSyncService> startedWatch() async {
    final service = serviceFor(isWatch: true);
    await service.start();
    await pumpEventQueue();
    bridge.sent.clear();
    return service;
  }

  group('advertise and fetch', () {
    test('a watch with no account and a phone with none asks nothing', () async {
      // The case that ruled out polling. Sync is opt-in, so most watches have
      // nothing coming, and one asking every half minute forever on the chance
      // that it might is a battery cost for nothing. Both at 0: silence.
      final service = await startedWatch();

      await bridge.receive(const BookmarkSnapshot(activities: []));

      expect(bridge.sent, isEmpty);
      expect(await store.token(), isNull);
      service.dispose();
    });

    test('a snapshot advertising something newer prompts one request', () async {
      final service = await startedWatch();

      await bridge.receive(const BookmarkSnapshot(activities: [], credentialVersion: 3));

      // Evidence, not hope: it asks because the phone said there is something.
      final asked = bridge.sent.whereType<SnapshotRequest>();
      expect(asked, hasLength(1));
      expect(asked.single.credentialVersion, 0);
      service.dispose();
    });

    test('an answered watch stops asking', () async {
      final service = serviceFor(isWatch: true);
      await service.start();

      await bridge.receive(const BookmarkSnapshot(activities: [], credentialVersion: 3));
      await bridge.receive(const SyncCredential(token: _token, version: 3));
      bridge.sent.clear();

      // The next snapshot advertises the same version it now holds, so there is
      // nothing to fetch and nothing is sent.
      await bridge.receive(const BookmarkSnapshot(activities: [], credentialVersion: 3));

      expect(bridge.sent, isEmpty);
      expect(await store.token(), _token);
      service.dispose();
    });

    test('a lost credential does not become a ping-pong', () async {
      // The request makes the phone re-send its snapshot. If the credential half
      // is lost while the snapshot half arrives, the answer would prompt the
      // question it answers, as fast as the two can talk.
      final service = await startedWatch();

      for (var i = 0; i < 5; i++) {
        await bridge.receive(const BookmarkSnapshot(activities: [], credentialVersion: 3));
      }

      expect(bridge.sent.whereType<SnapshotRequest>(), hasLength(1),
          reason: 'the cooldown bounds it to one exchange, not a spin');
      service.dispose();
    });

    test('the phone advertises its version on every snapshot', () async {
      await store.grantCredential(_token);
      final service = await startedPhone();

      await bridge.receive(const SnapshotRequest(credentialVersion: 1));

      final snapshot = bridge.sent.whereType<BookmarkSnapshot>().last;
      // The number, so a watch can tell there is something to fetch — never the
      // token, which only goes to a peer that says it is behind.
      expect(snapshot.credentialVersion, 1);
      expect(bridge.sent.whereType<SyncCredential>(), isEmpty);
      service.dispose();
    });
  });

  group('the store', () {
    test('granting moves the version, adopting does not invent one', () async {
      expect(await store.credentialVersion(), 0);
      expect(await store.grantCredential(_token), 1);
      expect(await store.grantCredential(null), 2);

      await store.adoptCredential(_token, 9);
      expect(await store.credentialVersion(), 9);
    });

    test('a revocation is a grant of null, not a deletion', () async {
      await store.grantCredential(_token);
      await store.grantCredential(null);

      // Both halves matter: the token is gone *and* the version says so, which
      // is what lets the revocation travel and win.
      expect(await store.token(), isNull);
      expect(await store.credentialVersion(), 2);
    });
  });

  group('wire format', () {
    test('round-trips a token, a revocation and the version', () {
      for (final token in [null, _token]) {
        final encoded = SyncCredential(token: token, version: 3).toPayload();
        final decoded = WearMessage.decode(SyncCredential.kind, encoded) as SyncCredential;
        expect(decoded.token, token);
        expect(decoded.version, 3);
      }
    });

    test('a malformed credential revokes, and loses to everything', () {
      // Failing safe means failing shut — but at version 0, so a message this
      // build cannot read also cannot overwrite a credential already held.
      for (final payload in [<Object?, Object?>{}, {'token': 42}, {'token': ''}]) {
        final decoded = WearMessage.decode(SyncCredential.kind, payload) as SyncCredential;
        expect(decoded.token, isNull);
        expect(decoded.version, 0);
      }
    });

    test('a request without a version reads as 0', () {
      // A peer too old to send one is offered the credential, which is the old
      // behaviour and the safe direction to be wrong in.
      final decoded =
          WearMessage.decode(SnapshotRequest.kind, <Object?, Object?>{}) as SnapshotRequest;
      expect(decoded.credentialVersion, 0);
    });
  });
}
