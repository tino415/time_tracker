import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/pointer_signal.dart';
import '../../data/providers.dart';
import '../../data/tracker_controller.dart';
import '../../domain/block.dart';
import '../../format.dart';
import '../../domain/unsorted.dart';
import 'activity_picker.dart';
import 'assign_activity.dart';
import 'block_comment.dart';
import 'block_split.dart';
import 'block_start.dart';
import 'neo.dart';
import 'swap_undo.dart';

/// The edit menu for one block, shared by the timeline list, the calendar and
/// the Now hero, so all three offer the same verbs on the same data.
///
/// [canMerge] is false for the earliest block, which has no boundary before it
/// to delete. Whether the block has a *predecessor* is a different question and
/// is answered here from the block list, not by the caller — see the note on
/// `previous` below.
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
  final hasPointer = ref.read(hasPointerProvider);
  // The block before this one, found here rather than passed in. The three
  // callers answer "is there a previous" differently — the calendar passes a
  // slice flag that is false for a block spanning midnight, which does have a
  // predecessor — and a verb offered on one screen and missing on another is a
  // worse fault than the one it fixes.
  final blocks = ref.read(blocksProvider);
  final index = blocks.indexWhere((b) => b.change.syncId == block.change.syncId);
  // Newest first, so the entry after this one is the earlier block.
  final previous = index >= 0 && index + 1 < blocks.length ? blocks[index + 1] : null;
  // This is the sheet that most needs the scroll control showNeoSheet gives
  // every one of them: change, tag, untag, split, retime, note and merge is
  // seven rows, past the 9/16 an unscrolled sheet is capped at.
  await showNeoSheet<void>(
    context,
    (sheetContext) => Container(
      margin: const EdgeInsets.all(10),
      constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * 0.85),
      decoration: BoxDecoration(
        color: t.bg,
        border: Border.all(color: t.line, width: 3),
      ),
      padding: const EdgeInsets.all(14),
      child: SingleChildScrollView(
        child: _MaybeSelectable(
          selectable: hasPointer,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NeoChip('Block'),
              const SizedBox(height: 12),
              // The activities as a *list*, each row carrying its own actions.
              //
              // This replaced three verbs — change / tag / untag — that each opened
              // a second sheet to ask which activity they applied to. On a
              // multi-activity block that asked a question already answered in the
              // user's head, about a list they could not see while answering.
              // Acting on the row removes the question instead of improving it.
              for (final a in block.activities)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ActivityRow(
                    block: block,
                    activity: a,
                    sheetContext: sheetContext,
                    host: context,
                    ref: ref,
                  ),
                ),
              const SizedBox(height: 2),
              NeoButton(
                // Naming an unnamed block replaces the catch-all rather than
                // joining it: "Unnamed + Email" would read as the forgot-to-switch
                // case and halve the attribution.
                label: isUnsortedSet(block.activities) ? '▸ what was this?' : '+ another activity',
                primary: isUnsortedSet(block.activities),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  if (isUnsortedSet(block.activities)) {
                    await assignBlockActivity(context, ref, block);
                    return;
                  }
                  final id = await pickOrCreateActivity(
                    context,
                    ref,
                    title: 'Tag with',
                    exclude: block.activities.map((a) => a.syncId).toSet(),
                  );
                  if (id == null) return;
                  await ref
                      .read(changeRepositoryProvider)
                      .addActivityToChange(block.change.syncId, id);
                },
              ),
              const SizedBox(height: 14),
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
                label: (block.comment == null || block.comment!.isEmpty)
                    ? '✎ add a note'
                    : '✎ edit note',
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
              // The button stays even where the sheet is also selectable
              // (`_MaybeSelectable` above): picking out a long name precisely is
              // worse than one click when the whole string is what you want.
              // Without a mouse it stays the only way to get the text out at
              // all — the block cards this sheet opens from are tap and
              // long-press targets, and the calendar's are drag-to-retime, so a
              // selection layer there would take exactly the gestures the app
              // already spends.
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
              if (previous != null) ...[
                const SizedBox(height: 10),
                // "Trade labels", not "swap": the one way this action is read
                // wrongly is as a reorder, with the durations following the
                // names. Naming the neighbour rather than saying "the block
                // before" also makes it checkable before tapping.
                //
                // Deliberately not called swap, which this sheet already spends
                // on the per-activity action meaning replace — and which the
                // watch spends the same way, so renaming either would leave the
                // two disagreeing.
                NeoButton(
                  label: '⇅ trade labels with ${_neighbourLabel(previous, block)}',
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await swapWithUndo(context, ref, block.change.syncId);
                  },
                ),
              ],
              if (canMerge) ...[
                const SizedBox(height: 10),
                NeoButton(
                  label: 'merge into previous block',
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await ref
                        .read(trackerControllerProvider)
                        .mergeIntoPrevious(block.change.syncId);
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

/// How the block being traded with is named on the button: its start time and
/// its activities, joined the way every other label here joins them.
///
/// The day is included only when the neighbour began on a different date, which
/// happens on the block that spans midnight. A bare "09:00" there would name the
/// wrong block, and printing the date always would spend the width on nothing.
String _neighbourLabel(Block previous, Block block) {
  final sameDay =
      previous.start.year == block.start.year &&
      previous.start.month == block.start.month &&
      previous.start.day == block.start.day;
  final when = sameDay
      ? formatTimeOfDay(previous.start)
      : '${previous.start.day}/${previous.start.month} ${formatTimeOfDay(previous.start)}';

  // deriveBlocks drops soft-deleted activities, so a block can arrive carrying
  // none. Naming the time alone still identifies it; a trailing empty name would
  // read as a bug and defeat the point of naming the neighbour at all.
  final names = previous.activities.map((a) => a.name).join(' + ');
  if (names.isEmpty) return 'the block at $when';

  // NeoButton's label does not ellipsize, so a long set would wrap the button
  // over several lines. Cut it here, where the string is built.
  final label = '$when $names';
  return label.length <= 34 ? label : '${label.substring(0, 33)}…';
}

/// One activity on the block, with the two things you can do to *it*.
///
/// Both actions name the row they sit on, so neither has to ask "which one?".
class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.block,
    required this.activity,
    required this.sheetContext,
    required this.host,
    required this.ref,
  });

  final Block block;
  final Activity activity;

  /// The *caller's* ref, not one of this row's own.
  ///
  /// A ConsumerWidget inside the sheet would give a ref that dies with the sheet
  /// — and every action here pops the sheet first, so by the time the write
  /// runs it would be reading from a disposed element and throwing into an async
  /// gap where nothing surfaces it. The action would simply not happen.
  final WidgetRef ref;

  /// The sheet's own context, used only to close it.
  final BuildContext sheetContext;

  /// The context that *opened* the sheet, and the one the next sheet must be
  /// pushed from. The row's own context lives inside the sheet being popped, so
  /// using it afterwards addresses a route that is on its way out — the picker
  /// then opens against nothing and the action silently does not happen.
  final BuildContext host;

  @override
  Widget build(BuildContext context) {
    final t = neo(context);
    final unnamed = isUnsorted(activity);

    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.line, width: 2),
      ),
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      child: Row(
        children: [
          NeoSwatch(parseHexColor(activity.color), size: 14),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              activity.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono(context, weight: FontWeight.w700),
            ),
          ),
          // The catch-all is answered by the "what was this?" button below, not
          // swapped like a real tag — offering both would be two labels for one
          // write.
          if (!unnamed) ...[
            _RowAction(
              label: 'swap',
              onTap: () async {
                Navigator.pop(sheetContext);
                final id = await pickOrCreateActivity(
                  host,
                  ref,
                  title: 'Replace ${activity.name} with',
                  exclude: block.activities.map((a) => a.syncId).toSet(),
                );
                if (id == null) return;
                await ref.read(trackerControllerProvider).retagActivity(block, activity.syncId, id);
              },
            ),
            const SizedBox(width: 6),
            _RowAction(
              label: '×',
              // Always available, including on the last row. Removing the only
              // activity does not fail: the block becomes an unnamed one, which
              // is what the catch-all is for. A disabled control here would make
              // the user carry a rule the data model can express itself.
              onTap: () async {
                Navigator.pop(sheetContext);
                await ref.read(trackerControllerProvider).untagActivity(block, activity.syncId);
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _RowAction extends StatelessWidget {
  const _RowAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = neo(context);
    return Semantics(
      button: true,
      container: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: t.line,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          // Uppercased like every other control here — NeoButton and NeoChip
          // both do it, and a lowercase row action would read as a label.
          child: Text(
            label.toUpperCase(),
            style: mono(context, size: 11, weight: FontWeight.w800, color: t.surface),
          ),
        ),
      ),
    );
  }
}

/// A `SelectionArea` when [selectable], the bare [child] otherwise — the
/// sheet's rows are plain buttons with no drag or long-press of their own, so
/// there is nothing here for a mouse selection to compete with.
class _MaybeSelectable extends StatelessWidget {
  const _MaybeSelectable({required this.selectable, required this.child});
  final bool selectable;
  final Widget child;

  @override
  Widget build(BuildContext context) => selectable ? SelectionArea(child: child) : child;
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
      content: Text(
        '$what copied',
        style: mono(context, weight: FontWeight.w800, color: t.surface),
      ),
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
Future<void> promptSplit(BuildContext context, WidgetRef ref, Block block, [DateTime? at]) async {
  final point = at ?? await chooseSplitPoint(context, ref, block);
  if (point == null) return;
  if (!context.mounted) return;

  final id = await showActivityPicker(context, ref, title: 'Track what from here');
  if (id == null) return;
  await ref.read(trackerControllerProvider).splitBlock(block: block, at: point, activityId: id);
}
