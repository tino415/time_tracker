import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'sync_service.dart';
import 'sync_transport.dart';

/// Syncs without being asked.
///
/// The manual button stays: this app is offline-first and the local database is
/// authoritative, so syncing is how devices *agree*, not how the app works. What
/// changes is that agreeing no longer depends on remembering to ask.
///
/// Three triggers, chosen because they match when divergence actually matters:
///  * **start** — the other device may have moved on while this one was closed;
///  * **resume** — the same, for a phone that is never really closed;
///  * **after a local edit**, debounced — so a burst of switching produces one
///    sync rather than one per tap.
///
/// Everything here is deliberately inert on failure. Being offline is this
/// app's normal state, not an error, and a background sync that surfaced
/// problems would be a constant irritation for something the user did not ask
/// for. Only the manual button reports outcomes.
/// Deliberately knows nothing about widgets: the app lifecycle is observed by
/// the shell, which calls [onResumed]. That keeps the scheduling — the part with
/// the interesting failure modes — testable without a binding.
class AutoSyncService {
  AutoSyncService({
    required SyncService sync,
    required Stream<Object?> localChanges,
    this.debounce = const Duration(seconds: 20),
    this.minInterval = const Duration(minutes: 1),
    DateTime Function()? clock,
  }) : _sync = sync,
       _localChanges = localChanges,
       _now = clock ?? DateTime.now;

  final SyncService _sync;
  final Stream<Object?> _localChanges;
  final DateTime Function() _now;

  /// How long to wait after the last local edit. Long enough that switching
  /// activities a few times in a row is one sync, short enough that a change is
  /// on the other device before you look at it.
  final Duration debounce;

  /// Floor between syncs, so a steady trickle of edits cannot turn into a
  /// request per edit.
  final Duration minInterval;

  StreamSubscription<Object?>? _subscription;
  Timer? _pending;
  DateTime? _lastAttempt;
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    _subscription = _localChanges.listen((_) => _scheduleAfterChange());
    unawaited(_run());
  }

  /// Called by the shell when the app comes back to the foreground — the other
  /// device may have moved on while this one was away.
  void onResumed() => unawaited(_run());

  void _scheduleAfterChange() {
    _pending?.cancel();
    _pending = Timer(debounce, () => unawaited(_run()));
  }

  Future<void> _run() async {
    final last = _lastAttempt;
    // Rate limit on *attempts*, not successes: a device that is offline should
    // not retry every time a stream ticks.
    if (last != null && _now().difference(last) < minInterval) return;
    _lastAttempt = _now();

    try {
      await _sync.syncNow();
    } on SyncException {
      // Offline, or a token the server no longer likes. Neither is actionable
      // from a background task, and the local database is unaffected.
    }
  }

  void dispose() {
    _pending?.cancel();
    _subscription?.cancel();
    _started = false;
  }
}

/// Null when sync is not configured, matching [syncServiceProvider].
final autoSyncProvider = Provider<AutoSyncService?>((ref) {
  final sync = ref.watch(syncServiceProvider);
  if (sync == null) return null;

  // Both streams: an edit to an activity (rename, colour, bookmark) and an edit
  // to the timeline (a switch, a retimed boundary) are equally worth sending.
  final service = AutoSyncService(
    sync: sync,
    localChanges: StreamGroup.merge([
      ref.watch(activityRepositoryProvider).watchActivities(),
      ref.watch(changeRepositoryProvider).watchChanges(),
    ]),
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Minimal stream merge, to avoid a dependency on package:async for one use.
class StreamGroup {
  static Stream<Object?> merge(List<Stream<Object?>> streams) {
    final controller = StreamController<Object?>.broadcast();
    final subs = <StreamSubscription<Object?>>[];
    controller.onListen = () {
      for (final s in streams) {
        subs.add(s.listen(controller.add, onError: (_) {}));
      }
    };
    controller.onCancel = () async {
      for (final s in subs) {
        await s.cancel();
      }
      subs.clear();
    };
    return controller.stream;
  }
}
