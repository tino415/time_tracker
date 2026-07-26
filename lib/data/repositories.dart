import 'database.dart';

/// Repository seam over [AppDatabase]. Every client (phone, watch, web) is
/// offline-first on local Drift, so there is a single local implementation
/// ([DriftActivityRepository] / [DriftChangeRepository]); cross-device sync is
/// layered on later as a *transport* over this same local DB, not an alternate
/// remote repository. Keeping the interface now means the phase-1 UI depends on
/// the seam, not on Drift directly.

/// The activity catalogue: the hierarchy, colours, bookmarks, and recency.
abstract class ActivityRepository {
  /// Live non-tombstoned activities, name order.
  Stream<List<Activity>> watchActivities();
  Future<List<Activity>> loadActivities();

  Future<Activity> createActivity({
    required String name,
    required String color,
    String? parentId,
    bool bookmarked = false,
    String? externalId,
  });

  Future<void> renameActivity(String id, String name);
  Future<void> setColor(String id, String color);
  Future<void> setBookmarked(String id, bool bookmarked);

  /// Bump recency (last-used-first autocomplete).
  Future<void> touchUsed(String id, DateTime at);

  /// Soft-delete: sets [Activities.deletedAt] and bumps version.
  Future<void> deleteActivity(String id);
}

/// The timeline: change events and their activity sets.
abstract class ChangeRepository {
  /// Live non-tombstoned changes, newest first.
  Stream<List<ActivityChange>> watchChanges();

  /// The current (latest) change — its set is what's tracking now.
  Future<ActivityChange?> currentChange();

  /// Switch (the normal live action): a new change at [at] (default now)
  /// replacing the whole active set with `{activityId}`.
  Future<ActivityChange> switchTo(String activityId, {DateTime? at});

  /// Live join rows across all changes (change id -> activity id). Combined with
  /// [watchChanges] and the activity catalogue to derive the timeline reactively.
  Stream<List<ActivityChangeActivity>> watchChangeActivityLinks();

  /// Retrospective "forgot to switch": add an activity to an existing change's
  /// set (no new boundary).
  Future<void> addActivityToChange(String changeId, String activityId);

  /// Undo a tag: remove an activity from a change's set. The last activity
  /// cannot be removed (a block always tracks something) — call is a no-op then.
  Future<void> removeActivityFromChange(String changeId, String activityId);

  Future<void> setComment(String changeId, String? comment);

  /// Resize: move a boundary. Because boundaries are shared, this retimes the
  /// end of the previous block and the start of the next at once.
  Future<void> setChangedAt(String changeId, DateTime at);

  /// Soft-delete a change (merges the adjacent blocks).
  Future<void> deleteChange(String id);

  /// The activity ids active from [changeId].
  Future<List<String>> activityIdsForChange(String changeId);
}
