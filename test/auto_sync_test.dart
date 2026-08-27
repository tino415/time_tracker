// Automatic syncing: when it fires, and — more importantly — when it does not.
//
// The failure mode worth guarding is a background task that syncs too eagerly:
// a request per tap while switching activities, or a retry storm while offline.
// Both are invisible in normal use and expensive on a phone.

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/data/auto_sync.dart';
import 'package:time_tracker/data/sync_service.dart';
import 'package:time_tracker/data/sync_transport.dart';
import 'package:time_tracker/domain/sync_protocol.dart';

/// Counts round trips without touching a database.
class CountingTransport implements SyncTransport {
  int calls = 0;
  bool offline = false;

  @override
  Future<void> claimAccount() async {}

  @override
  Future<SyncResponse> exchange(SyncRequest request) async {
    calls++;
    if (offline) throw const SyncException('unreachable');
    return const SyncResponse(cursor: '1');
  }
}

/// A SyncService that does nothing but count, so these tests are about the
/// *scheduling* rather than the exchange.
class CountingSync implements SyncService {
  CountingSync(this.transport);
  final CountingTransport transport;

  @override
  Future<SyncResult> syncNow() async {
    await transport.exchange(const SyncRequest(cursor: null));
    return SyncResult.none;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late CountingTransport transport;
  late StreamController<Object?> changes;

  setUp(() {
    transport = CountingTransport();
    changes = StreamController<Object?>.broadcast();
  });

  tearDown(() => changes.close());

  AutoSyncService serviceFor({Duration? debounce, Duration? minInterval}) => AutoSyncService(
    sync: CountingSync(transport),
    localChanges: changes.stream,
    debounce: debounce ?? const Duration(seconds: 20),
    minInterval: minInterval ?? const Duration(minutes: 1),
  );

  test('syncs once on start', () {
    fakeAsync((async) {
      final service = serviceFor();
      service.start();
      async.elapse(const Duration(seconds: 1));

      expect(transport.calls, 1);
      service.dispose();
    });
  });

  test('a burst of local edits produces one sync, not one per edit', () {
    fakeAsync((async) {
      final service = serviceFor(minInterval: Duration.zero);
      service.start();
      async.elapse(const Duration(seconds: 1));
      transport.calls = 0;

      // Switching activities a few times in quick succession.
      for (var i = 0; i < 5; i++) {
        changes.add(null);
        async.elapse(const Duration(seconds: 2));
      }
      async.elapse(const Duration(seconds: 30));

      expect(transport.calls, 1);
      service.dispose();
    });
  });

  test('the debounce restarts on each edit rather than firing mid-burst', () {
    fakeAsync((async) {
      final service = serviceFor(debounce: const Duration(seconds: 10), minInterval: Duration.zero);
      service.start();
      async.elapse(const Duration(seconds: 1));
      transport.calls = 0;

      changes.add(null);
      async.elapse(const Duration(seconds: 8)); // not yet
      expect(transport.calls, 0);
      changes.add(null);
      async.elapse(const Duration(seconds: 8)); // still not, the timer restarted
      expect(transport.calls, 0);
      async.elapse(const Duration(seconds: 3));
      expect(transport.calls, 1);

      service.dispose();
    });
  });

  test('minInterval throttles a steady trickle of edits', () {
    fakeAsync((async) {
      final service = serviceFor(
        debounce: const Duration(seconds: 1),
        minInterval: const Duration(minutes: 5),
      );
      service.start();
      async.elapse(const Duration(seconds: 2));
      expect(transport.calls, 1);

      // An edit every ten seconds for two minutes: without a floor this would
      // be a request each time the debounce expired.
      for (var i = 0; i < 12; i++) {
        changes.add(null);
        async.elapse(const Duration(seconds: 10));
      }

      expect(transport.calls, 1);
      service.dispose();
    });
  });

  test('being offline does not become a retry storm', () {
    fakeAsync((async) {
      transport.offline = true;
      final service = serviceFor(
        debounce: const Duration(seconds: 1),
        minInterval: const Duration(minutes: 5),
      );
      service.start();
      async.elapse(const Duration(seconds: 2));

      for (var i = 0; i < 10; i++) {
        changes.add(null);
        async.elapse(const Duration(seconds: 10));
      }

      // Rate limiting is on attempts, not successes — otherwise a device that
      // cannot reach the server would try on every single stream tick.
      expect(transport.calls, 1);
      service.dispose();
    });
  });

  test('a failed sync never escapes', () {
    fakeAsync((async) {
      transport.offline = true;
      final service = serviceFor();
      service.start();
      async.elapse(const Duration(seconds: 1));

      // Offline is this app's normal state; a background task must not surface
      // it. Reaching here without an unhandled exception is the assertion.
      expect(transport.calls, 1);
      service.dispose();
    });
  });

  test('dispose stops everything', () {
    fakeAsync((async) {
      final service = serviceFor(debounce: const Duration(seconds: 1), minInterval: Duration.zero);
      service.start();
      async.elapse(const Duration(seconds: 1));
      transport.calls = 0;

      changes.add(null);
      service.dispose();
      async.elapse(const Duration(seconds: 30));

      expect(transport.calls, 0);
    });
  });
}
