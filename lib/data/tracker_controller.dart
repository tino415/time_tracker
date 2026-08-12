import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/block.dart';
import '../domain/calendar.dart';
import 'database.dart';
import 'providers.dart';
import 'repositories.dart';

/// What a switch actually did, so the screen can offer to take it back.
///
/// Only [switchTo] reports this. The block is written either way — an undo is
/// an offer, not a confirmation prompt, so nothing waits on the user.
class SwitchOutcome {
  const SwitchOutcome({required this.changeId, required this.splitSameActivity});

  /// The boundary that was opened.
  final String changeId;

  /// The new block tracks exactly what the previous one did, so this switch
  /// split a block rather than changing what is being tracked. Deliberate when
  /// the second stretch needs its own note, a fumble when it does not — and only
  /// the person who tapped can tell which, which is why it is offered rather
  /// than judged.
  final bool splitSameActivity;
}

/// The actions the screens invoke: the ones that span both repositories (a
/// "switch" also bumps the target activity's recency for the autocomplete), and
/// the timeline edits that need a boundary's neighbours before they are safe to
/// write. Screens call this instead of wiring the repositories together
/// themselves.
class TrackerController {
  TrackerController(this._activities, this._changes);

  final ActivityRepository _activities;
  final ChangeRepository _changes;

  /// The normal live action: open a new block tracking [activityId] and mark it
  /// as just-used (recency drives the paste/search autocomplete).
  ///
  /// Picking whatever is *already* running opens a new boundary too, splitting
  /// the block in two. This used to be a no-op, on the reasoning that the two
  /// halves would be indistinguishable — but a comment lives on the change, one
  /// per block, so they are distinguished by the thing every block already has.
  /// Splitting is how a different note gets attached to the second stretch of
  /// the same work, which is a common thing to want rather than an edge case.
  ///
  /// The risk that guard covered was the accidental double-tap. That is handled
  /// by making the split visible instead of by guessing intent: the returned
  /// [SwitchOutcome] says when a same-activity split happened, and the caller
  /// offers to undo it. A time threshold was rejected — it guesses, and puts
  /// wall-clock timing into a test.
  Future<SwitchOutcome> switchTo(String activityId, {DateTime? at}) async {
    // Read before the write, and only for the label: an explicit [at] is a
    // deliberate boundary (a split, a retime), never a fumbled tap.
    final splitSameActivity = at == null && await _isTrackingExactly(activityId);
    final now = at ?? DateTime.now();
    final change = await _changes.switchTo(activityId, at: now);
    await _activities.touchUsed(activityId, now);
    return SwitchOutcome(changeId: change.syncId, splitSameActivity: splitSameActivity);
  }

  /// True when the open block tracks exactly [activityId] and nothing else.
  ///
  /// A block tracking two activities is a different case: picking one of them
  /// narrows the set back down, which is a real change and never a fumble.
  Future<bool> _isTrackingExactly(String activityId) async {
    final current = await _changes.currentChange();
    if (current == null) return false;
    final ids = await _changes.activityIdsForChange(current.syncId);
    return ids.length == 1 && ids.first == activityId;
  }

  /// Start tracking *something*, right now, without deciding what.
  ///
  /// The whole point is that this costs one tap and no typing: the boundary
  /// opens at the moment of the tap against the catch-all activity, and the
  /// block is answered later with [assignBlock]. Deciding first would charge the
  /// deciding to whatever you were doing before.
  ///
  /// Always opens a boundary, even when an unnamed block is already running:
  /// two consecutive unnamed blocks are two different things to be named later,
  /// and collapsing them merges unrelated work with no way to separate it
  /// afterwards. That is the common case when only the watch is to hand.
  ///
  /// This was once the exception to [switchTo]'s no-op guard. The guard is gone
  /// and the argument generalised, so the two now follow one rule — but no undo
  /// is offered here, unlike [switchTo]. There, a same-activity split is
  /// ambiguous; here it is the whole point, and a prompt would nag the one flow
  /// whose entire value is costing a single tap and no reading.
  Future<void> startUnsorted({DateTime? at}) async {
    final unsorted = await _activities.ensureUnsorted();
    final now = at ?? DateTime.now();
    await _changes.switchTo(unsorted.syncId, at: now);
    await _activities.touchUsed(unsorted.syncId, now);
  }

  /// Re-point a block at [activityId], keeping its start and replacing whatever
  /// set it had. This answers an unnamed block, and is also how a named one is
  /// corrected ("that hour was Email, not Deep work").
  ///
  /// Not a switch — no new boundary — so the elapsed time, including the seconds
  /// spent choosing, belongs to the activity finally picked.
  Future<void> assignBlock(String changeId, String activityId) async {
    await _changes.setChangeActivity(changeId, activityId);
    await _activities.touchUsed(activityId, DateTime.now());
  }

  /// Create a work task (a leaf under [parentId]) from a pasted "CU-1234 Title",
  /// inheriting the parent's colour unless [color] is given, then switch to it.
  /// Returns the new activity.
  Future<Activity> createAndSwitch({
    required String name,
    required String color,
    String? parentId,
    String? externalId,
    bool bookmarked = false,
  }) async {
    final activity = await _activities.createActivity(
      name: name,
      color: color,
      parentId: parentId,
      externalId: externalId,
      bookmarked: bookmarked,
    );
    await switchTo(activity.syncId);
    return activity;
  }

  // ---- calendar edits ------------------------------------------------------

  /// Move an existing boundary — the calendar's drag-to-resize. One boundary is
  /// shared by two blocks, so this retimes the end of the earlier block and the
  /// start of the later one in a single write.
  ///
  /// [to] is clamped to stay strictly between the neighbouring boundaries (and
  /// out of the future), so a drag can never reorder the timeline. If the
  /// neighbours leave no legal room, or the boundary would not actually move,
  /// this is a no-op.
  Future<void> moveBoundary(
    String changeId,
    DateTime to, {
    DateTime? now,
    Duration minBlock = const Duration(minutes: 1),
  }) async {
    final ascending = (await _changes.loadChanges()).reversed.toList();
    final i = ascending.indexWhere((c) => c.syncId == changeId);
    if (i < 0) return;

    final target = clampBoundary(
      desired: to,
      previous: i > 0 ? ascending[i - 1].changedAt : null,
      next: i + 1 < ascending.length ? ascending[i + 1].changedAt : null,
      notAfter: now ?? DateTime.now(),
      minBlock: minBlock,
    );
    if (target == null || target == ascending[i].changedAt) return;

    await _changes.setChangedAt(changeId, target);
  }

  /// Split [block] at [at], tracking [activityId] from that instant on. A split
  /// *is* a switch with an explicit timestamp — the new boundary is the split —
  /// so this also bumps recency like any other switch.
  ///
  /// Refuses a point that would leave a half shorter than [minBlock] (including
  /// a block too short to split at all), so the split always yields two real
  /// blocks.
  Future<void> splitBlock({
    required Block block,
    required DateTime at,
    required String activityId,
    DateTime? now,
    Duration minBlock = const Duration(minutes: 1),
  }) async {
    final end = block.end ?? (now ?? DateTime.now());
    final lower = block.start.add(minBlock);
    final upper = end.subtract(minBlock);
    if (upper.isBefore(lower)) return;
    if (at.isBefore(lower) || at.isAfter(upper)) return;

    await switchTo(activityId, at: at);
  }

  /// Merge a block into the one before it by deleting the boundary that opens
  /// it. The earliest block has no boundary before it — nothing to delete, and
  /// removing it would silently drop the start of recorded history — so that is
  /// a no-op.
  Future<void> mergeIntoPrevious(String changeId) async {
    final ascending = (await _changes.loadChanges()).reversed.toList();
    if (ascending.isEmpty || ascending.first.syncId == changeId) return;
    if (!ascending.any((c) => c.syncId == changeId)) return;
    await _changes.deleteChange(changeId);
  }
}

final trackerControllerProvider = Provider<TrackerController>((ref) {
  return TrackerController(
    ref.watch(activityRepositoryProvider),
    ref.watch(changeRepositoryProvider),
  );
});
