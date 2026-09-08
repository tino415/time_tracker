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
  ///
  /// [push] false records it without offering the row to the server. For the
  /// watch, where a row may have arrived over the Wear relay carrying only the
  /// fields the relay protocol has — pushing one would state the fields it does
  /// *not* have as fact, and version-LWW would let that win.
  Future<void> touchUsed(String id, DateTime at, {bool push = true});

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
  ///
  /// [version] is the sender's, and seeds this device's copy so the two
  /// counters can be compared afterwards. Null from a peer that does not send
  /// one, which leaves the local version alone.
  Future<void> applyPeerCurrentBlock({
    required String changeSyncId,
    required String activityId,
    required DateTime at,
    required int? version,
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

  /// One change by its id, or null. Callers that need a row's *version* — the
  /// relay puts it on the wire — read it here rather than scanning
  /// [loadChanges].
  Future<ActivityChange?> changeById(String syncId);

  /// Adopt a peer's correction to a boundary both devices already have.
  ///
  /// The counterpart to [applyRelayedSwitch] for edits rather than events, and
  /// the reason the two cannot share a path: a switch is idempotent because a
  /// known id is skipped, while "the start is X" is a valid thing to say twice
  /// and about a row that keeps changing. So these compare versions instead,
  /// with exactly the rule `SyncStore` applies to a row pulled from the server:
  /// strictly newer is adopted, an equal version loses to unpushed local work,
  /// and the value is written *at the version it arrived with* rather than
  /// bumped past it.
  ///
  /// That last part is the point. Applying a relayed correction as a local edit
  /// bumps it above whatever the receiver had, so a stale one — replayed from
  /// the outbox after a disconnect — would beat a newer local edit and then
  /// propagate that stale value through the next sync.
  ///
  /// Returns whether the correction was adopted. Both no-op on a change this
  /// device does not have: a correction names a boundary, it cannot open one.
  ///
  /// [at] is still clamped against *this* device's neighbours. Adopting a
  /// version settles whose answer is newer, not whether that answer fits here —
  /// the sender may have been working from a snapshot that predates a boundary
  /// already on the record, and no relay may reorder two blocks.
  Future<bool> applyRelayedRetime({
    required String changeSyncId,
    required DateTime at,
    required int version,
    DateTime Function()? clock,
  });

  /// See [applyRelayedRetime]. No-op too when [activityId] is unknown here,
  /// which would otherwise break the join row's foreign key.
  Future<bool> applyRelayedAssign({
    required String changeSyncId,
    required String activityId,
    required int version,
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

  /// Exchange what two changes are labelled with: their activity sets and the
  /// comments describing them, in one transaction.
  ///
  /// Neither `changedAt` moves, so the boundaries stay exactly where they are
  /// and no block changes length. This corrects two neighbours labelled the
  /// wrong way round; it is not the fix for a switch made a minute late, which
  /// is a boundary in the wrong place and belongs to [setChangedAt].
  ///
  /// Its own inverse — calling it again puts both back — which is what lets undo
  /// be the same call rather than a second unwind path.
  ///
  /// A no-op when the two carry the same set and the same comment, so a swap
  /// that would change nothing does not mark either row for pushing. Returns
  /// whether it wrote, so a caller does not announce an edit that did not happen.
  ///
  /// Known hazard, and the first edit here to have it: this needs *two* change
  /// rows to land together, and sync resolves one row at a time. If a peer holds
  /// a newer version of exactly one of the pair, it keeps that one and takes the
  /// other, leaving both blocks carrying the same set and one label gone. Every
  /// other multi-block edit — moving a boundary, merging — writes a single row's
  /// payload, so nothing before this could split in transit.
  Future<bool> swapActivitySets(String changeA, String changeB);

  Future<void> setComment(String changeId, String? comment);

  /// Resize: move a boundary. Because boundaries are shared, this retimes the
  /// end of the previous block and the start of the next at once.
  Future<void> setChangedAt(String changeId, DateTime at);

  /// Soft-delete a change (merges the adjacent blocks).
  Future<void> deleteChange(String id);

  /// The activity ids active from [changeId].
  Future<List<String>> activityIdsForChange(String changeId);
}
