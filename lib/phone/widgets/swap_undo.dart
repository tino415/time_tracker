import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/tracker_controller.dart';
import 'neo.dart';

/// Trade [changeId]'s labels with the block before it, and offer to take it back.
///
/// The undo is the same call again. A swap is its own inverse, so there is no
/// unwind path that could be wrong — the same argument the switch's undo makes
/// by reusing "merge into previous block".
///
/// The message says what did *not* happen. The one real risk in this action is
/// being read as a reorder, where the durations follow the names; saying the
/// times are unchanged costs a line and answers it before it is asked.
Future<void> swapWithUndo(BuildContext context, WidgetRef ref, String changeId) async {
  // Read the controller before the await: the action below outlives this call,
  // and the widget that owns `ref` may be gone by the time it runs.
  final controller = ref.read(trackerControllerProvider);
  final swapped = await controller.swapWithPrevious(changeId);

  // Nothing was written — no predecessor, or two neighbours already carrying the
  // same label and note, which is what a block split for a second note looks
  // like. Announcing an edit that did not happen, with an undo that would also
  // do nothing, is worse than staying quiet.
  if (swapped == null) return;
  if (!context.mounted) return;

  final t = neo(context);
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      backgroundColor: t.line,
      duration: const Duration(seconds: 6),
      content: Text(
        'labels swapped · times unchanged',
        style: mono(context, weight: FontWeight.w800, color: t.surface),
      ),
      action: SnackBarAction(
        label: 'UNDO',
        textColor: t.surface,
        onPressed: () => controller.swapPair(swapped.$1, swapped.$2),
      ),
    ),
  );
}
