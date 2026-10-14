import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/manual_sync.dart';
import '../data/providers.dart';
import '../data/sync_service.dart';
import '../data/tracker_controller.dart';
import 'phone_app.dart';
import 'screens/calendar_screen.dart';
import 'screens/now_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/timeline_screen.dart';
import 'widgets/assign_activity.dart';
import 'widgets/block_comment.dart';
import 'widgets/command_picker.dart';
import 'widgets/neo.dart';
import 'widgets/sync_setup.dart';

/// Keyboard shortcuts for the desktop PWA — bare keys, vim-style.
///
/// The first attempt used modifiers and did not work. Browsers reserve
/// *modifier* combinations and almost no bare letters, so every collision came
/// from reaching for one: Cmd+1‥4 is the tab strip in Chrome and Safari alike —
/// in an installed window too, not only a tab — Cmd+[ and Cmd+] are
/// Back/Forward, as are Cmd+arrows, and Cmd+/ is Safari's status bar. Bare keys
/// collide with none of it, anywhere.
///
/// The price is the guard the modifiers were bought to avoid: nothing may fire
/// while a text field has focus, or `s` could not be typed into a note. See
/// [_isTyping] — it is the load-bearing part of this file, and the one thing
/// whose failure would make the app feel broken rather than merely inert.
///
/// `g` then a letter for the tabs, rather than four more single keys: the prefix
/// is self-limiting, and it leaves the single-key space for actions instead of
/// spending it on navigation. `e` is the same device turned on corrections to
/// the running block: `a` and `n` on their own would be verbs that rewrite what
/// is already recorded on a stray press, which is the case a prefix exists for.
///
/// Deliberately absent: calendar zoom. The calendar is a direct-manipulation
/// surface — boundaries are dragged, splits are long-pressed — so zoom belongs
/// to the trackpad rather than to a key.

/// How long a pending prefix waits for its second key.
///
/// Long enough not to lose a deliberate two-key press, short enough that a
/// prefix pressed by accident cannot swallow something typed a moment later. The
/// pending state is shown on screen too, so it is never armed invisibly.
const _prefixTimeout = Duration(milliseconds: 1500);

/// A key that opens a two-key sequence.
class ShortcutPrefix {
  const ShortcutPrefix({required this.key, required this.label});
  final PhysicalKeyboardKey key;
  final String label;
}

const goPrefix = ShortcutPrefix(key: PhysicalKeyboardKey.keyG, label: 'g');
const editPrefix = ShortcutPrefix(key: PhysicalKeyboardKey.keyE, label: 'e');
const shortcutPrefixes = [goPrefix, editPrefix];

enum ShortcutAction {
  goNow,
  goTimeline,
  goReports,
  goActivities,
  startUnnamed,
  focusSearch,
  syncNow,
  syncSetup,
  toggleTheme,
  exportCsv,
  showCommands,
  showHelp,
  prevPeriod,
  nextPeriod,
  editActivity,
  editNote,
}

/// One binding, carrying everything the help overlay needs — so adding a
/// shortcut cannot leave the list documenting them out of date.
class ShortcutBinding {
  const ShortcutBinding({
    required this.key,
    required this.label,
    required this.what,
    required this.action,
    this.prefix,
    this.shift = false,
    this.primaryModifier = false,
    this.only,
    this.available,
  });

  /// Matched on position, not on the character produced. A logical binding is
  /// not merely relabelled on another layout but unreachable — on a Slovak
  /// layout the key left of `2` types `+` — so every layout would need its own
  /// table. This way the binding is the same finger movement everywhere and only
  /// the legend on the keycap differs.
  final PhysicalKeyboardKey key;

  /// The prefix this key follows, or null for a key that stands alone.
  final ShortcutPrefix? prefix;

  /// Requires Shift. Significant because `s` and `S` differ. It was deliberately
  /// ignored under the earlier digit scheme, where shifting is how some layouts
  /// produce a digit at all; letters have no such problem, so that reason is
  /// gone with the digits.
  final bool shift;

  /// Requires the platform's own modifier — Cmd on a Mac, Ctrl everywhere else.
  ///
  /// The exception to this file's bare-keys rule, and it earns the exception by
  /// being the one binding people arrive already knowing. See [_onKey] for why
  /// holding one otherwise means the keystroke is somebody else's.
  final bool primaryModifier;

  /// The legend on a US keyboard. Shown, never matched.
  final String label;

  final String what;

  /// The screen this applies on, or null for anywhere.
  final String? only;

  /// Whether this build can do it at all, or null for a key that always can.
  ///
  /// [only] scopes by screen; this scopes by configuration, which the table
  /// cannot say for itself — sync is absent from a build with no server, not
  /// merely inapplicable somewhere. Consulted by the help list too, so a key
  /// this device does not have is never advertised.
  final bool Function(WidgetRef ref)? available;

  final ShortcutAction action;
}

/// A tear-off rather than a closure in the row below: the table is const, and a
/// function literal cannot appear in a constant expression.
bool _syncConfigured(WidgetRef ref) => ref.read(syncServiceProvider) != null;

/// Weaker than [_syncConfigured] on purpose: setting up the account is exactly
/// what you reach for when there is a server and no account yet.
bool _syncOffered(WidgetRef ref) => ref.read(syncConfigProvider).hasServer;

const shortcutBindings = <ShortcutBinding>[
  ShortcutBinding(
    key: PhysicalKeyboardKey.keyN,
    prefix: goPrefix,
    label: 'g n',
    what: 'Now',
    action: ShortcutAction.goNow,
  ),
  ShortcutBinding(
    key: PhysicalKeyboardKey.keyT,
    prefix: goPrefix,
    label: 'g t',
    what: 'Timeline',
    action: ShortcutAction.goTimeline,
  ),
  ShortcutBinding(
    key: PhysicalKeyboardKey.keyR,
    prefix: goPrefix,
    label: 'g r',
    what: 'Reports',
    action: ShortcutAction.goReports,
  ),
  ShortcutBinding(
    key: PhysicalKeyboardKey.keyA,
    prefix: goPrefix,
    label: 'g a',
    what: 'Activities',
    action: ShortcutAction.goActivities,
  ),
  ShortcutBinding(
    key: PhysicalKeyboardKey.keyA,
    prefix: editPrefix,
    label: 'e a',
    what: 'Change what the running block tracks',
    action: ShortcutAction.editActivity,
  ),
  ShortcutBinding(
    key: PhysicalKeyboardKey.keyN,
    prefix: editPrefix,
    label: 'e n',
    what: 'Note on the running block',
    action: ShortcutAction.editNote,
  ),
  ShortcutBinding(
    key: PhysicalKeyboardKey.keyS,
    label: 's',
    what: 'Start a block, name it later',
    action: ShortcutAction.startUnnamed,
  ),
  ShortcutBinding(
    key: PhysicalKeyboardKey.keyS,
    shift: true,
    label: 'S',
    what: 'Search, or paste a task id',
    action: ShortcutAction.focusSearch,
  ),
  // The same physical key as `g r`, and they cannot collide: the match below
  // requires a binding's prefix to be the one that is armed, so bare and
  // prefixed rows are disjoint sets rather than competing entries.
  ShortcutBinding(
    key: PhysicalKeyboardKey.keyR,
    label: 'r',
    what: 'Sync now',
    action: ShortcutAction.syncNow,
    available: _syncConfigured,
  ),
  // h and l rather than brackets: previous/next is a *direction*, and it then
  // means one thing on both screens — one unit back or forward along the time
  // axis, whether the unit is a month, a week or a day.
  //
  // j and k are left free on purpose. The calendar's visible axis is vertical,
  // which argues for them there, but a day is a sequence you page through rather
  // than a direction you scroll — and anyone reaching for j/k means scrolling.
  ShortcutBinding(
    key: PhysicalKeyboardKey.keyH,
    label: 'h',
    what: 'Previous period',
    only: 'reports',
    action: ShortcutAction.prevPeriod,
  ),
  ShortcutBinding(
    key: PhysicalKeyboardKey.keyL,
    label: 'l',
    what: 'Next period',
    only: 'reports',
    action: ShortcutAction.nextPeriod,
  ),
  ShortcutBinding(
    key: PhysicalKeyboardKey.keyH,
    label: 'h',
    what: 'Previous day',
    only: 'calendar',
    action: ShortcutAction.prevPeriod,
  ),
  ShortcutBinding(
    key: PhysicalKeyboardKey.keyL,
    label: 'l',
    what: 'Next day',
    only: 'calendar',
    action: ShortcutAction.nextPeriod,
  ),
  // The one binding with a modifier, and the one nobody has to be taught. Every
  // app with a command palette uses it, so it is the first thing a keyboard user
  // tries — which is worth more here than the consistency of the bare-key rule.
  //
  // A browser tab is not the obstacle it looks like. Cmd+K is the omnibox, but
  // the engine calls preventDefault() on any key the framework reports handled,
  // so the page wins it the same way GitHub and every other palette does.
  ShortcutBinding(
    key: PhysicalKeyboardKey.keyK,
    primaryModifier: true,
    label: '⌘K',
    what: 'Everything, by name',
    action: ShortcutAction.showCommands,
  ),
  ShortcutBinding(
    key: PhysicalKeyboardKey.slash,
    shift: true,
    label: '?',
    what: 'This list',
    action: ShortcutAction.showHelp,
  ),
];

/// What the picker can reach: every action with a name, whether or not a key is
/// spent on it.
///
/// The point of the picker is to scale past the keymap — the single-key space is
/// small and spending one is permanent — so this table is the longer list, and
/// [shortcutBindings] is the subset that also earned a key. Theme, sync setup and
/// the CSV export appear only here, because until now they had buttons and
/// nothing else.
class ShortcutCommand {
  const ShortcutCommand({
    required this.action,
    required this.label,
    this.keywords = '',
    this.available,
  });

  final ShortcutAction action;

  /// How the row reads. Sentence case, a verb first — it is an instruction being
  /// picked, not a heading.
  final String label;

  /// Words it should also match, for the ones whose label is not what someone
  /// would type looking for them.
  final String keywords;

  /// Whether this build can do it. Same contract as [ShortcutBinding.available],
  /// and the same reason: sync is absent without a server, not merely inert.
  final bool Function(WidgetRef ref)? available;

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return label.toLowerCase().contains(q) || keywords.toLowerCase().contains(q);
  }
}

const shortcutCommands = <ShortcutCommand>[
  ShortcutCommand(action: ShortcutAction.goNow, label: 'Go to Now', keywords: 'tab switch'),
  ShortcutCommand(
    action: ShortcutAction.goTimeline,
    label: 'Go to Timeline',
    keywords: 'tab calendar day',
  ),
  ShortcutCommand(
    action: ShortcutAction.goReports,
    label: 'Go to Reports',
    keywords: 'tab week totals',
  ),
  ShortcutCommand(
    action: ShortcutAction.goActivities,
    label: 'Go to Activities',
    keywords: 'tab catalogue list',
  ),
  ShortcutCommand(
    action: ShortcutAction.startUnnamed,
    label: 'Start a block, name it later',
    keywords: 'new now unsorted',
  ),
  ShortcutCommand(
    action: ShortcutAction.focusSearch,
    label: 'Search, or paste a task id',
    keywords: 'find external',
  ),
  ShortcutCommand(
    action: ShortcutAction.editActivity,
    label: 'Change what the running block tracks',
    keywords: 'assign repoint correct',
  ),
  ShortcutCommand(
    action: ShortcutAction.editNote,
    label: 'Note on the running block',
    keywords: 'comment annotate',
  ),
  ShortcutCommand(
    action: ShortcutAction.syncNow,
    label: 'Sync now',
    keywords: 'push pull backend',
    available: _syncConfigured,
  ),
  ShortcutCommand(
    action: ShortcutAction.syncSetup,
    label: 'Sync account',
    keywords: 'token qr join disconnect settings',
    available: _syncOffered,
  ),
  ShortcutCommand(
    action: ShortcutAction.toggleTheme,
    label: 'Switch light and dark',
    keywords: 'theme appearance settings',
  ),
  ShortcutCommand(
    action: ShortcutAction.exportCsv,
    label: 'Export CSV · all history',
    keywords: 'download save spreadsheet',
  ),
  ShortcutCommand(action: ShortcutAction.showHelp, label: 'Keyboard shortcuts', keywords: 'keys ?'),
];

// `/` on its own is deliberately unbound. It means "search" nearly everywhere,
// and there is no search here yet — binding it to something that is not one
// would teach the wrong thing and then have to be taken back. `?` is Shift on
// the same physical key, so holding `/` back costs nothing.

/// True when a text field has focus and the keyboard belongs to it.
///
/// Without this, bare keys are unusable: typing "s" into a note would start a
/// block. Structural rather than a flag maintained per field — there are ten
/// fields across eight files, and a check they each have to remember is one a
/// new field will forget.
/// Whether the platform's own command modifier is down — Cmd on Apple, Ctrl
/// elsewhere.
///
/// The distinction is the platform's, not the keyboard's: a Mac user reaches for
/// Cmd and everyone else for Ctrl, and binding both everywhere would swallow
/// Ctrl+K on a Mac, where it is "delete to end of line" in every text field.
bool _isPrimaryModifierHeld() {
  final keyboard = HardwareKeyboard.instance;
  final apple =
      defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.iOS;
  if (apple) return keyboard.isMetaPressed && !keyboard.isControlPressed;
  return keyboard.isControlPressed && !keyboard.isMetaPressed;
}

bool _isTyping() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  return context.findAncestorWidgetOfExactType<EditableText>() != null;
}

/// Installs the bindings over the app shell.
///
/// Inside the home route rather than above the [Navigator]: a dialog or bottom
/// sheet is a sibling route, so while one is open its focus sits outside this
/// subtree and none of these fire. That is wanted — the keyboard should not move
/// tabs behind an open sheet — and it means fields inside dialogs are covered
/// twice over.
class AppShortcuts extends ConsumerStatefulWidget {
  const AppShortcuts({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppShortcuts> createState() => _AppShortcutsState();
}

class _AppShortcutsState extends ConsumerState<AppShortcuts> {
  final _node = FocusNode(debugLabel: 'app shortcuts');

  /// Set while a prefix waits for its second key.
  ShortcutPrefix? _pending;
  Timer? _pendingTimer;

  @override
  void dispose() {
    _pendingTimer?.cancel();
    _node.dispose();
    super.dispose();
  }

  void _arm(ShortcutPrefix prefix) {
    _pendingTimer?.cancel();
    setState(() => _pending = prefix);
    _pendingTimer = Timer(_prefixTimeout, _disarm);
  }

  void _disarm() {
    _pendingTimer?.cancel();
    _pendingTimer = null;
    if (_pending != null && mounted) setState(() => _pending = null);
  }

  /// Which screen a scoped binding is judged against.
  String? _screen() {
    switch (ref.read(tabProvider)) {
      case reportsTab:
        return 'reports';
      case timelineTab:
        // The timeline tab is two views behind a toggle, and only one of them
        // has days to step.
        return ref.read(timelineViewProvider) ? 'calendar' : 'timeline';
      default:
        return null;
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    // Cancelling an armed prefix comes first, and does nothing else.
    //
    // Without it the only way out of an armed prefix is to wait for the timeout
    // or to spend a real binding — so a prefix pressed by accident leaves the
    // next keystroke meaning something you did not ask for. Escape is the
    // obvious key; Ctrl+G is emacs's own cancel, which is the one anybody
    // reaching for a key-sequence already has in their fingers.
    //
    // Ahead of both the field guard and the held-modifier check, because those
    // would otherwise swallow it: Escape is claimed below for leaving a field,
    // and Ctrl+G is rejected as somebody else's shortcut.
    if (_pending != null &&
        (event.physicalKey == PhysicalKeyboardKey.escape ||
            (event.physicalKey == PhysicalKeyboardKey.keyG &&
                HardwareKeyboard.instance.isControlPressed))) {
      _disarm();
      return KeyEventResult.handled;
    }

    // The command picker, ahead of both guards below.
    //
    // Ahead of the field guard because the picker is most useful from inside a
    // field — you are already typing, and this is where you go when what you
    // want is not what the field does. Ahead of the modifier bail because it is
    // the one binding that holds one.
    //
    // Matched here rather than in the table's loop: everything down there
    // assumes no modifier is held, and threading a second mode through it would
    // cost more than the one row it serves.
    if (_isPrimaryModifierHeld() && !HardwareKeyboard.instance.isShiftPressed) {
      for (final b in shortcutBindings) {
        if (!b.primaryModifier || b.key != event.physicalKey) continue;
        if (b.available?.call(ref) == false) continue;
        _disarm();
        _run(b.action);
        return KeyEventResult.handled;
      }
    }

    // Escape leaves the field, and is the one key the guard does not silence.
    //
    // Without a way out by keyboard the guard is a trap: focus the search field
    // and every binding switches off, including the ones that would take you
    // elsewhere, so the only exit is the mouse. Flutter does not blur a
    // TextField on Escape by itself — inside a dialog the route consumes it
    // first, which is why this only ever sees the case with no route to close.
    if (event.physicalKey == PhysicalKeyboardKey.escape) {
      if (!_isTyping()) return KeyEventResult.ignored;
      _node.requestFocus();
      return KeyEventResult.handled;
    }

    // The field wins otherwise. Every binding here is a character someone might
    // legitimately be typing.
    if (_isTyping()) return KeyEventResult.ignored;

    final keyboard = HardwareKeyboard.instance;
    // Bare keys only. A modifier held means this is someone else's shortcut —
    // the browser's, or the platform's — and swallowing it would be worse than
    // ignoring it.
    if (keyboard.isControlPressed || keyboard.isMetaPressed || keyboard.isAltPressed) {
      return KeyEventResult.ignored;
    }
    final shift = keyboard.isShiftPressed;

    final wasPending = _pending;
    if (wasPending != null) _disarm();

    final screen = _screen();
    for (final b in shortcutBindings) {
      if (b.prefix?.key != wasPending?.key) continue;
      if (b.key != event.physicalKey || b.shift != shift) continue;
      if (b.only != null && b.only != screen) continue;
      if (b.available?.call(ref) == false) continue;
      _run(b.action);
      return KeyEventResult.handled;
    }

    // A prefix key arms — but not while already armed, so "g g" falls through
    // rather than re-arming forever.
    if (wasPending == null && !shift) {
      for (final p in shortcutPrefixes) {
        if (p.key != event.physicalKey) continue;
        _arm(p);
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  /// Move tabs, taking focus back from whatever held it.
  ///
  /// The Now search field lives in an [IndexedStack], so it stays alive — and
  /// focused — after a tab change. Left that way [_isTyping] would keep every
  /// binding switched off on a screen with no field in sight. Focus moves *here*
  /// rather than being dropped: `unfocus()` hands it to the enclosing route
  /// scope, which sits above this widget, and the shortcuts would go deaf.
  void _goToTab(int tab) {
    _node.requestFocus();
    ref.read(tabProvider.notifier).state = tab;
  }

  void _run(ShortcutAction action) {
    switch (action) {
      case ShortcutAction.goNow:
        _goToTab(nowTab);
      case ShortcutAction.goTimeline:
        _goToTab(timelineTab);
      case ShortcutAction.goReports:
        _goToTab(reportsTab);
      case ShortcutAction.goActivities:
        _goToTab(activitiesTab);

      case ShortcutAction.startUnnamed:
        ref.read(trackerControllerProvider).startUnsorted();

      case ShortcutAction.focusSearch:
        ref.read(tabProvider.notifier).state = nowTab;
        // Focus waits for the tab change to be laid out: until then the field is
        // an off-stage child of the IndexedStack, and an off-stage node cannot
        // take focus — asking now silently does nothing.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(quickSwitchFocusProvider).requestFocus();
        });

      case ShortcutAction.syncNow:
        ref.read(manualSyncProvider.notifier).run();

      case ShortcutAction.syncSetup:
        showSyncSetup(context, ref);

      case ShortcutAction.toggleTheme:
        {
          final current = Theme.of(context).brightness;
          ref.read(themeModeProvider.notifier).state = current == Brightness.dark
              ? ThemeMode.light
              : ThemeMode.dark;
        }

      case ShortcutAction.exportCsv:
        exportCsv(context, ref);

      case ShortcutAction.showCommands:
        _openCommands();

      case ShortcutAction.showHelp:
        showShortcutsHelp(context, ref);

      // Both edit the block the clock is running against, so both are silent on
      // an empty timeline rather than opening a sheet over nothing.
      case ShortcutAction.editActivity:
        {
          final block = ref.read(currentBlockProvider);
          if (block == null) return;
          assignBlockActivity(context, ref, block);
        }
      case ShortcutAction.editNote:
        {
          final block = ref.read(currentBlockProvider);
          if (block == null) return;
          editBlockComment(context, ref, block);
        }

      // One action for both screens: the binding table says which unit, and the
      // scope decides which of the two entries matched.
      case ShortcutAction.prevPeriod:
        _shiftPeriod(-1);
      case ShortcutAction.nextPeriod:
        _shiftPeriod(1);
    }
  }

  /// Open the picker, and run whatever it comes back with.
  ///
  /// The action is run here rather than inside the picker so it goes through
  /// [_run] like every other one — which is what keeps the tab moves' focus
  /// handling, and means a command cannot behave differently depending on which
  /// door it was opened by.
  Future<void> _openCommands() async {
    final action = await showCommandPicker(context, ref);
    if (!mounted) return;
    // The picker was a modal route, so focus left this subtree while it was up
    // and the bare keys are deaf until it comes back. See [_goToTab].
    _node.requestFocus();
    if (action != null) _run(action);
  }

  void _shiftPeriod(int delta) {
    switch (_screen()) {
      case 'reports':
        shiftReportPeriod(ref, delta);
      case 'calendar':
        shiftCalendarDay(ref, delta);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = neo(context);
    return Focus(
      focusNode: _node,
      // Without a focused node inside this subtree the key events never arrive:
      // they travel up from whatever holds primary focus, and the route's own
      // scope sits beside this tree rather than under it.
      autofocus: true,
      // It holds the keyboard, not a control. Tab stopping on it would spend a
      // press on nothing the eye can find.
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: Stack(
        children: [
          widget.child,
          // A pending prefix is a mode, and an invisible mode is a trap. Shown
          // rather than merely timed out, so it is never a mystery why the next
          // key did something unexpected.
          if (_pending != null)
            Positioned(
              left: 16,
              bottom: 16,
              child: IgnorePointer(
                child: Container(
                  color: t.line,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  child: Text(
                    '${_pending!.label} …',
                    style: mono(context, size: 12, weight: FontWeight.w800, color: t.surface),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The bindings, as a list you can read — the ones this build actually has.
Future<void> showShortcutsHelp(BuildContext context, WidgetRef ref) {
  final t = neo(context);
  // Resolved here rather than inside the builder, which reruns on every rebuild
  // of the dialog route: _AppControls sits in the header or in the sidebar
  // depending on the breakpoint, so a resize across it disposes the consumer this
  // ref belongs to while the dialog is still open.
  final listed = shortcutBindings.where((b) => b.available?.call(ref) != false).toList();

  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: t.bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: t.line, width: 3),
      ),
      title: Text('Keyboard', style: mono(ctx, size: 16, weight: FontWeight.w800)),
      // An explicit width, not the content's intrinsic one: AlertDialog sizes its
      // child to what that child asks for, so a bare column would make the dialog
      // exactly as wide as its longest row.
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final b in listed) _HelpRow(keys: b.label, what: b.what, only: b.only),
              // Not one of ours — Flutter dismisses a modal route on Escape by
              // itself. Listed because someone reading this wants to know what
              // the keyboard does, not which layer implements it.
              const _HelpRow(keys: 'Esc', what: 'Close a sheet, or leave the field'),
              // Written as a sequence, like the rows above it: "g Esc" is press
              // g, then Escape. "Esc ^g" read as a chord and said nothing about
              // when it applies — the cancel only exists while a prefix is
              // waiting. The prefixes are listed from the table so a new one
              // cannot leave this row naming only some of them.
              _HelpRow(
                keys: '${shortcutPrefixes.map((p) => p.label).join('/')} Esc',
                what: 'Cancel a pending prefix — Ctrl+G also',
              ),
              const SizedBox(height: 14),
              Text(
                'Keys are matched by position, so a non-US layout uses the same '
                'keys in the same places — whatever the keycaps say. Nothing '
                'fires while you are typing in a field.',
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
            // Sized for the longest chip, "g/e Esc".
            width: 62,
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
              only == null ? what : '$what · $only',
              style: mono(context, size: 12, weight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
