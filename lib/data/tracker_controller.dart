import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database.dart';
import 'providers.dart';
import 'repositories.dart';

/// Compound actions that span both repositories. The screens call this instead
/// of wiring two repos together themselves — chiefly so a "switch" also bumps
/// the target activity's recency for the autocomplete.
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
}

final trackerControllerProvider = Provider<TrackerController>((ref) {
  return TrackerController(
    ref.watch(activityRepositoryProvider),
    ref.watch(changeRepositoryProvider),
  );
});
