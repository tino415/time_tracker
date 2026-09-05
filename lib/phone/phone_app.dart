import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/manual_sync.dart';
import '../data/sync_service.dart';
import '../theme/tokens.dart';
import 'breakpoints.dart';
import 'screens/activities_screen.dart';
import 'screens/now_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/timeline_screen.dart';
import 'shortcuts.dart';
import 'widgets/neo.dart';
import 'widgets/sync_setup.dart';

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

/// The shell, in whichever of its two shapes the window has room for.
///
/// Narrow is the phone: a header strip, the screen, and the tab bar under the
/// thumb. Wide moves the navigation beside the content and folds the header into
/// it, so the chrome costs a column instead of a column and a strip.
class _Home extends ConsumerWidget {
  const _Home();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(tabProvider);
    final width = MediaQuery.sizeOf(context).width;

    if (width >= sidebarBreakpoint) {
      return Scaffold(
        body: SafeArea(
          // Grouped, or Tab zig-zags between the two. Reading order sorts by
          // rectangle, and a full-height sidebar shares its vertical bands with
          // the first rows of the screen beside it.
          child: Row(
            children: [
              FocusTraversalGroup(child: const _Sidebar()),
              Expanded(child: FocusTraversalGroup(child: _wideBody(tab))),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const _Header(),
            Expanded(
              child: IndexedStack(index: tab, children: [for (final tt in _tabs) tt.screen]),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const _TabBar(),
    );
  }

  /// One screen per destination, same as narrow — each mounted exactly once, so
  /// a second copy never carries its own state and its own database
  /// subscriptions.
  ///
  /// The menu trigger rides above them rather than beside them: a strip spanning
  /// both columns would interleave the focus ring, and Tab is meant to exhaust
  /// the sidebar before it enters the content. Inside this column it is simply
  /// one more content stop.
  Widget _wideBody(int tab) {
    return Stack(
      children: [
        IndexedStack(
          index: tab,
          children: [for (final tt in _tabs) _ReadableWidth(child: tt.screen)],
        ),
        const Positioned(top: 12, right: 12, child: _MenuTrigger()),
      ],
    );
  }
}

/// Caps and centres a column of content. The screens keep owning their gutters;
/// how wide any of them is *allowed* to get is the shell's business, so the
/// number lives in one place instead of in each screen.
class _ReadableWidth extends StatelessWidget {
  const _ReadableWidth({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: contentMaxWidth),
        child: child,
      ),
    );
  }
}

/// The wordmark strip, and nothing else.
///
/// It used to carry the app controls at its right edge, which put them in the
/// far corner from a thumb holding the phone one-handed — the position a phone
/// is actually held in. They are under the thumb now, at the end of the tab bar.
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(children: [_Wordmark()]),
    );
  }
}

class _TabBar extends ConsumerWidget {
  const _TabBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = neo(context);
    final tab = ref.watch(tabProvider);

    return SafeArea(
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
            // Fixed width, not a fifth Expanded cell. The cells carry no
            // horizontal padding and the labels are 11px mono, so five equal
            // cells on a 360px phone give 72px each — about what ACTIVITIES
            // needs on its own, and the label sets no overflow, so it would clip
            // rather than degrade.
            //
            // Kept out of `_tabs` as well: that list also builds the sidebar,
            // and the index constants beside it are what the shortcuts address.
            // This is an action, and only the bar it is drawn in has room for
            // that distinction to not matter.
            const _MoreCell(),
          ],
        ),
      ),
    );
  }
}

/// The app's own controls, under the thumb.
///
/// A sheet rather than a popup: it is the frame every other sheet in the app
/// uses, and it disappears under the soft keyboard along with the bar it hangs
/// off — which matters, because Now's vertical budget is the binding constraint
/// on that screen and this costs it nothing.
class _MoreCell extends ConsumerWidget {
  const _MoreCell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = neo(context);
    return Container(
      width: 52,
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: t.line, width: 3)),
      ),
      child: _TabButton(
        label: '•••',
        active: false,
        onTap: () => showNeoSheet<void>(context, (_) => const _AppControlsSheet()),
      ),
    );
  }
}

/// [_AppControls] in the frame the narrow shell opens it in.
class _AppControlsSheet extends StatelessWidget {
  const _AppControlsSheet();

  @override
  Widget build(BuildContext context) {
    final t = neo(context);
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: t.bg,
          border: Border.all(color: t.line, width: 3),
        ),
        padding: const EdgeInsets.all(14),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [NeoSectionHeader('app'), SizedBox(height: 12), _AppControls()],
        ),
      ),
    );
  }
}

/// The same destinations down the side, with room for the labels to be read
/// rather than squeezed, and the header's controls at the foot — one shell-level
/// spot for them instead of a strip across the top of every screen.
class _Sidebar extends ConsumerWidget {
  const _Sidebar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = neo(context);
    final tab = ref.watch(tabProvider);

    return Container(
      width: sidebarWidth,
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(right: BorderSide(color: t.line, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 18), child: _Wordmark()),
          for (var i = 0; i < _tabs.length; i++)
            _TabButton(
              label: _tabs[i].label,
              active: i == tab,
              onTap: () => ref.read(tabProvider.notifier).state = i,
              leftAligned: true,
            ),
          const Spacer(),
        ],
      ),
    );
  }
}

/// The wide shell's way into the app's controls: top right, where a desktop
/// looks for them.
///
/// They used to sit at the foot of the sidebar, because that is where the
/// header folds in at this width — bottom left, which is the furthest point on
/// the screen from where anyone goes looking for settings.
///
/// Deliberately not the phone's gesture. A bottom sheet beside a mouse arrives
/// from the wrong edge, and the two shells already differ in every other way
/// they present the same four things.
class _MenuTrigger extends ConsumerWidget {
  const _MenuTrigger();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _ControlButton(
      label: '⚙ MENU',
      onTap: () => showNeoMenu<void>(context, (_) => const _AppControls()),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return Text(
      '[track]',
      style: mono(context, size: 18, weight: FontWeight.w800, color: neo(context).brand),
    );
  }
}

/// The controls that belong to the app rather than to a screen. A [Wrap] so the
/// same widget serves the header's wide strip and the sidebar's narrower foot —
/// which only works where the host hands it a width. The sidebar does so by
/// being a stretched Column child; the header needs an [Expanded] to.
class _AppControls extends ConsumerWidget {
  const _AppControls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        // The keyboard list needs a control that is *seen*. It was reachable
        // only by Cmd/Ctrl+/ — a keystroke to discover the keystrokes — and
        // Safari takes that combination for its status bar, so on Safari the
        // list could not be opened at all.
        //
        // Shown on the web only. The bindings themselves stay installed
        // everywhere (a Bluetooth keyboard on a phone should work), but a
        // keyboard button on a touch phone is noise, and the platform is the
        // honest signal here rather than how wide the window happens to be.
        if (kIsWeb) _ControlButton(label: '⌨ KEYS', onTap: () => showShortcutsHelp(context, ref)),
        _ControlButton(
          label: '◑ THEME',
          onTap: () {
            final cur = Theme.of(context).brightness;
            ref.read(themeModeProvider.notifier).state = cur == Brightness.dark
                ? ThemeMode.light
                : ThemeMode.dark;
          },
        ),
        const _SyncControls(),
      ],
    );
  }
}

/// Manual sync, reachable from every screen rather than sunk at the bottom of
/// Reports' category list — the more activities exist, the further down that
/// list it sank.
///
/// Hidden entirely when no backend is configured — sync is optional, and an
/// action that cannot work is worse than no action.
///
/// Manual rather than a background loop, because the local database is
/// authoritative: syncing is how devices *agree*, not how the app works, so its
/// failure has to be inert and its timing the user's business.
///
/// The button is one of two ways to ask and `r` is the other, which is why the
/// running flag and the result line live in [manualSyncProvider] rather than in
/// this widget.
class _SyncControls extends ConsumerWidget {
  const _SyncControls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = neo(context);
    // No server in this build: nothing to offer, so offer nothing.
    if (!ref.watch(syncConfigProvider).hasServer) return const SizedBox.shrink();

    // A server but no account — sync is opt-in, and this is the invitation.
    if (ref.watch(syncServiceProvider) == null) {
      return _ControlButton(label: '⟳ SYNC', onTap: () => showSyncSetup(context, ref));
    }

    final sync = ref.watch(manualSyncProvider);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _ControlButton(
          label: sync.running ? '⟳ SYNCING…' : '⟳ SYNC',
          onTap: sync.running ? null : ref.read(manualSyncProvider.notifier).run,
        ),
        _ControlButton(label: '⚙', onTap: () => showSyncSetup(context, ref)),
        if (sync.status != null)
          Text(
            sync.status!,
            // The one control sized by a result rather than by a label. The
            // strip bounds it now, so this is only about how many lines a long
            // one may take out of the body.
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: mono(context, size: 10, weight: FontWeight.w700, color: t.muted),
          ),
      ],
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = neo(context);
    return NeoPressable(
      fill: t.line,
      shadowOffset: 3,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      onTap: onTap,
      child: Text(
        label,
        style: mono(context, size: 11, weight: FontWeight.w700, color: t.surface),
      ),
    );
  }
}

/// One destination, in the bottom bar or down the sidebar. Active is the inverse
/// fill in both; only the alignment differs, because a bar centres four cells
/// across a width and a sidebar reads as a list.
///
/// Focus is drawn as an inset two-tone outline rather than [NeoPressable]'s
/// brand shadow: these cells carry no shadow to recolour, and a *foreground*
/// decoration paints over the label instead of insetting it the way a real
/// border would. A `BoxDecoration` only holds one border, so the two tones —
/// same [NeoTokens.focusBandWidth]/[NeoTokens.focusRingWidth] the shadow
/// version reads — are two nested `Container`s in an `IgnorePointer` overlay:
/// a bordered `Container` insets its child by the border's width for free, so
/// nesting one inside the other draws concentric rings without touching the
/// label's own layout. The active tab is the case this exists for — its fill
/// is `t.line`, the colour the ring measures worst against.
class _TabButton extends StatefulWidget {
  const _TabButton({
    required this.label,
    required this.active,
    required this.onTap,
    this.leftAligned = false,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final bool leftAligned;

  @override
  State<_TabButton> createState() => _TabButtonState();
}

class _TabButtonState extends State<_TabButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final t = neo(context);
    return FocusableActionDetector(
      mouseCursor: SystemMouseCursors.click,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onTap()),
        ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(onInvoke: (_) => widget.onTap()),
      },
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            Container(
              color: widget.active ? t.line : t.surface,
              padding: widget.leftAligned
                  ? const EdgeInsets.fromLTRB(16, 14, 16, 14)
                  : const EdgeInsets.symmetric(vertical: 12),
              alignment: widget.leftAligned ? Alignment.centerLeft : Alignment.center,
              child: Text(
                widget.label.toUpperCase(),
                style: mono(
                  context,
                  size: 11,
                  weight: FontWeight.w800,
                  spacing: .6,
                  color: widget.active ? t.surface : t.muted,
                ),
              ),
            ),
            if (_focused)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: t.bg, width: NeoTokens.focusBandWidth),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: t.brand, width: NeoTokens.focusRingWidth),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
