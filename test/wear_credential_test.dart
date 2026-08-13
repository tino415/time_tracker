// Handing the watch a sync account, and taking it away again.
//
// The watch already runs the same sync stack as the phone — main() starts
// auto-sync in the shared root, before the isWatch branch — and syncServiceProvider
// was null on the watch for exactly one reason: no token on that device. There
// is no way to enter 32 generated characters on a 227px screen with no camera,
// so it inherits the phone's over the relay that already carries the catalogue.
//
// The revocation half is the security-relevant one: without it, "leave this
// account" on the phone leaves a working bearer credential on a device you
// believe you have disconnected.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/data/drift_repositories.dart';
import 'package:time_tracker/data/sync_store.dart';
import 'package:time_tracker/data/wear_sync.dart';
import 'package:time_tracker/domain/wear_protocol.dart';

import 'support/fake_wear_bridge.dart';

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

  group('phone side', () {
    test('sends the token when the watch asks for a snapshot', () async {
      await store.setToken('a-token-worth-32-chars-or-so');
      final service = serviceFor(isWatch: false);
      await service.start();
      bridge.sent.clear();

      await bridge.receive(const SnapshotRequest());

      // More than one is expected and fine: the token stream also delivers on
      // subscribe. Re-sending a credential is idempotent, which is what lets
      // both the stream and the request carry it without coordinating.
      expect(credentials(), isNotEmpty);
      expect(
        credentials().map((c) => c.token).toSet(),
        {'a-token-worth-32-chars-or-so'},
      );
      service.dispose();
    });

    test('sends a revocation when the account is left', () async {
      await store.setToken('a-token-worth-32-chars-or-so');
      final service = serviceFor(isWatch: false);
      await service.start();
      bridge.sent.clear();

      await store.setToken(null); // what forget() does
      await pumpEventQueue();

      // Sent unprompted, rather than waiting to be asked: the point of a
      // revocation is that it does not wait.
      expect(credentials().last.token, isNull);
      service.dispose();
    });

    test('a snapshot request after leaving carries the revocation too', () async {
      final service = serviceFor(isWatch: false);
      await service.start();
      bridge.sent.clear();

      // The watch was off the wrist when the account was left, so it never saw
      // the message above. Asking for a snapshot is the first thing it does on
      // waking, and it must not be told nothing and keep its token.
      await bridge.receive(const SnapshotRequest());

      expect(credentials(), isNotEmpty);
      expect(credentials().last.token, isNull);
      service.dispose();
    });
  });

  group('watch side', () {
    test('stores a delivered token', () async {
      final service = serviceFor(isWatch: true);
      await service.start();

      await bridge.receive(const SyncCredential(token: 'a-token-worth-32-chars-or-so'));

      expect(await store.token(), 'a-token-worth-32-chars-or-so');
      service.dispose();
    });

    test('clears the token on a revocation', () async {
      await store.setToken('a-token-worth-32-chars-or-so');
      final service = serviceFor(isWatch: true);
      await service.start();

      await bridge.receive(const SyncCredential(token: null));

      expect(await store.token(), isNull);
      service.dispose();
    });

    test('never sends one back', () async {
      final service = serviceFor(isWatch: true);
      await service.start();
      bridge.sent.clear();

      await bridge.receive(const SyncCredential(token: 'a-token-worth-32-chars-or-so'));

      // A watch cannot hand the phone an account. Honouring it in that direction
      // would let a lost watch dictate which server the phone talks to.
      expect(credentials(), isEmpty);
      service.dispose();
    });
  });

  group('wire format', () {
    test('round-trips a token and a revocation', () {
      for (final token in [null, 'a-token-worth-32-chars-or-so']) {
        final encoded = SyncCredential(token: token).toPayload();
        final decoded = WearMessage.decode(SyncCredential.kind, encoded);
        expect((decoded as SyncCredential).token, token);
      }
    });

    test('a malformed credential revokes rather than being ignored', () {
      // Failing safe here means failing shut: a message this build cannot read
      // must not leave a stale credential in place.
      for (final payload in [<Object?, Object?>{}, {'token': 42}, {'token': ''}]) {
        final decoded = WearMessage.decode(SyncCredential.kind, payload);
        expect((decoded as SyncCredential).token, isNull);
      }
    });
  });
}
