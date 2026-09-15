// A cursor write must not rebuild the sync stack.
//
// syncNow ends by writing the cursor into syncMeta — the same table the token
// is watched from. If that write rebuilt syncTokenProvider's dependents, every
// sync would mint a fresh AutoSyncService whose start() syncs immediately: a
// loop at network round-trip speed, throttled by nothing (the rate limit lives
// in the instance that was just thrown away) and visible on no screen.
//
// The dedup must also sit exactly one layer up from the store: the Wear relay
// listens to the raw token stream and pushes the credential per *emission*, so
// a store that deduped by value would swallow the same-token re-grant whose
// newer version is what re-pairs a watch.

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/data/auto_sync.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/data/providers.dart';
import 'package:time_tracker/data/sync_account.dart';
import 'package:time_tracker/data/sync_service.dart';
import 'package:time_tracker/data/sync_store.dart';

void main() {
  late AppDatabase db;
  late SyncStore store;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        syncConfigProvider.overrideWithValue(const SyncConfig(baseUrl: 'https://sync.invalid/')),
      ],
    );
    store = container.read(syncStoreProvider);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('a cursor write mints no new sync service; a token change does', () async {
    // Granted before the chain first initializes, so the provider's first
    // emission is already the token — nothing here races the drift stream.
    await store.grantCredential('0123456789abcdef');

    // Keep the chain alive the way the running app does.
    container.listen(autoSyncProvider, (_, _) {});
    await container.read(syncTokenProvider.future);

    final sync = container.read(syncServiceProvider);
    final auto = container.read(autoSyncProvider);
    expect(sync, isNotNull, reason: 'a stored token and a server make a service');

    // What every syncNow does last — and, for an up-to-date device, the only
    // local write a sync performs at all.
    await store.setCursor('42');
    await pumpEventQueue();

    expect(
      identical(container.read(syncServiceProvider), sync),
      isTrue,
      reason: 'the token did not change, so the service must not be rebuilt',
    );
    expect(
      identical(container.read(autoSyncProvider), auto),
      isTrue,
      reason: 'a rebuilt auto-sync starts unthrottled: sync -> rebuild -> sync',
    );

    // The other direction, so an over-eager dedup cannot pass: joining a
    // different account is precisely a rebuild.
    await store.grantCredential('fedcba9876543210');
    await pumpEventQueue();

    expect(
      identical(container.read(syncServiceProvider), sync),
      isFalse,
      reason: 'a changed token is a different account and must rebuild the service',
    );
  });

  test('a same-token re-grant still reaches the raw token stream', () async {
    // The Wear relay pushes the credential once per emission of this stream.
    // Re-entering the token a watch already has bumps only the credential
    // version — the value is unchanged, and only the *event* says to re-pair.
    await store.grantCredential('0123456789abcdef');

    final emissions = <String?>[];
    final sub = store.watchToken().listen(emissions.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();
    final before = emissions.length;

    await store.grantCredential('0123456789abcdef');
    await pumpEventQueue();

    expect(
      emissions.length,
      greaterThan(before),
      reason: 'a swallowed re-grant never re-pairs the watch',
    );
  });
}
