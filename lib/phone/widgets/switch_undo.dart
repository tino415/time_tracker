import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/tracker_controller.dart';
import 'neo.dart';

/// Switch to [activityId], and offer to take it back when that split a block
/// rather than changing what is tracked.
///
/// Picking the activity that is already running is legitimate — it is how the
/// second stretch of the same work gets its own note — but it is also exactly
/// what a fumbled double-tap looks like, and the two are indistinguishable from
/// the outside. So the split happens and is *announced*, rather than being
/// suppressed by a guess about intent.
///
/// The undo merges the new block into the one before it, which is the same edit
/// the block menu's "merge into previous block" offers; there is no separate
/// unwind path to keep correct.
Future<void> switchWithUndo(BuildContext context, WidgetRef ref, String activityId) async {
  // Read the controller before the await: the action below outlives this call,
  // and the widget that owns `ref` may be gone by the time it runs.
  final controller = ref.read(trackerControllerProvider);
  final outcome = await controller.switchTo(activityId);

  // A switch to something else needs no comment — the hero already shows it.
  if (!outcome.splitSameActivity) return;
  if (!context.mounted) return;

  final t = neo(context);
  final messenger = ScaffoldMessenger.of(context);
  // Tapping twice more should not stack three of these.
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      backgroundColor: t.line,
      // Longer than the 4s default: this one asks a question, and reading it is
      // the whole point.
      duration: const Duration(seconds: 6),
      // A snack bar with an action otherwise stays until it is acted on, and on
      // the phone shell it sits over the Now field until then.
      persist: false,
      content: Text(
        'new block · same activity',
        style: mono(context, weight: FontWeight.w800, color: t.surface),
      ),
      action: SnackBarAction(
        label: 'UNDO',
        // Not `brand`: it is a dark green on a near-black bar in the light theme
        // and a light green on a near-white one in the dark theme. `surface` is
        // the bar's own contrast colour in both.
        textColor: t.surface,
        onPressed: () => controller.mergeIntoPrevious(outcome.changeId),
      ),
    ),
  );
}
