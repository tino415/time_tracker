import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart' show Activity;
import '../../data/providers.dart';
import '../../format.dart';
import '../screens/now_screen.dart';
import '../shortcuts.dart';
import 'neo.dart';
import 'switch_undo.dart';

/// Everything the app does, by name.
///
/// The keymap does not scale: the single-key space is small, and a key spent is
/// spent for good — so anything that will never earn one had a button or nothing
/// at all. Typing a word costs a moment and has no such ceiling.
///
/// Two kinds of row, deliberately in one list. Commands are what the app can do;
/// activities are what it can be pointed at, and "start deep work" is the thing
/// people most often want. Keeping them apart would mean knowing which list you
/// wanted before you started typing, which is the knowledge the picker exists to
/// remove.
///
/// Returns the chosen command for the caller to run, or null. An activity is
/// started here, because that is one call and needs nothing from the shell — a
/// command may need the shell's focus handling, which is why it goes back.
Future<ShortcutAction?> showCommandPicker(BuildContext context, WidgetRef ref) {
  return showDialog<ShortcutAction>(context: context, builder: (_) => const _CommandPicker());
}

class _CommandPicker extends ConsumerStatefulWidget {
  const _CommandPicker();

  @override
  ConsumerState<_CommandPicker> createState() => _CommandPickerState();
}

class _CommandPickerState extends ConsumerState<_CommandPicker> {
  final _query = TextEditingController();
  final _field = FocusNode();

  /// Which row Enter would take. An index rather than an identity, because the
  /// list is rebuilt on every keystroke and the row under the cursor is a
  /// position in what is showing now.
  int _cursor = 0;

  @override
  void dispose() {
    _query.dispose();
    _field.dispose();
    super.dispose();
  }

  List<ShortcutCommand> get _commands => [
    for (final c in shortcutCommands)
      if (c.available?.call(ref) != false && c.matches(_query.text)) c,
  ];

  /// Empty until something is typed: the whole catalogue listed under every
  /// command would bury them, and "which activity" is a question you answer by
  /// naming it. [matchingActivities] already returns nothing for a blank query,
  /// and orders by recency — the one you just left is the one you are most
  /// likely coming back to.
  List<Activity> get _activities =>
      matchingActivities(ref.watch(activitiesStreamProvider).valueOrNull ?? const [], _query.text);

  int get _rowCount => _commands.length + _activities.length;

  void _move(int delta) {
    if (_rowCount == 0) return;
    setState(() => _cursor = (_cursor + delta) % _rowCount);
  }

  void _pick(int index) {
    final commands = _commands;
    if (index < commands.length) {
      Navigator.pop(context, commands[index].action);
      return;
    }
    final activity = _activities[index - commands.length];
    // Popped first: the undo bar the switch raises belongs to the screen behind
    // this route, not to a dialog on its way out.
    Navigator.pop(context);
    switchWithUndo(context, ref, activity.syncId);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        _move(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _move(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        if (_cursor < _rowCount) _pick(_cursor);
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final t = neo(context);
    final commands = _commands;
    final activities = _activities;

    return AlertDialog(
      backgroundColor: t.bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: t.line, width: 3),
      ),
      contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      // An explicit width, not the content's intrinsic one: AlertDialog sizes to
      // what its child asks for, so a bare column would be as wide as its
      // longest row and jump about as the list filters.
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The arrow keys belong to the list, but focus belongs to the field
            // — you type without aiming first. Handled above the field so the
            // caret does not eat Up and Down moving within one line of text.
            Focus(
              onKeyEvent: _onKey,
              child: DottedField(
                controller: _query,
                focusNode: _field,
                hint: 'what do you want to do?',
                // The cursor goes home on every edit: it points at a position in
                // a list that has just been rebuilt, so keeping it would leave it
                // on whatever happens to be there now.
                onChanged: (_) => setState(() => _cursor = 0),
                onSubmitted: (_) {
                  if (_cursor < _rowCount) _pick(_cursor);
                },
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < commands.length; i++)
                      _Row(label: commands[i].label, selected: i == _cursor, onTap: () => _pick(i)),
                    for (var i = 0; i < activities.length; i++)
                      _Row(
                        label: activities[i].name,
                        colour: parseHexColor(activities[i].color),
                        trailing: 'start',
                        selected: commands.length + i == _cursor,
                        onTap: () => _pick(commands.length + i),
                      ),
                    if (_rowCount == 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'nothing matches',
                          style: mono(context, size: 12, weight: FontWeight.w700, color: t.muted),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [NeoButton(label: 'close', onTap: () => Navigator.pop(context))],
    );
  }
}

/// One row. Flat rather than a [NeoPressable]: a list this long of hard-shadowed
/// cards reads as a wall, and the selected row is already marked by the inverse
/// fill the rest of the app uses for "this one".
class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.selected,
    required this.onTap,
    this.colour,
    this.trailing,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? colour;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final t = neo(context);
    final ink = selected ? t.surface : t.ink;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: selected ? t.line : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        child: Row(
          children: [
            if (colour != null) ...[NeoSwatch(colour!, size: 10), const SizedBox(width: 8)],
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mono(context, size: 12, weight: FontWeight.w700, color: ink),
              ),
            ),
            if (trailing != null)
              Text(
                trailing!,
                style: mono(
                  context,
                  size: 9,
                  weight: FontWeight.w800,
                  color: selected ? t.surface : t.muted,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
