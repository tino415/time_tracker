import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/providers.dart';
import '../../data/tracker_controller.dart';
import '../../domain/task_paste.dart';
import '../../format.dart';
import '../../theme/tokens.dart';
import 'activity_picker.dart';
import 'neo.dart';

/// Create or edit an activity. On create it can also switch to it immediately
/// (the paste-a-task flow on the Now screen). Returns the created/edited
/// activity, or null if dismissed.
Future<Activity?> showActivityEditor(
  BuildContext context,
  WidgetRef ref, {
  Activity? existing,
  String? initialName,
  String? presetParentId,
  bool switchToOnCreate = false,
}) {
  return showNeoSheet<Activity>(
    context,
    (_) => _EditorSheet(
      existing: existing,
      initialName: initialName,
      presetParentId: presetParentId,
      switchToOnCreate: switchToOnCreate,
    ),
  );
}

class _EditorSheet extends ConsumerStatefulWidget {
  const _EditorSheet({
    this.existing,
    this.initialName,
    this.presetParentId,
    this.switchToOnCreate = false,
  });

  final Activity? existing;
  final String? initialName;
  final String? presetParentId;
  final bool switchToOnCreate;

  @override
  ConsumerState<_EditorSheet> createState() => _EditorSheetState();
}

class _EditorSheetState extends ConsumerState<_EditorSheet> {
  late final TextEditingController _name;
  final _nameFocus = FocusNode();
  String? _parentId;
  String? _externalId;
  late Color _color;
  bool _bookmarked = false;
  bool _colorTouched = false;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? widget.initialName ?? '');
    _parentId = e?.parentId ?? widget.presetParentId;
    _externalId = e?.externalId;
    _bookmarked = e?.bookmarked ?? false;
    _color = e != null ? parseHexColor(e.color) : ActivityPalette.blue;
    _colorTouched = e != null;
    // Parse a pasted "CU-1234 …" initial name for the external id.
    if (e == null && (widget.initialName ?? '').isNotEmpty) {
      _externalId = parsePastedTask(widget.initialName!).externalId;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  /// Run [action], then put the keyboard back where it was.
  ///
  /// A web-only failure, and a silent one. Flutter routes typing through a
  /// hidden DOM input; a pointer down on a non-focusable area blurs that element
  /// in the *browser* while Flutter's focus tree still believes the field is
  /// focused. The two disagree, so the caret stays put and every keystroke goes
  /// nowhere — the field looks focused and the keyboard looks broken.
  ///
  /// Simply re-requesting focus does not help: the framework sees no change and
  /// does nothing. The connection has to be dropped and rebuilt, which is what
  /// the unfocus/requestFocus pair across a frame does. Guarded by [kIsWeb]
  /// because on a phone it would bounce the soft keyboard for no reason.
  ///
  /// Making the controls refuse focus is *not* sufficient on its own — measured,
  /// by neutering this method with `_Swatch`'s `ExcludeFocus` still in place:
  /// `just web-smoke` then reports the field holding "". What `ExcludeFocus`
  /// buys is that Flutter's focus tree stays put, so [wasTyping] below still has
  /// a truthful answer to restore from.
  void _keepTyping(VoidCallback action) {
    final wasTyping = _nameFocus.hasFocus;
    action();
    if (!wasTyping || !kIsWeb) return;
    _nameFocus.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _nameFocus.requestFocus();
    });
  }

  /// Colour used when the user hasn't explicitly chosen one: inherit the parent's.
  Color get _effectiveColor {
    if (_colorTouched) return _color;
    final parent = _parentId;
    if (parent != null) {
      final p = ref.read(activitiesByIdProvider)[parent];
      if (p != null) return parseHexColor(p.color);
    }
    return _color;
  }

  Future<void> _pickParent() async {
    final id = await showActivityPicker(
      context,
      ref,
      title: 'Parent activity',
      exclude: widget.existing != null ? {widget.existing!.syncId} : const {},
      excludeSubtrees: true,
    );
    if (id != null) setState(() => _parentId = id);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty || _saving) return;
    setState(() => _saving = true);

    final repo = ref.read(activityRepositoryProvider);
    final colorHex = toHexColor(_effectiveColor);
    Activity result;

    if (_isEdit) {
      final e = widget.existing!;
      if (name != e.name) await repo.renameActivity(e.syncId, name);
      if (colorHex != e.color.toUpperCase()) await repo.setColor(e.syncId, colorHex);
      if (_bookmarked != e.bookmarked) await repo.setBookmarked(e.syncId, _bookmarked);
      if (_parentId != e.parentId) await repo.setParent(e.syncId, _parentId);
      result = (await repo.loadActivities()).firstWhere(
        (a) => a.syncId == e.syncId,
        orElse: () => e,
      );
    } else {
      result = await repo.createActivity(
        name: name,
        color: colorHex,
        parentId: _parentId,
        bookmarked: _bookmarked,
        externalId: _externalId,
      );
      if (widget.switchToOnCreate) {
        await ref.read(trackerControllerProvider).switchTo(result.syncId);
      }
    }

    if (mounted) Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final t = neo(context);
    final byId = ref.watch(activitiesByIdProvider);
    final parentName = _parentId == null ? null : byId[_parentId]?.name;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        margin: const EdgeInsets.all(10),
        // The form is taller than a short screen once the keyboard is up, so it
        // scrolls rather than overflowing (the confirm button must stay reachable).
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        decoration: BoxDecoration(color: t.bg, border: Border.all(color: t.line, width: 3)),
        padding: const EdgeInsets.all(14),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  NeoChip(_isEdit ? 'Edit activity' : 'New activity'),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Text('✕', style: mono(context, size: 18, weight: FontWeight.w800)),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _Field(
                controller: _name,
                focusNode: _nameFocus,
                hint: 'name (paste CU-1234 Title…)',
                autofocus: !_isEdit,
              ),
              if (_externalId != null) ...[
                const SizedBox(height: 8),
                Row(children: [
                  Text('ID · ', style: mono(context, size: 12, color: t.muted)),
                  Text(_externalId!, style: mono(context, size: 12, weight: FontWeight.w700, color: t.brand)),
                ]),
              ],
              const SizedBox(height: 14),
              Text('COLOUR', style: mono(context, size: 11, weight: FontWeight.w800, spacing: 1, color: t.muted)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in ActivityPalette.all)
                    _Swatch(
                      color: c,
                      selected: _effectiveColor.toARGB32() == c.toARGB32(),
                      onTap: () => _keepTyping(() => setState(() {
                        _color = c;
                        _colorTouched = true;
                      })),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: NeoButton(
                      label: parentName == null ? 'parent: none' : 'parent: $parentName',
                      onTap: _pickParent,
                      shadowOffset: 3,
                    ),
                  ),
                  if (_parentId != null) ...[
                    const SizedBox(width: 8),
                    NeoButton(
                      label: 'clear',
                      onTap: () => _keepTyping(() => setState(() => _parentId = null)),
                      shadowOffset: 3,
                      compact: true,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              _BookmarkToggle(
                value: _bookmarked,
                onChanged: (v) => _keepTyping(() => setState(() => _bookmarked = v)),
              ),
              const SizedBox(height: 16),
              NeoButton(
                label: _isEdit
                    ? 'save'
                    : widget.switchToOnCreate
                        ? 'create & switch'
                        : 'create',
                primary: true,
                onTap: _saving ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    this.focusNode,
    this.autofocus = false,
  });
  final TextEditingController controller;
  final String hint;

  /// Supplied when the caller needs to put the keyboard back after a tap
  /// elsewhere in the form — see `_EditorSheetState._keepTyping`.
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final t = neo(context);
    return Container(
      decoration: BoxDecoration(color: t.surface, border: Border.all(color: t.line, width: 3)),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        style: mono(context, weight: FontWeight.w700),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: hint,
          hintStyle: mono(context, color: t.muted),
        ),
      ),
    );
  }
}

/// One colour in the palette.
///
/// A real, named control rather than a bare `GestureDetector` around a coloured
/// box: it carries a semantics label (so it is announced, and reachable from a
/// browser-driven test — the only harness that sees the web focus bug this
/// widget exists to keep fixed), and it refuses focus, so tapping one cannot
/// take the caret out of the name field.
class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.selected, required this.onTap});

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = neo(context);
    return Semantics(
      button: true,
      selected: selected,
      label: 'colour ${toHexColor(color)}',
      child: ExcludeFocus(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color,
              border: Border.all(
                color: selected ? t.brand : t.line,
                width: selected ? 4 : 2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BookmarkToggle extends StatelessWidget {
  const _BookmarkToggle({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = neo(context);
    return NeoPressable(
      onTap: () => onChanged(!value),
      shadowOffset: 3,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          Text(value ? '★' : '☆',
              style: mono(context, size: 18, weight: FontWeight.w800, color: value ? t.brand : t.muted)),
          const SizedBox(width: 10),
          // Flexible: the label is wider than a narrow phone's sheet.
          Expanded(
            child: Text(
              'bookmark (quick-switch + watch)',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono(context, weight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
