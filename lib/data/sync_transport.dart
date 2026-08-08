import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/sync_protocol.dart';

/// Thrown when a round trip fails in a way the caller can act on.
class SyncException implements Exception {
  const SyncException(this.message, {this.unauthorized = false});

  final String message;

  /// The token was missing, wrong, or revoked. Distinguished because retrying
  /// is pointless — this needs the user, not a backoff.
  final bool unauthorized;

  @override
  String toString() => 'SyncException: $message';
}

/// One request/response exchange with the backend. An interface so the sync
/// engine can be tested without a server, and so a different backend (or none)
/// can be dropped in without touching the merge logic.
abstract class SyncTransport {
  Future<SyncResponse> exchange(SyncRequest request);

  /// Claim the account this transport's token identifies, creating it if it does
  /// not exist yet. Idempotent: entering an existing token on a second device
  /// joins that account rather than colliding.
  Future<void> claimAccount();
}

/// Talks to the Cloudflare Worker in `worker/`.
///
/// Push and pull are one POST: a separate pull would need its own round trip and
/// could interleave with a push, which is exactly when "did my edit survive?"
/// becomes hard to answer.
class HttpSyncTransport implements SyncTransport {
  HttpSyncTransport({
    required this.baseUrl,
    required this.token,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client();

  final Uri baseUrl;
  final String token;
  final Duration timeout;
  final http.Client _client;

  @override
  Future<SyncResponse> exchange(SyncRequest request) async {
    final http.Response response;
    try {
      response = await _client
          .post(
            baseUrl.resolve('sync'),
            headers: {
              'content-type': 'application/json',
              'authorization': 'Bearer $token',
            },
            body: jsonEncode(request.toJson()),
          )
          .timeout(timeout);
    } catch (e) {
      // Offline is the normal case for this app, not an error worth escalating —
      // the local database is authoritative until a sync succeeds.
      throw SyncException('unreachable: $e');
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const SyncException('rejected by the server', unauthorized: true);
    }
    if (response.statusCode != 200) {
      throw SyncException('http ${response.statusCode}: ${response.body}');
    }

    final decoded = SyncResponse.fromJson(
      jsonDecode(response.body) as Object?,
    );
    if (decoded == null) {
      throw const SyncException('malformed response');
    }
    return decoded;
  }

  @override
  Future<void> claimAccount() async {
    final http.Response response;
    try {
      response = await _client
          .post(baseUrl.resolve('account'), headers: {'authorization': 'Bearer $token'})
          .timeout(timeout);
    } catch (e) {
      throw SyncException('unreachable: $e');
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const SyncException('the server refused this token', unauthorized: true);
    }
    if (response.statusCode != 200) {
      throw SyncException('http ${response.statusCode}: ${response.body}');
    }
  }

  void close() => _client.close();
}
