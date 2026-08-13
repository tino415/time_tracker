import '../domain/wear_protocol.dart';
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

  /// Re-parent an activity ([parentId] null moves it to the top level). A move
  /// that would create a cycle (onto itself or into its own subtree) is refused
  /// — the call is then a no-op.
  Future<void> setParent(String id, String? parentId);

  /// Bump recency (last-used-first autocomplete).
  Future<void> touchUsed(String id, DateTime at);

  /// The catch-all activity behind "start now, name it later", created on first
  /// use. Idempotent, and safe to race: the id is fixed, so two devices (or two
  /// taps) converge on one row rather than making a second catch-all.
  Future<Activity> ensureUnsorted();

  /// Soft-delete: sets [Activities.deletedAt] and bumps version.
  Future<void> deleteActivity(String id);

  /// Adopt a peer's bookmarked set (the watch applying a phone snapshot).
  ///
  /// The snapshot is *authoritative for bookmarks*: listed activities are
  /// created or updated and marked bookmarked, and anything locally bookmarked
  /// but absent from it is un-bookmarked. Nothing is deleted — an activity the
  /// snapshot omits may simply not be a bookmark, and the watch has no business
  /// tombstoning the catalogue.
  Future<void> applyBookmarkSnapshot(List<WearActivity> activities);

  /// Make sure a peer's activity exists locally, without claiming it is a
  /// bookmark. Needed because the phone can be tracking something unbookmarked:
  /// the watch still has to have that row to point its copy of the block at.
  Future<void> ensurePeerActivity(WearActivity activity);
}

/// The timeline: change events and their activity sets.
abstract class ChangeRepository {
  /// Live non-tombstoned changes, newest first.
  Stream<List<ActivityChange>> watchChanges();

  /// One-shot read of the same rows, newest first. Edits that need a boundary's
  /// *neighbours* (moving one, merging into the previous block) read this rather
  /// than racing the stream.
  Future<List<ActivityChange>> loadChanges();

  /// The current (latest) change — its set is what's tracking now.
  Future<ActivityChange?> currentChange();

  /// Switch (the normal live action): a new change at [at] (default now)
  /// replacing the whole active set with `{activityId}`.
  Future<ActivityChange> switchTo(String activityId, {DateTime? at});

  /// Adopt a peer's *current state*: the open block, as it is now.
  ///
  /// Unlike [applyRelayedSwitch] this is not an event and is **not** skipped
  /// when the change already exists — a snapshot is authoritative, and the same
  /// change can legitimately come back re-pointed (an unnamed block that has
  /// since been named) or retimed. Skipping it is how a watch stays stuck on
  /// "unnamed" after the phone names the block.
  ///
  /// Idempotent in the sense that matters: applying the same snapshot twice
  /// writes nothing the second time.
  Future<void> applyPeerCurrentBlock({
    required String changeSyncId,
    required String activityId,
    required DateTime at,
  });

  /// Apply a switch relayed from a peer, under an id the peer minted.
  ///
  /// Idempotent by construction: if [changeSyncId] already exists the call does
  /// nothing. That is what makes the Wear relay safe to deliver twice — once
  /// live and once replayed from the listener service's queue after a restart.
  /// Returns true when a boundary was actually opened.
  Future<bool> applyRelayedSwitch({
    required String changeSyncId,
    required String activityId,
    required DateTime at,
  });

  /// Live join rows across all changes (change id -> activity id). Combined with
  /// [watchChanges] and the activity catalogue to derive the timeline reactively.
  Stream<List<ActivityChangeActivity>> watchChangeActivityLinks();

  /// Retrospective "forgot to switch": add an activity to an existing change's
  /// set (no new boundary).
  Future<void> addActivityToChange(String changeId, String activityId);

  /// Undo a tag: remove an activity from a change's set. The last activity
  /// cannot be removed (a block always tracks something) — call is a no-op then.
  ///
  /// Callers wanting "remove whatever this is" for the *last* activity should
  /// use [TrackerController.untagActivity], which re-points the block at the
  /// catch-all instead of refusing.
  Future<void> removeActivityFromChange(String changeId, String activityId);

  /// Swap one member of a change's set, leaving the rest alone.
  ///
  /// Not remove-then-add: on a single-activity block the remove would be refused
  /// by the empty-set guard, so the two steps are not interchangeable with the
  /// one operation. A no-op if [from] is not in the set, or [to] already is.
  Future<void> replaceActivityInChange(String changeId, String from, String to);

  /// Replace a change's whole activity set with exactly `{activityId}`, leaving
  /// its [ActivityChanges.changedAt] alone.
  ///
  /// This is how an unnamed block is answered later: no new boundary, so the
  /// elapsed time — including the seconds spent deciding — stays with the block
  /// and lands on the activity finally chosen.
  Future<void> setChangeActivity(String changeId, String activityId);

  Future<void> setComment(String changeId, String? comment);

  /// Resize: move a boundary. Because boundaries are shared, this retimes the
  /// end of the previous block and the start of the next at once.
  Future<void> setChangedAt(String changeId, DateTime at);

  /// Soft-delete a change (merges the adjacent blocks).
  Future<void> deleteChange(String id);

  /// The activity ids active from [changeId].
  Future<List<String>> activityIdsForChange(String changeId);
}
