import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../domain/activity_tree.dart';
import '../../format.dart';
import 'neo.dart';

/// Pick an existing activity from the catalogue. Shows the hierarchy (indented,
/// name order) with a live filter over name + external id. Returns the chosen
/// activity's syncId, or null if dismissed.
///
/// [exclude] hides ids (and, when [excludeSubtrees] is set, their descendants) —
/// e.g. picking a parent must not offer the node itself or its own subtree.
Future<String?> showActivityPicker(
  BuildContext context,
  WidgetRef ref, {
  String title = 'Pick activity',
  Set<String> exclude = const {},
  bool excludeSubtrees = false,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PickerSheet(
      title: title,
      exclude: exclude,
      excludeSubtrees: excludeSubtrees,
    ),
  );
}

class _PickerSheet extends ConsumerStatefulWidget {
  const _PickerSheet({
    required this.title,
    required this.exclude,
    required this.excludeSubtrees,
  });

  final String title;
  final Set<String> exclude;
  final bool excludeSubtrees;

  @override
  ConsumerState<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends ConsumerState<_PickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final t = neo(context);
    final tree = ref.watch(activityTreeProvider);

    final hidden = <String>{...widget.exclude};
    if (widget.excludeSubtrees) {
      for (final id in widget.exclude) {
        hidden.addAll(tree.subtreeIds(id));
      }
    }

    final q = _query.trim().toLowerCase();
    // When searching, flatten to a filtered flat list; otherwise show the tree.
    final ids = tree.flattened().where((id) {
      if (hidden.contains(id)) return false;
      if (q.isEmpty) return true;
      final a = tree[id]!;
      return a.name.toLowerCase().contains(q) ||
          (a.externalId?.toLowerCase().contains(q) ?? false);
    }).toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        margin: const EdgeInsets.all(10),
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
        decoration: BoxDecoration(color: t.bg, border: Border.all(color: t.line, width: 3)),
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                NeoChip(widget.title),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Text('✕', style: mono(context, size: 18, weight: FontWeight.w800)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _SearchField(onChanged: (v) => setState(() => _query = v)),
            const SizedBox(height: 12),
            Flexible(
              child: ids.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text('no activities',
                          textAlign: TextAlign.center, style: mono(context, color: t.muted)),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: ids.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _PickerRow(
                        tree: tree,
                        id: ids[i],
                        indent: q.isEmpty,
                        onTap: () => Navigator.pop(context, ids[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.tree,
    required this.id,
    required this.indent,
    required this.onTap,
  });

  final ActivityTree tree;
  final String id;
  final bool indent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = neo(context);
    final a = tree[id]!;
    final depth = indent ? tree.depthOf(id) : 0;
    return Padding(
      padding: EdgeInsets.only(left: depth * 16.0),
      child: NeoPressable(
        onTap: onTap,
        shadowOffset: 3,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(
          children: [
            NeoSwatch(parseHexColor(a.color), size: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                indent ? a.name : tree.pathName(id),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mono(context, weight: FontWeight.w700),
              ),
            ),
            if (a.externalId != null) ...[
              const SizedBox(width: 8),
              Text(a.externalId!, style: mono(context, size: 11, color: t.muted)),
            ],
          ],
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.onChanged});
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = neo(context);
    return Container(
      decoration: BoxDecoration(color: t.surface, border: Border.all(color: t.line, width: 3)),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: TextField(
        autofocus: true,
        onChanged: onChanged,
        style: mono(context, weight: FontWeight.w700),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: 'search…',
          hintStyle: mono(context, color: t.muted),
        ),
      ),
    );
  }
}
