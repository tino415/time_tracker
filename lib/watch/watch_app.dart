import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Wear OS shell — stub for the scaffold. The real watch UI (a bookmarked-only
/// quick-switch grid + a Wear MessageClient bridge relaying changes to the
/// phone) lands in the watch phase. Kept minimal so the Android build that
/// targets both phone and watch still compiles.
class WatchApp extends StatelessWidget {
  const WatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: neoTheme(NeoTokens.dark, Brightness.dark),
      home: Scaffold(
        backgroundColor: NeoTokens.dark.bg,
        body: const Center(
          child: Text(
            '[track]\nwatch — soon',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: kMonoFont,
              fontWeight: FontWeight.w800,
              color: Color(0xFF57C97D),
            ),
          ),
        ),
      ),
    );
  }
}
