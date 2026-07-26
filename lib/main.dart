import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
