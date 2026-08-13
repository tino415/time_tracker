import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/tracker_controller.dart';
import '../../domain/block.dart';
import '../../domain/unsorted.dart';
import 'activity_picker.dart';
import 'assign_activity.dart';
import 'block_comment.dart';
import 'block_split.dart';
import 'block_start.dart';
import 'neo.dart';

/// The edit menu for one block, shared by the timeline list, the calendar and
/// the Now hero, so all three offer the same verbs on the same data.
///
/// [canMerge] is false for the earliest block, which has no boundary before it
/// to delete.
///
/// Split used to be here only when the caller supplied a position, which meant
/// the calendar only. It is offered everywhere now: the calendar cannot express
/// a position inside a block a few pixels tall, so on a day of short blocks that
/// arrangement put the action behind a gesture that could not be made.
Future<void> showBlockActions(
  BuildContext context,
  WidgetRef ref,
  Block block, {
  bool canMerge = true,
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
            // Resuming, not editing — so it sits apart from the verbs below,
            // which all change the block you opened this from. Hidden on the
            // running block: "track this again" for what is already tracking is
            // a split, and re-picking it on Now is the gesture for that.
            if (!block.isOpen && block.activities.isNotEmpty) ...[
              NeoButton(
                label: '▶ track this again',
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await ref.read(trackerControllerProvider).resumeBlock(block);
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
            // Hidden only when there is no legal cut: splitting needs a real
            // half either side, so a block under two minutes has nowhere to go.
            if (canSplit(block, DateTime.now())) ...[
              const SizedBox(height: 10),
              NeoButton(
                // "at…", not "in half": the midpoint is the starting guess, not
                // the offer.
                label: '✂ split at…',
                onTap: () {
                  Navigator.pop(sheetContext);
                  promptSplit(context, ref, block);
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
            // Getting text back *out*. Names are routinely pasted in — the
            // paste-to-create flow exists — so being unable to lift one into a
            // commit message or a work tracker without retyping it is the
            // asymmetry worth closing.
            //
            // An explicit action rather than selectable text: the block cards
            // this sheet opens from are tap and long-press targets, and the
            // calendar's are drag-to-retime, so a selection layer would take
            // exactly the gestures the app already spends.
            const SizedBox(height: 10),
            NeoButton(
              label: '⧉ copy name',
              onTap: () {
                Navigator.pop(sheetContext);
                copyToClipboard(context, block.activities.map((a) => a.name).join(' + '), 'name');
              },
            ),
            if (block.comment != null && block.comment!.isNotEmpty) ...[
              const SizedBox(height: 10),
              NeoButton(
                label: '⧉ copy note',
                onTap: () {
                  Navigator.pop(sheetContext);
                  copyToClipboard(context, block.comment!, 'note');
                },
              ),
            ],
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

/// Put [text] on the clipboard and say so.
///
/// The confirmation is not decoration: a copy has no visible effect anywhere on
/// screen, so without it the only way to know whether the tap registered is to
/// go and paste somewhere.
void copyToClipboard(BuildContext context, String text, String what) {
  Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  final t = neo(context);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: t.line,
      duration: const Duration(seconds: 2),
      content: Text('$what copied',
          style: mono(context, weight: FontWeight.w800, color: t.surface)),
    ),
  );
}

/// Split [block]: choose where, then what the *second* half tracks.
///
/// [at] is supplied by the calendar's long-press, which names a position
/// directly. Without it the split point is asked for — see [chooseSplitPoint]
/// for why that is the general case rather than the fallback.
///
/// Where before what, because the boundary is the decision: the picker's own
/// title ("track what from here") only means something once "here" is fixed.
/// Returns silently if either step is dismissed or the point is not splittable.
Future<void> promptSplit(
  BuildContext context,
  WidgetRef ref,
  Block block, [
  DateTime? at,
]) async {
  final point = at ?? await chooseSplitPoint(context, ref, block);
  if (point == null) return;
  if (!context.mounted) return;

  final id = await showActivityPicker(
    context,
    ref,
    title: 'Track what from here',
  );
  if (id == null) return;
  await ref.read(trackerControllerProvider).splitBlock(
        block: block,
        at: point,
        activityId: id,
      );
}
