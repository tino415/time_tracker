import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/sync_protocol.dart';
import 'providers.dart';
import 'sync_account.dart';
import 'sync_store.dart';
import 'sync_transport.dart';

/// The outcome of one round trip, for the UI's status line.
class SyncResult {
  const SyncResult({
    required this.pushed,
    required this.pulled,
    required this.rejected,
  });

  final int pushed;
  final int pulled;

  /// Rows the server refused as stale. Not an error — the newer version came
  /// back in the same response and has already been adopted — but worth
  /// surfacing, because it means an edit made on this device was superseded.
  final int rejected;

  static const none = SyncResult(pushed: 0, pulled: 0, rejected: 0);
}

/// Drives one sync: push what is pending, adopt what comes back, move the
/// cursor.
///
/// Deliberately manual rather than a background loop. This app is offline-first
/// and the local database is authoritative; syncing is how devices *agree*, not
/// how they work, so it runs when asked and its failures are inert.
class SyncService {
  SyncService({
    required SyncStore store,
    required SyncTransport transport,
    required String backend,
  })  : _store = store,
        _transport = transport,
        _backend = backend;

  final SyncStore _store;
  final SyncTransport _transport;

  /// Identifies which server this device's cursor and dirty flags refer to.
  final String _backend;

  bool _running = false;

  /// One round trip. Concurrent calls collapse: a second sync while one is in
  /// flight would push the same rows twice and race on the cursor.
  Future<SyncResult> syncNow() async {
    if (_running) return SyncResult.none;
    _running = true;
    try {
      // Before anything else: if this device last synced somewhere else, its
      // cursor and dirty flags describe that server, not this one.
      await _store.adoptBackend(_backend);

      final activities = await _store.pendingActivities();
      final changes = await _store.pendingChanges();

      final response = await _transport.exchange(SyncRequest(
        cursor: await _store.cursor(),
        activities: activities,
        changes: changes,
      ));

      final rejected = response.rejected.toSet();

      // Mark clean only what was not rejected, and only at the version pushed —
      // a row edited while the request was in flight stays dirty and goes next
      // time. Rejected rows stay dirty too, but the authoritative version came
      // back in this same response and is adopted below, which is what stops
      // them being re-pushed forever.
      await _store.markSynced(
        activityVersions: {
          for (final a in activities)
            if (!rejected.contains(a.syncId)) a.syncId: a.version,
        },
        changeVersions: {
          for (final c in changes)
            if (!rejected.contains(c.syncId)) c.syncId: c.version,
        },
      );

      var pulled = 0;
      // Activities first: a change's links reference them, and a link naming an
      // unknown activity is skipped rather than applied.
      for (final dto in response.activities) {
        if (await _store.applyRemoteActivity(dto)) pulled++;
      }
      for (final dto in response.changes) {
        if (await _store.applyRemoteChange(dto)) pulled++;
      }

      // Last: an interrupted sync must re-pull rather than skip. Adopting is
      // idempotent, so replaying a page costs nothing; missing one loses data.
      await _store.setCursor(response.cursor);

      return SyncResult(
        pushed: activities.length + changes.length - rejected.length,
        pulled: pulled,
        rejected: rejected.length,
      );
    } finally {
      _running = false;
    }
  }
}

/// Where the backend lives. Only the URL is built in — the token is per account
/// and lives in the local database, because a token compiled into a web build is
/// served to everyone who loads the page.
class SyncConfig {
  const SyncConfig({this.baseUrl});

  final String? baseUrl;

  bool get hasServer => (baseUrl ?? '').isNotEmpty;
}

/// Supplied at build time:
///   flutter build web --dart-define=SYNC_URL=https://example.workers.dev/
///
/// Without it the app never offers sync at all.
final syncConfigProvider = Provider<SyncConfig>((ref) {
  return const SyncConfig(baseUrl: String.fromEnvironment('SYNC_URL'));
});

final syncStoreProvider = Provider<SyncStore>((ref) {
  return SyncStore(ref.watch(databaseProvider));
});

/// Null until this device has both a server and an account — which is the state
/// every new install starts in, and why every caller has to handle it.
final syncServiceProvider = Provider<SyncService?>((ref) {
  final config = ref.watch(syncConfigProvider);
  final token = ref.watch(syncTokenProvider).valueOrNull;
  if (!config.hasServer || token == null) return null;

  final transport = HttpSyncTransport(baseUrl: Uri.parse(config.baseUrl!), token: token);
  ref.onDispose(transport.close);

  return SyncService(
    store: ref.watch(syncStoreProvider),
    transport: transport,
    // Identity includes the token: joining a *different* account is as much a
    // change of backend as pointing at a different server, and carrying a cursor
    // across either is silently destructive.
    backend: '${config.baseUrl}#${token.hashCode}',
  );
});
