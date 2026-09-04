import 'dart:async';

import 'package:time_tracker/data/wear_bridge.dart';
import 'package:time_tracker/domain/wear_protocol.dart';

/// A bridge with no device on the other end: records what was sent, and lets a
/// test push inbound messages as if a peer had.
///
/// This is the seam that makes the Wear work testable at all — a real exchange
/// needs two paired devices, which neither the widget harness nor a single
/// emulator has. Everything either side *decides* runs against this; only the
/// delivery itself is left to the manual pass.
class FakeWearBridge implements WearBridge {
  final sent = <WearMessage>[];

  /// Every payload handed to [cacheCurrent], in order, standing in for what
  /// would land in `current_state.json` on the native side.
  final cached = <Map<String, Object?>>[];
  final _messages = StreamController<WearMessage>.broadcast();
  final _reachability = StreamController<WearReachability>.broadcast();
  int drainCount = 0;

  /// Queued by the native listener service while no engine was running.
  List<WearMessage> pending = [];

  @override
  Stream<WearMessage> get messages => _messages.stream;

  @override
  Stream<WearReachability> get reachability => _reachability.stream;

  /// Whether a peer is reachable. Set false to model an out-of-range send, which
  /// the sender must notice rather than assume delivered.
  bool deliverable = true;

  /// How many more sends succeed before the peer goes away again. Null is
  /// unlimited; it exists to model a walk out of range *mid-drain*, which is
  /// the case where a backlog can be half-delivered.
  int? deliverableCount;

  @override
  Future<bool> send(WearMessage message) async {
    if (!deliverable) return false;
    final budget = deliverableCount;
    if (budget != null) {
      if (budget <= 0) return false;
      deliverableCount = budget - 1;
    }
    sent.add(message);
    return true;
  }

  @override
  Future<void> drainPending() async {
    drainCount++;
    for (final m in pending) {
      _messages.add(m);
    }
    pending = [];
  }

  @override
  Future<void> cacheCurrent(Map<String, Object?> payload) async {
    cached.add(payload);
  }

  /// Simulate the peer sending something, without waiting for the handlers.
  ///
  /// Widget tests must use this and then pump the tester: [pump] below waits on
  /// a real timer, and inside `testWidgets` timers are fake — they only fire
  /// when the tester pumps, so awaiting one from the test body deadlocks.
  void emit(WearMessage message) => _messages.add(message);

  void emitReachability(WearReachability state) => _reachability.add(state);

  /// Simulate the peer sending something and let the handlers finish. Plain
  /// `test()` only — see [emit].
  Future<void> receive(WearMessage message) async {
    emit(message);
    await pump();
  }

  Future<void> becomes(WearReachability state) async {
    emitReachability(state);
    await pump();
  }

  /// Let the service's async handlers run to completion.
  Future<void> pump() => Future<void>.delayed(Duration.zero);

  @override
  void dispose() {
    _messages.close();
    _reachability.close();
  }
}
