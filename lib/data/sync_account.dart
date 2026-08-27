import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sync_service.dart';
import 'sync_store.dart';
import 'sync_transport.dart';

/// Joining, leaving, and creating a sync account.
///
/// The token *is* the account: generated on the first device, entered on the
/// others. There are no usernames and no reset — which suits a handful of people
/// who know each other, and keeps the whole thing to one secret the user can
/// copy between their devices.
///
/// Sync is opt-in. Until a token exists the app never contacts a server, and the
/// sync UI offers to set one up rather than pretending to be connected.
class SyncAccountController {
  SyncAccountController({
    required SyncStore store,
    required SyncTransport? Function(String token) transportFor,
  }) : _store = store,
       _transportFor = transportFor;

  final SyncStore _store;
  final SyncTransport? Function(String token) _transportFor;

  /// 32 characters from a cryptographically secure source — around 190 bits.
  ///
  /// Generated rather than chosen because this is a bearer credential, not a
  /// password: it is never typed from memory, only copied, so there is no reason
  /// to trade entropy for memorability. It is also why the server can store a
  /// plain SHA-256 of it — there is nothing here to brute force.
  static String generateToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// Create a new account and store its token on this device.
  Future<String> createAccount() async {
    final token = generateToken();
    await _claimAndStore(token);
    return token;
  }

  /// Join an existing account by entering its token.
  ///
  /// Throws [SyncException] if the server cannot be reached, so the UI can say
  /// so rather than silently storing a token that may be wrong.
  Future<void> joinAccount(String token) async {
    final trimmed = token.trim();
    if (trimmed.length < 16) {
      throw const SyncException('that token is too short to be one');
    }
    await _claimAndStore(trimmed);
  }

  Future<void> _claimAndStore(String token) async {
    final transport = _transportFor(token);
    if (transport == null) {
      throw const SyncException('no sync server is configured in this build');
    }
    // Claim first: storing a token the server will not accept would leave the
    // app looking connected while every sync fails.
    await transport.claimAccount();
    await _store.grantCredential(token);
  }

  /// Stop syncing. The local database is untouched — it is the authoritative
  /// copy, and disconnecting is not deleting.
  ///
  /// A version bump, not a deletion: leaving the account has to *reach* the
  /// watch, and it can only beat a stale grant still queued somewhere if it is
  /// newer rather than merely absent.
  Future<void> forget() => _store.grantCredential(null);
}

final syncAccountProvider = Provider<SyncAccountController>((ref) {
  return SyncAccountController(
    store: ref.watch(syncStoreProvider),
    transportFor: (token) {
      final config = ref.watch(syncConfigProvider);
      if (!config.hasServer) return null;
      return HttpSyncTransport(baseUrl: Uri.parse(config.baseUrl!), token: token);
    },
  );
});

/// The token stored on this device, or null when sync has not been set up.
///
/// Watched rather than read once: on the watch the token arrives over the Wear
/// relay after startup, and [syncServiceProvider] has to come to life when it
/// does rather than at the next launch. Revocation travels the same way.
final syncTokenProvider = StreamProvider<String?>((ref) {
  return ref.watch(syncStoreProvider).watchToken();
});
