import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'phone/phone_app.dart';
import 'watch/watch_app.dart';

const _platformChannel = MethodChannel('time_tracker/platform');

Future<bool> _detectIsWatch() async {
  if (kIsWeb) return false;
  if (defaultTargetPlatform != TargetPlatform.android) return false;
  try {
    return await _platformChannel.invokeMethod<bool>('isWatch') ?? false;
  } catch (_) {
    return false;
  }
}

/// Held for the process lifetime: disposing the handle turns semantics back off,
/// so it is deliberately never released.
// ignore: unused_element
SemanticsHandle? _semanticsHandle;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kIsWeb) {
    // Flutter web renders into a canvas and only builds its DOM accessibility
    // tree once something asks for one — normally a screen reader, or the user
    // finding the hidden "enable accessibility" button. Asking up front means
    // assistive technology works immediately, and it gives the page real
    // <flt-semantics> elements, which is the only way to drive the web build
    // from a browser test without guessing at canvas coordinates.
    _semanticsHandle = SemanticsBinding.instance.ensureSemantics();
  }

  final isWatch = await _detectIsWatch();
  runApp(
    ProviderScope(
      overrides: [isWatchProvider.overrideWithValue(isWatch)],
      child: TimeTrackerRoot(isWatch: isWatch),
    ),
  );
}

/// Whether this build runs on a Wear OS device. Overridden in [main] after
/// platform detection; default false so tests take the phone branch.
final isWatchProvider = Provider<bool>((ref) => false);

/// Root shell picker. Every surface is offline-first on local Drift — the web
/// PWA runs the same phone shell (not a server-direct build), so only watch vs
/// phone differ here. Cross-device sync attaches later as a transport layer.
class TimeTrackerRoot extends ConsumerWidget {
  const TimeTrackerRoot({super.key, required this.isWatch});

  final bool isWatch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isWatch) return const WatchApp();
    return const PhoneApp();
  }
}
