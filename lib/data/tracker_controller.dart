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
  Future<void> switchTo(String activityId, {DateTime? at}) async {
    final now = at ?? DateTime.now();
    await _changes.switchTo(activityId, at: now);
    await _activities.touchUsed(activityId, now);
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
