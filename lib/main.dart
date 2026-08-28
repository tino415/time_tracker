import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/auto_sync.dart';
import 'data/pointer_probe.dart';
import 'data/pointer_signal.dart';
import 'data/wear_sync.dart';
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
  final hasPointer = probeHasPointer();
  runApp(
    ProviderScope(
      overrides: [
        isWatchProvider.overrideWithValue(isWatch),
        hasPointerProvider.overrideWithValue(hasPointer),
      ],
      child: TimeTrackerRoot(isWatch: isWatch),
    ),
  );
}

/// Root shell picker. Every surface is offline-first on local Drift — the web
/// PWA runs the same phone shell (not a server-direct build), so only watch vs
/// phone differ here.
///
/// Stateful only to own the Wear sync service's lifetime: both form factors run
/// it (the phone answers snapshot requests and applies relayed switches, the
/// watch asks and relays), and it must be started once, after the first frame
/// is on its way rather than blocking it.
class TimeTrackerRoot extends ConsumerStatefulWidget {
  const TimeTrackerRoot({super.key, required this.isWatch});

  final bool isWatch;

  @override
  ConsumerState<TimeTrackerRoot> createState() => _TimeTrackerRootState();
}

class _TimeTrackerRootState extends ConsumerState<TimeTrackerRoot> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Fire-and-forget: a missing or unpaired Wear layer must not delay or block
    // the UI, and every failure inside is already swallowed at the bridge.
    unawaited(ref.read(wearSyncProvider).start());

    // Null unless a sync backend is configured. Same contract as the Wear
    // bridge: it must not delay the first frame, and its failures are inert.
    ref.read(autoSyncProvider)?.start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back to the foreground is the moment the other device is most
    // likely to have moved on.
    if (state == AppLifecycleState.resumed) ref.read(autoSyncProvider)?.onResumed();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isWatch) return const WatchApp();
    return const PhoneApp();
  }
}
