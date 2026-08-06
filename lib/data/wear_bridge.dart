import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/wear_protocol.dart';

/// Transport to the paired device. An interface rather than a bare
/// MethodChannel so the sync logic and the watch UI can be driven by a fake in
/// tests — a real exchange needs two paired devices, which no test harness has.
abstract class WearBridge {
  /// Messages from the peer, plus any that the listener service parked on disk
  /// while no engine was running.
  Stream<WearMessage> get messages;

  /// How the peer can currently be reached. Emits on every capability change.
  Stream<WearReachability> get reachability;

  Future<void> send(WearMessage message);

  /// Ask for the backlog the native listener service queued while the app was
  /// dead. Safe to call repeatedly; draining is destructive on the native side.
  Future<void> drainPending();

  void dispose();
}

/// The real bridge, over the channels [WearBridgeHost] serves on the Kotlin
/// side. One APK covers both form factors, so this is the same class on the
/// phone and on the watch — only the messages differ.
class ChannelWearBridge implements WearBridge {
  ChannelWearBridge({
    MethodChannel? method,
    EventChannel? events,
  })  : _method = method ?? const MethodChannel('time_tracker/wear/method'),
        _events = events ?? const EventChannel('time_tracker/wear/events') {
    _subscription = _events.receiveBroadcastStream().listen(
      _onEvent,
      onError: (Object error) {
        // A dead channel must not take the app down: the watch still works
        // against its cached snapshot, and the phone is unaffected.
        debugPrint('wear bridge stream error: $error');
      },
    );
  }

  final MethodChannel _method;
  final EventChannel _events;
  StreamSubscription<dynamic>? _subscription;

  final _messages = StreamController<WearMessage>.broadcast();
  final _reachability = StreamController<WearReachability>.broadcast();

  @override
  Stream<WearMessage> get messages => _messages.stream;

  @override
  Stream<WearReachability> get reachability => _reachability.stream;

  void _onEvent(Object? event) {
    if (event is! Map) return;
    final type = event['type'];
    final payload = event['payload'];

    // Reachability rides the same channel under a reserved type rather than a
    // second EventChannel — it is a property of the transport, not a message.
    if (type == '_reachability') {
      final state = payload is Map ? payload['state'] : null;
      _reachability.add(WearReachability.parse(state));
      return;
    }

    final message = WearMessage.decode(type, payload);
    if (message != null) _messages.add(message);
  }

  @override
  Future<void> send(WearMessage message) async {
    try {
      await _method.invokeMethod<void>('send', {
        'type': message.type,
        'payload': message.toPayload(),
      });
    } on PlatformException catch (e) {
      // Out of range, unpaired, or the peer app not installed. The caller
      // cannot do anything useful about it, and the watch's own state is
      // already correct, so this is logged rather than thrown.
      debugPrint('wear send(${message.type}) failed: ${e.message}');
    } on MissingPluginException {
      // No native side — e.g. the web build. Nothing to relay to.
    }
  }

  @override
  Future<void> drainPending() async {
    try {
      final pending = await _method.invokeListMethod<Object?>('drainPending');
      for (final raw in pending ?? const <Object?>[]) {
        if (raw is! Map) continue;
        final message = WearMessage.decode(raw['type'], raw['payload']);
        if (message != null) _messages.add(message);
      }
    } on PlatformException catch (e) {
      debugPrint('wear drainPending failed: ${e.message}');
    } on MissingPluginException {
      // No native side.
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _messages.close();
    _reachability.close();
  }
}

/// Stand-in for platforms with no Wear layer at all (web, desktop, tests that
/// do not care). Accepts sends and reports nothing.
class NullWearBridge implements WearBridge {
  const NullWearBridge();

  @override
  Stream<WearMessage> get messages => const Stream.empty();

  @override
  Stream<WearReachability> get reachability => const Stream.empty();

  @override
  Future<void> send(WearMessage message) async {}

  @override
  Future<void> drainPending() async {}

  @override
  void dispose() {}
}

/// The bridge for this platform. Overridden in tests with a fake.
final wearBridgeProvider = Provider<WearBridge>((ref) {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return const NullWearBridge();
  }
  final bridge = ChannelWearBridge();
  ref.onDispose(bridge.dispose);
  return bridge;
});
