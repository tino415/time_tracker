import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/providers.dart';
import '../../domain/activity_tree.dart';
import '../../format.dart';
import '../../theme/tokens.dart';
import '../widgets/activity_editor.dart';
import '../widgets/block_actions.dart';
import '../widgets/neo.dart';

/// The activity catalogue as an indented tree: colour swatch + name + external
/// id + bookmark star per node. Tap a node to edit; long-press for add-child /
/// bookmark / delete. "+ NEW ACTIVITY" creates a top-level activity.
class ActivitiesScreen extends ConsumerWidget {
  const ActivitiesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = neo(context);
    final tree = ref.watch(activityTreeProvider);
    final ids = tree.flattened();

    return Column(
      children: [
        Expanded(
          child: ids.isEmpty
              ? Center(child: Text('no activities yet', style: mono(context, color: t.muted)))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  itemCount: ids.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _ActivityRow(tree: tree, id: ids[i]),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: NeoButton(
            label: '+ new activity',
            primary: true,
            onTap: () => showActivityEditor(context, ref),
          ),
        ),
      ],
    );
  }
}

class _ActivityRow extends ConsumerWidget {
  const _ActivityRow({required this.tree, required this.id});
  final ActivityTree tree;
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = neo(context);
    final a = tree[id]!;
    final depth = tree.depthOf(id);

    return Padding(
      padding: EdgeInsets.only(left: depth * 18.0),
      child: NeoPressable(
        shadowOffset: depth == 0 ? 5 : 3,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        onTap: () => showActivityEditor(context, ref, existing: a),
        onLongPress: () => _showRowActions(context, ref, a),
        child: Row(
          children: [
            NeoSwatch(parseHexColor(a.color)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: mono(context, weight: FontWeight.w800)),
                  if (a.externalId != null)
                    Text(a.externalId!, style: mono(context, size: 11, weight: FontWeight.w700, color: t.brand)),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => ref.read(activityRepositoryProvider).setBookmarked(a.syncId, !a.bookmarked),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(a.bookmarked ? '★' : '☆',
                    style: mono(context, size: 20, weight: FontWeight.w800, color: a.bookmarked ? t.brand : t.muted)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showRowActions(BuildContext context, WidgetRef ref, Activity a) async {
  final t = neo(context);
  await showNeoSheet<void>(
    context,
    (sheet) => Container(
      margin: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: t.bg, border: Border.all(color: t.line, width: 3)),
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NeoChip(a.name),
          const SizedBox(height: 14),
          NeoButton(
            label: '+ add sub-activity',
            onTap: () {
              Navigator.pop(sheet);
              showActivityEditor(context, ref, presetParentId: a.syncId);
            },
          ),
          const SizedBox(height: 10),
          NeoButton(
            label: a.bookmarked ? 'remove bookmark' : 'bookmark',
            onTap: () {
              Navigator.pop(sheet);
              ref.read(activityRepositoryProvider).setBookmarked(a.syncId, !a.bookmarked);
            },
          ),
          const SizedBox(height: 10),
          // A work task's name is usually the thing you need somewhere else —
          // a commit message, a tracker, a chat — and rows are already tap and
          // long-press targets, so this is an action rather than selectable text.
          NeoButton(
            label: '⧉ copy name',
            onTap: () {
              Navigator.pop(sheet);
              copyToClipboard(context, a.name, 'name');
            },
          ),
          if (a.externalId != null) ...[
            const SizedBox(height: 10),
            NeoButton(
              label: '⧉ copy ${a.externalId}',
              onTap: () {
                Navigator.pop(sheet);
                copyToClipboard(context, a.externalId!, 'id');
              },
            ),
          ],
          const SizedBox(height: 10),
          NeoButton(
            label: 'delete',
            onTap: () async {
              Navigator.pop(sheet);
              final ok = await _confirmDelete(context, a.name);
              if (ok) await ref.read(activityRepositoryProvider).deleteActivity(a.syncId);
            },
          ),
        ],
      ),
    ),
  );
}

Future<bool> _confirmDelete(BuildContext context, String name) async {
  final t = neo(context);
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: t.surface,
      shape: RoundedRectangleBorder(side: BorderSide(color: t.line, width: 3), borderRadius: BorderRadius.zero),
      title: Text('DELETE', style: mono(context, weight: FontWeight.w800)),
      content: Text('Delete "$name"? Any sub-activities move to the top level.', style: mono(context)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text('CANCEL', style: mono(context))),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text('DELETE', style: mono(context, weight: FontWeight.w800, color: ActivityPalette.red)),
        ),
      ],
    ),
  );
  return result ?? false;
}
