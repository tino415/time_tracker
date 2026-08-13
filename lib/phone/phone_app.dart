import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/tokens.dart';
import 'screens/activities_screen.dart';
import 'screens/now_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/timeline_screen.dart';
import 'shortcuts.dart';
import 'widgets/neo.dart';

/// App-wide theme mode, toggled from the header.
final themeModeProvider = StateProvider<ThemeMode>((_) => ThemeMode.system);

/// Selected bottom-nav tab.
final tabProvider = StateProvider<int>((_) => 0);

/// Tab indices, named so shortcuts and tests address a screen rather than a
/// position in a list that may be reordered.
const nowTab = 0;
const timelineTab = 1;
const reportsTab = 2;
const activitiesTab = 3;

class PhoneApp extends ConsumerWidget {
  const PhoneApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Track',
      debugShowCheckedModeBanner: false,
      theme: neoTheme(NeoTokens.light, Brightness.light),
      darkTheme: neoTheme(NeoTokens.dark, Brightness.dark),
      themeMode: ref.watch(themeModeProvider),
      // Inside the home route, not around the Navigator: a dialog or sheet is a
      // sibling route, so while one is open the bindings are deliberately deaf.
      home: const AppShortcuts(child: _Home()),
    );
  }
}

const _tabs = <({String label, Widget screen})>[
  (label: 'Now', screen: NowScreen()),
  (label: 'Timeline', screen: TimelineScreen()),
  (label: 'Reports', screen: ReportsScreen()),
  (label: 'Activities', screen: ActivitiesScreen()),
];

class _Home extends ConsumerWidget {
  const _Home();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = neo(context);
    final tab = ref.watch(tabProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const _Header(),
            Expanded(
              child: IndexedStack(
                index: tab,
                children: [for (final tt in _tabs) tt.screen],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          // An explicit height is required: each tab is a centre-aligned
          // Container, which expands to whatever height it is offered — without
          // this the bar would claim the whole screen and collapse the body.
          height: 52,
          decoration: BoxDecoration(
            color: t.surface,
            border: Border(top: BorderSide(color: t.line, width: 3)),
          ),
          child: Row(
            children: [
              for (var i = 0; i < _tabs.length; i++)
                Expanded(
                  child: _TabButton(
                    label: _tabs[i].label,
                    active: i == tab,
                    onTap: () => ref.read(tabProvider.notifier).state = i,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = neo(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('[track]', style: mono(context, size: 18, weight: FontWeight.w800, color: t.brand)),
          const Spacer(),
          // The keyboard list needs a control that is *seen*. It was reachable
          // only by Cmd/Ctrl+/ — a keystroke to discover the keystrokes — and
          // Safari takes that combination for its status bar, so on Safari the
          // list could not be opened at all.
          //
          // Shown on the web only. The bindings themselves stay installed
          // everywhere (a Bluetooth keyboard on a phone should work), but a
          // keyboard button on a touch phone is noise, and the platform is the
          // honest signal here rather than how wide the window happens to be.
          if (kIsWeb) ...[
            NeoPressable(
              fill: t.line,
              shadowOffset: 3,
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              onTap: () => showShortcutsHelp(context),
              child: Text('⌨ KEYS',
                  style: mono(context, size: 11, weight: FontWeight.w700, color: t.surface)),
            ),
            const SizedBox(width: 8),
          ],
          NeoPressable(
            fill: t.line,
            shadowOffset: 3,
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            onTap: () {
              final cur = Theme.of(context).brightness;
              ref.read(themeModeProvider.notifier).state =
                  cur == Brightness.dark ? ThemeMode.light : ThemeMode.dark;
            },
            child: Text('◑ THEME',
                style: mono(context, size: 11, weight: FontWeight.w700, color: t.surface)),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = neo(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: active ? t.line : t.surface,
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        child: Text(
          label.toUpperCase(),
          style: mono(
            context,
            size: 11,
            weight: FontWeight.w800,
            spacing: .6,
            color: active ? t.surface : t.muted,
          ),
        ),
      ),
    );
  }
}
