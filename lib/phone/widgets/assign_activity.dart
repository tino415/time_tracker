import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/providers.dart';
import '../../data/tracker_controller.dart';
import '../../domain/block.dart';
import '../../domain/unsorted.dart';
import '../../format.dart';
import '../screens/now_screen.dart' show DottedField;
import 'activity_editor.dart';
import 'neo.dart';

/// Re-point a block at a real activity, keeping its original start — answering
/// an unnamed one, or correcting a named one.
///
/// Recency-ordered rather than alphabetical: naming an unnamed block almost
/// always means naming something tracked recently, and the whole feature exists
/// to save seconds. Typing filters; the create row makes a new activity and
/// assigns it in one step.
Future<void> assignBlockActivity(BuildContext context, WidgetRef ref, Block block) async {
  final id = await pickOrCreateActivity(
    context,
    ref,
    // A named block reaching this sheet is being corrected, not answered, and
    // "What was this?" would be asking about something already on screen.
    title: isUnsortedSet(block.activities) ? 'What was this?' : 'Change to',
    trailing:
        '${formatTimeOfDay(block.start)} · '
        '${formatSpan(block.duration(DateTime.now()))}',
  );
  if (id == null) return;
  await ref.read(trackerControllerProvider).assignBlock(block.change.syncId, id);
}

/// Pick an activity, or make one on the spot. Returns the id, or null if
/// dismissed.
///
/// Was private to "what was this?", and generalised because tagging needs the
/// same thing. The plain picker cannot create, so every tag used to mean backing
/// out to the activity list, making the row, and starting again — which is
/// exactly the moment you least want to leave what you were doing.
///
/// [exclude] drops activities already on the block: offering to tag something
/// twice is offering a no-op.
Future<String?> pickOrCreateActivity(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  String? trailing,
  Set<String> exclude = const {},
}) {
  return showNeoSheet<String>(
    context,
    (_) => _AssignSheet(title: title, trailing: trailing, exclude: exclude),
  );
}

class _AssignSheet extends ConsumerStatefulWidget {
  const _AssignSheet({required this.title, this.trailing, this.exclude = const {}});

  final String title;
  final String? trailing;
  final Set<String> exclude;

  @override
  ConsumerState<_AssignSheet> createState() => _AssignSheetState();
}

class _AssignSheetState extends ConsumerState<_AssignSheet> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<Activity> _suggestions(List<Activity> all) {
    final q = _query.trim().toLowerCase();
    final matches =
        all.where((a) {
          // The catch-all is not something you can answer *with*.
          if (isUnsorted(a)) return false;
          // Already on the block — tagging it again would do nothing.
          if (widget.exclude.contains(a.syncId)) return false;
          if (q.isEmpty) return true;
          return a.name.toLowerCase().contains(q) ||
              (a.externalId?.toLowerCase().contains(q) ?? false);
        }).toList()..sort((a, b) {
          final la = a.lastUsedAt, lb = b.lastUsedAt;
          if (la != null && lb != null) return lb.compareTo(la);
          if (la != null) return -1;
          if (lb != null) return 1;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
    return matches.take(6).toList();
  }

  void _assign(String activityId) => Navigator.pop(context, activityId);

  Future<void> _createAndAssign() async {
    final name = _controller.text.trim();
    final created = await showActivityEditor(context, ref, initialName: name.isEmpty ? null : name);
    if (created == null) return;
    if (mounted) _assign(created.syncId);
  }

  @override
  Widget build(BuildContext context) {
    final t = neo(context);
    final all = ref.watch(activitiesStreamProvider).valueOrNull ?? const [];
    final suggestions = _suggestions(all);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        margin: const EdgeInsets.all(10),
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        decoration: BoxDecoration(
          color: t.bg,
          border: Border.all(color: t.line, width: 3),
        ),
        padding: const EdgeInsets.all(14),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  NeoChip(widget.title),
                  const SizedBox(width: 12),
                  if (widget.trailing != null)
                    Expanded(
                      child: Text(
                        widget.trailing!,
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: mono(context, size: 11, weight: FontWeight.w700, color: t.muted),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              DottedField(
                controller: _controller,
                hint: 'search or name it…',
                onChanged: (v) => setState(() => _query = v),
                onSubmitted: (_) {
                  if (suggestions.isNotEmpty) {
                    _assign(suggestions.first.syncId);
                  } else {
                    _createAndAssign();
                  }
                },
              ),
              const SizedBox(height: 12),
              for (final a in suggestions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: NeoPressable(
                    onTap: () => _assign(a.syncId),
                    shadowOffset: 3,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    child: Row(
                      children: [
                        NeoSwatch(parseHexColor(a.color), size: 14),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            a.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: mono(context, weight: FontWeight.w700),
                          ),
                        ),
                        if (a.externalId != null)
                          Text(a.externalId!, style: mono(context, size: 11, color: t.muted)),
                      ],
                    ),
                  ),
                ),
              NeoButton(
                label: _query.trim().isEmpty ? '+ new activity' : '+ create "${_query.trim()}"',
                primary: true,
                shadowOffset: 3,
                onTap: _createAndAssign,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
