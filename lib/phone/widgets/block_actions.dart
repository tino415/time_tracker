import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/tracker_controller.dart';
import '../../domain/block.dart';
import '../../domain/unsorted.dart';
import 'activity_picker.dart';
import 'assign_activity.dart';
import 'block_comment.dart';
import 'block_start.dart';
import 'neo.dart';

/// The edit menu for one block, shared by the timeline list, the calendar and
/// the Now hero, so all three offer the same verbs on the same data.
///
/// [canMerge] is false for the earliest block, which has no boundary before it
/// to delete. [onSplit] is supplied by the calendar, where a split has a
/// meaningful position; the list view omits it.
Future<void> showBlockActions(
  BuildContext context,
  WidgetRef ref,
  Block block, {
  bool canMerge = true,
  VoidCallback? onSplit,
}) async {
  final t = neo(context);
  await showModalBottomSheet<void>(
    context: context,
    // A multi-activity block on a short screen can fill this: change, tag,
    // untag, split, retime, note and merge is seven rows, past the 9/16 of the
    // screen an unscrolled sheet is capped at.
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => Container(
      margin: const EdgeInsets.all(10),
      constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * 0.85),
      decoration: BoxDecoration(color: t.bg, border: Border.all(color: t.line, width: 3)),
      padding: const EdgeInsets.all(14),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NeoChip('Block · ${block.activities.map((a) => a.name).join(", ")}'),
            const SizedBox(height: 14),
            // An unnamed block's only interesting action is naming it, so it leads.
            if (isUnsortedSet(block.activities)) ...[
              NeoButton(
                label: '▸ what was this?',
                primary: true,
                onTap: () {
                  Navigator.pop(sheetContext);
                  assignBlockActivity(context, ref, block);
                },
              ),
              const SizedBox(height: 10),
            ] else ...[
              // Swapping *is* naming, for a block that already has one — so an
              // unnamed block leads with "what was this?" instead of offering
              // the same write twice under two labels.
              NeoButton(
                // Glyph-free, like "merge into previous block": JetBrains Mono
                // has no swap arrow, and a tofu box is worse than a plain label.
                label: 'change activity',
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final id = await showActivityPicker(
                    context,
                    ref,
                    title: block.activities.length > 1 ? 'Replace the set with' : 'Change to',
                    exclude: block.activities.map((a) => a.syncId).toSet(),
                  );
                  if (id != null) {
                    await ref.read(trackerControllerProvider).assignBlock(block.change.syncId, id);
                  }
                },
              ),
              const SizedBox(height: 10),
            ],
            NeoButton(
              label: '+ tag another activity',
              onTap: () async {
                Navigator.pop(sheetContext);
                final id = await showActivityPicker(
                  context,
                  ref,
                  title: 'Tag with activity',
                  exclude: block.activities.map((a) => a.syncId).toSet(),
                );
                if (id != null) {
                  await ref.read(changeRepositoryProvider).addActivityToChange(block.change.syncId, id);
                }
              },
            ),
            if (block.activities.length > 1) ...[
              const SizedBox(height: 10),
              NeoButton(
                label: '- untag an activity',
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final id = await showActivityPicker(
                    context,
                    ref,
                    title: 'Remove which activity',
                    // Only this block's own set can be untagged.
                    only: block.activities.map((a) => a.syncId).toSet(),
                  );
                  if (id != null) {
                    await ref.read(changeRepositoryProvider).removeActivityFromChange(block.change.syncId, id);
                  }
                },
              ),
            ],
            if (onSplit != null) ...[
              const SizedBox(height: 10),
              NeoButton(
                label: '✂ split in half',
                onTap: () {
                  Navigator.pop(sheetContext);
                  onSplit();
                },
              ),
            ],
            const SizedBox(height: 10),
            NeoButton(
              label: 'edit start time',
              onTap: () {
                Navigator.pop(sheetContext);
                editBlockStart(context, ref, block);
              },
            ),
            const SizedBox(height: 10),
            NeoButton(
              label: (block.comment == null || block.comment!.isEmpty) ? '✎ add a note' : '✎ edit note',
              onTap: () {
                Navigator.pop(sheetContext);
                editBlockComment(context, ref, block);
              },
            ),
            if (canMerge) ...[
              const SizedBox(height: 10),
              NeoButton(
                label: 'merge into previous block',
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await ref.read(trackerControllerProvider).mergeIntoPrevious(block.change.syncId);
                },
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

/// Ask which activity the *second* half of a split should track, then split.
/// Returns silently if the picker is dismissed or the point is not splittable.
Future<void> promptSplit(
  BuildContext context,
  WidgetRef ref,
  Block block,
  DateTime at,
) async {
  final id = await showActivityPicker(
    context,
    ref,
    title: 'Track what from here',
  );
  if (id == null) return;
  await ref.read(trackerControllerProvider).splitBlock(
        block: block,
        at: at,
        activityId: id,
      );
}
