import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/tracker_controller.dart';
import 'phone_app.dart';
import 'screens/now_screen.dart';
import 'screens/reports_screen.dart';
import 'widgets/neo.dart';

/// Keyboard shortcuts for the desktop PWA.
///
/// Every action here already has a tap target — this screen is a phone app
/// first. What the keyboard buys is not new capability but the removal of the
/// slowest step of using it on a desktop: taking a hand off the keys to move
/// one tab.
///
/// They stay installed on phone and watch. A `Shortcuts` widget with no keyboard
/// attached costs nothing, and gating it on `kIsWeb` would only mean a Bluetooth
/// keyboard on the phone is deliberately ignored.

/// Cmd on Apple platforms, Ctrl everywhere else — the modifier each platform's
/// users already reach for.
///
/// Note the consequence on macOS, where this is Cmd: Chrome owns Cmd+1‥8 for
/// its own tab strip and does not pass it to the page, so the tab bindings work
/// in the installed window and are shadowed in an ordinary browser tab. Ctrl
/// would have been free in both, and was traded away for the native feel.
bool get _isApple =>
    defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.iOS;

/// How to write the modifier in help text.
String modifierLabel() => _isApple ? '⌘' : 'Ctrl';

/// A shortcut bound to a key's **position** rather than to the character it
/// produces.
///
/// [SingleActivator] matches a [LogicalKeyboardKey], which is what the keyboard
/// layout produced — and on a Slovak layout the key left of `2` types `+`, not
/// `1`. A logical `digit1` binding is therefore not merely relabelled there but
/// unreachable, and every layout would need its own table. Matching
/// [PhysicalKeyboardKey] makes the binding the same finger movement on every
/// layout; only the legend printed on the keycap differs.
///
/// [triggers] returns null because there is no logical key to index this under.
/// [ShortcutManager] then offers it every key event instead — the same
/// arrangement [CharacterActivator] uses, and the reason this works at all.
class PhysicalActivator implements ShortcutActivator {
  const PhysicalActivator(this.key);

  final PhysicalKeyboardKey key;

  @override
  Iterable<LogicalKeyboardKey>? get triggers => null;

  @override
  bool accepts(KeyEvent event, HardwareKeyboard state) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    if (event.physicalKey != key) return false;
    // Shift is deliberately not required to be up. On layouts where a digit is
    // the shifted symbol, shifting is the natural way to ask for "1" — and
    // since these are position bindings, holding it changes nothing about which
    // key was pressed. The other modifiers must be exactly right, so that
    // Ctrl+Alt+1 is not silently the same as Ctrl+1.
    if (_isApple) {
      return state.isMetaPressed && !state.isControlPressed && !state.isAltPressed;
    }
    return state.isControlPressed && !state.isMetaPressed && !state.isAltPressed;
  }

  @override
  String debugDescribeKeys() => '${modifierLabel()} + ${key.debugName ?? key.usbHidUsage}';
}

class GoToTabIntent extends Intent {
  const GoToTabIntent(this.tab);
  final int tab;
}

class FocusSearchIntent extends Intent {
  const FocusSearchIntent();
}

class StartUnnamedIntent extends Intent {
  const StartUnnamedIntent();
}

class ShiftWeekIntent extends Intent {
  const ShiftWeekIntent(this.delta);
  final int delta;
}

class ShowShortcutsIntent extends Intent {
  const ShowShortcutsIntent();
}

/// One binding, carrying everything the help overlay needs to describe it — so
/// adding a shortcut cannot leave the list that documents them out of date.
class ShortcutBinding {
  const ShortcutBinding({
    required this.key,
    required this.label,
    required this.what,
    required this.intent,
    this.only,
  });

  final PhysicalKeyboardKey key;

  /// The legend this key carries on a US keyboard. Only ever shown to the user;
  /// the binding itself is positional, so on another layout the same key may be
  /// printed differently.
  final String label;

  final String what;
  final Intent intent;

  /// The screen this only applies on, or null for anywhere.
  final String? only;
}

const shortcutBindings = <ShortcutBinding>[
  ShortcutBinding(
    key: PhysicalKeyboardKey.digit1,
    label: '1',
    what: 'Now',
    intent: GoToTabIntent(nowTab),
  ),
  ShortcutBinding(
    key: PhysicalKeyboardKey.digit2,
    label: '2',
    what: 'Timeline',
    intent: GoToTabIntent(timelineTab),
  ),
  ShortcutBinding(
    key: PhysicalKeyboardKey.digit3,
    label: '3',
    what: 'Reports',
    intent: GoToTabIntent(reportsTab),
  ),
  ShortcutBinding(
    key: PhysicalKeyboardKey.digit4,
    label: '4',
    what: 'Activities',
    intent: GoToTabIntent(activitiesTab),
  ),
  ShortcutBinding(
    key: PhysicalKeyboardKey.keyL,
    label: 'L',
    what: 'Search, or paste a task id',
    intent: FocusSearchIntent(),
  ),
  ShortcutBinding(
    key: PhysicalKeyboardKey.enter,
    // Spelled out rather than "↵": the mono face renders it small enough to
    // read as a smudge, and the codebase already prefers a plain word to a
    // glyph the font handles poorly.
    label: 'Enter',
    what: 'Start a block, name it later',
    intent: StartUnnamedIntent(),
  ),
  ShortcutBinding(
    key: PhysicalKeyboardKey.bracketLeft,
    label: '[',
    what: 'Previous week',
    only: 'reports',
    intent: ShiftWeekIntent(-1),
  ),
  ShortcutBinding(
    key: PhysicalKeyboardKey.bracketRight,
    label: ']',
    what: 'Next week',
    only: 'reports',
    intent: ShiftWeekIntent(1),
  ),
  ShortcutBinding(
    key: PhysicalKeyboardKey.slash,
    label: '/',
    what: 'This list',
    intent: ShowShortcutsIntent(),
  ),
];

Map<ShortcutActivator, Intent> buildShortcutMap() => <ShortcutActivator, Intent>{
  for (final b in shortcutBindings) PhysicalActivator(b.key): b.intent,
};

/// Installs the bindings over the app shell.
///
/// Placed inside the home route rather than above the [Navigator] on purpose: a
/// dialog or bottom sheet is a sibling route, so while one is open its focus
/// sits outside this subtree and none of these fire. That is the wanted
/// behaviour — switching tabs behind an open sheet is never what was meant —
/// and it also means text fields inside dialogs need no special handling.
class AppShortcuts extends ConsumerStatefulWidget {
  const AppShortcuts({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppShortcuts> createState() => _AppShortcutsState();
}

class _AppShortcutsState extends ConsumerState<AppShortcuts> {
  final _node = FocusNode(debugLabel: 'app shortcuts');

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  /// Move tabs, taking focus back from whatever held it.
  ///
  /// The Now search field lives in an [IndexedStack], so it stays alive — and
  /// focused — after a tab change, and left that way it would keep swallowing
  /// keystrokes meant for the screen now on top. Focus moves *here* rather than
  /// being merely dropped: `unfocus()` hands focus to the enclosing route scope,
  /// which sits above this widget, and the shortcuts would go deaf.
  void _goToTab(int tab) {
    _node.requestFocus();
    ref.read(tabProvider.notifier).state = tab;
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: buildShortcutMap(),
      child: Actions(
        actions: <Type, Action<Intent>>{
          GoToTabIntent: CallbackAction<GoToTabIntent>(
            onInvoke: (intent) {
              _goToTab(intent.tab);
              return null;
            },
          ),
          FocusSearchIntent: CallbackAction<FocusSearchIntent>(
            onInvoke: (_) {
              ref.read(tabProvider.notifier).state = nowTab;
              // Focus has to wait for the tab change to be laid out. Until then
              // the field is an off-stage child of the IndexedStack, and an
              // off-stage node cannot take focus — asking now silently does
              // nothing, leaving the caret wherever it was.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                ref.read(quickSwitchFocusProvider).requestFocus();
              });
              return null;
            },
          ),
          StartUnnamedIntent: CallbackAction<StartUnnamedIntent>(
            onInvoke: (_) {
              ref.read(trackerControllerProvider).startUnsorted();
              return null;
            },
          ),
          ShiftWeekIntent: CallbackAction<ShiftWeekIntent>(
            onInvoke: (intent) {
              // Scoped to the report rather than bound there: the screen keeps no
              // focus of its own, so the binding has to ask which tab is showing.
              if (ref.read(tabProvider) != reportsTab) return null;
              shiftReportWeek(ref, intent.delta);
              return null;
            },
          ),
          ShowShortcutsIntent: CallbackAction<ShowShortcutsIntent>(
            onInvoke: (_) {
              showShortcutsHelp(context);
              return null;
            },
          ),
        },
        // Without a focused node inside this subtree the key events never arrive:
        // they travel up from whatever holds primary focus, and the route's own
        // scope sits beside this tree rather than under it.
        child: Focus(focusNode: _node, autofocus: true, child: widget.child),
      ),
    );
  }
}

/// The bindings, as a list you can read.
Future<void> showShortcutsHelp(BuildContext context) {
  final t = neo(context);
  final mod = modifierLabel();

  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: t.bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: t.line, width: 3),
      ),
      title: Text('Keyboard', style: mono(ctx, size: 16, weight: FontWeight.w800)),
      // An explicit width, not the content's intrinsic one: AlertDialog sizes
      // its child to what that child asks for, so a bare column would make the
      // dialog exactly as wide as its longest row.
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final b in shortcutBindings)
                _HelpRow(keys: '$mod + ${b.label}', what: b.what, only: b.only),
              // Not one of ours — Flutter dismisses a modal route on Escape by
              // itself. Listed because someone reading this list wants to know
              // what the keyboard does, not which layer implements it.
              const _HelpRow(keys: 'Esc', what: 'Close a dialog or sheet'),
              const SizedBox(height: 14),
              Text(
                'Keys are matched by position, so a non-US layout uses the same '
                'keys in the same places — whatever the keycaps say.',
                style: mono(ctx, size: 11, weight: FontWeight.w600, color: t.muted),
              ),
            ],
          ),
        ),
      ),
      actions: [NeoButton(label: 'close', onTap: () => Navigator.pop(ctx))],
    ),
  );
}

class _HelpRow extends StatelessWidget {
  const _HelpRow({required this.keys, required this.what, this.only});

  final String keys;
  final String what;
  final String? only;

  @override
  Widget build(BuildContext context) {
    final t = neo(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            // Sized for the longest chip, "Ctrl + Enter": a shrink-wrapped chip
            // would leave the descriptions on a ragged left edge.
            width: 96,
            child: Container(
              color: t.line,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(
                keys,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mono(context, size: 11, weight: FontWeight.w800, color: t.surface),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              only == null ? what : '$what · ${only!}',
              style: mono(context, size: 12, weight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
