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
  final _messages = StreamController<WearMessage>.broadcast();
  final _reachability = StreamController<WearReachability>.broadcast();
  int drainCount = 0;

  /// Queued by the native listener service while no engine was running.
  List<WearMessage> pending = [];

  @override
  Stream<WearMessage> get messages => _messages.stream;

  @override
  Stream<WearReachability> get reachability => _reachability.stream;

  @override
  Future<void> send(WearMessage message) async => sent.add(message);

  @override
  Future<void> drainPending() async {
    drainCount++;
    for (final m in pending) {
      _messages.add(m);
    }
    pending = [];
  }

  /// Simulate the peer sending something.
  Future<void> receive(WearMessage message) async {
    _messages.add(message);
    await pump();
  }

  Future<void> becomes(WearReachability state) async {
    _reachability.add(state);
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
