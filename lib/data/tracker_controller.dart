import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/block.dart';
import '../domain/calendar.dart';
import 'database.dart';
import 'providers.dart';
import 'repositories.dart';

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
  /// Tapping whatever is *already* tracking is a no-op rather than a new
  /// boundary — switching replaces the active set, and here the set wouldn't
  /// change, so splitting the running block in two would only lose information.
  /// An explicit [at] is always honoured (a deliberate boundary at that time).
  Future<void> switchTo(String activityId, {DateTime? at}) async {
    if (at == null && await _isAlreadyTracking(activityId)) return;
    final now = at ?? DateTime.now();
    await _changes.switchTo(activityId, at: now);
    await _activities.touchUsed(activityId, now);
  }

  /// True when the open block tracks exactly [activityId] and nothing else.
  Future<bool> _isAlreadyTracking(String activityId) async {
    final current = await _changes.currentChange();
    if (current == null) return false;
    final ids = await _changes.activityIdsForChange(current.syncId);
    return ids.length == 1 && ids.first == activityId;
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
