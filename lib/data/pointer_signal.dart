import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether a mouse (or a trackpad acting like one) is available on this
/// device — the signal that turns text selection on. Overridden in `main()`
/// from `pointer_probe.dart` after platform detection; defaults to false so
/// every existing widget test keeps today's touch-only behaviour.
final hasPointerProvider = Provider<bool>((ref) => false);
