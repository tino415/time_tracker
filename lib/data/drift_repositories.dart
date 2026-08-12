import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../domain/unsorted.dart';
import '../domain/wear_protocol.dart';
import 'database.dart';
import 'repositories.dart';

const _uuid = Uuid();

class DriftActivityRepository implements ActivityRepository {
  DriftActivityRepository(this._db);
  final AppDatabase _db;

  @override
  Stream<List<Activity>> watchActivities() {
    return (_db.select(_db.activities)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch();
  }

  @override
  Future<List<Activity>> loadActivities() {
    return (_db.select(_db.activities)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
  }

  @override
  Future<Activity> createActivity({
    required String name,
    required String color,
    String? parentId,
    bool bookmarked = false,
    String? externalId,
  }) async {
    final row = ActivitiesCompanion.insert(
      syncId: _uuid.v4(),
      name: name,
      color: color,
      parentId: Value(parentId),
      bookmarked: Value(bookmarked),
      externalId: Value(externalId),
    );
    return _db.into(_db.activities).insertReturning(row);
  }

  @override
  Future<void> renameActivity(String id, String name) =>
      _bump(id, ActivitiesCompanion(name: Value(name)));

  @override
  Future<void> setColor(String id, String color) =>
      _bump(id, ActivitiesCompanion(color: Value(color)));

  @override
  Future<void> setBookmarked(String id, bool bookmarked) =>
      _bump(id, ActivitiesCompanion(bookmarked: Value(bookmarked)));

  @override
  Future<void> setParent(String id, String? parentId) async {
    if (parentId == id) return;
    // Moving a node into its own subtree would orphan the whole branch from the
    // roots (and loop the ancestor walk) — refuse it.
    if (parentId != null && await _isDescendantOf(parentId, id)) return;
    await _bump(id, ActivitiesCompanion(parentId: Value(parentId)));
  }

  /// Walks [candidateId]'s parent chain looking for [ancestorId]. Guarded against
  /// a pre-existing corrupt cycle by a seen-set.
  Future<bool> _isDescendantOf(String candidateId, String ancestorId) async {
    final seen = <String>{};
    String? cursor = candidateId;
    while (cursor != null && seen.add(cursor)) {
      if (cursor == ancestorId) return true;
      final at = cursor;
      final row = await (_db.select(_db.activities)
            ..where((t) => t.syncId.equals(at)))
          .getSingleOrNull();
      cursor = row?.parentId;
    }
    return false;
  }

  @override
  Future<void> touchUsed(String id, DateTime at) =>
      _bump(id, ActivitiesCompanion(lastUsedAt: Value(at)));

  @override
  Future<void> ensurePeerActivity(WearActivity activity) async {
    await _db.transaction(() async {
      final existing = await (_db.select(_db.activities)
            ..where((t) => t.syncId.equals(activity.syncId)))
          .getSingleOrNull();

      if (existing == null) {
        await _db.into(_db.activities).insert(
              ActivitiesCompanion.insert(
                syncId: activity.syncId,
                name: activity.name,
                color: activity.color,
                // Deliberately not a bookmark: being tracked is not the same as
                // being pinned to the watch's switch list.
              ),
            );
        return;
      }

      // Only write on a real difference — see applyBookmarkSnapshot.
      if (existing.name != activity.name || existing.color != activity.color) {
        await _bump(
          activity.syncId,
          ActivitiesCompanion(name: Value(activity.name), color: Value(activity.color)),
        );
      }
    });
  }

  @override
  Future<Activity> ensureUnsorted() async {
    return _db.transaction(() async {
      final existing = await (_db.select(_db.activities)
            ..where((t) => t.syncId.equals(kUnsortedActivityId)))
          .getSingleOrNull();

      // Un-tombstone rather than insert: deleting the catch-all and then
      // starting an unnamed block again must not fail on the primary key.
      if (existing != null) {
        // Two corrections, either of which needs the row read back.
        //
        // The name one is a rename that shipped after some devices had already
        // created the row. Only the *exact* superseded default is touched: a
        // name the user chose themselves is theirs, and self-healing over it
        // would silently undo a deliberate edit on every app start.
        final companion = ActivitiesCompanion(
          deletedAt: existing.deletedAt != null ? const Value(null) : const Value.absent(),
          name: existing.name == kUnsortedLegacyName
              ? const Value(kUnsortedName)
              : const Value.absent(),
        );
        if (companion.deletedAt.present || companion.name.present) {
          // Through _bump, so the version moves and the correction reaches the
          // other devices instead of each one waiting to notice for itself.
          await _bump(kUnsortedActivityId, companion);
          return (await (_db.select(_db.activities)
                ..where((t) => t.syncId.equals(kUnsortedActivityId)))
              .getSingle());
        }
        return existing;
      }

      return _db.into(_db.activities).insertReturning(
            ActivitiesCompanion.insert(
              syncId: kUnsortedActivityId,
              name: kUnsortedName,
              color: kUnsortedColor,
            ),
          );
    });
  }

  @override
  Future<void> deleteActivity(String id) =>
      _bump(id, ActivitiesCompanion(deletedAt: Value(DateTime.now())));

  @override
  Future<void> applyBookmarkSnapshot(List<WearActivity> activities) async {
    await _db.transaction(() async {
      final incoming = {for (final a in activities) a.syncId: a};

      for (final a in activities) {
        final existing = await (_db.select(_db.activities)
              ..where((t) => t.syncId.equals(a.syncId)))
            .getSingleOrNull();

        if (existing == null) {
          await _db.into(_db.activities).insert(
                ActivitiesCompanion.insert(
                  syncId: a.syncId,
                  name: a.name,
                  color: a.color,
                  bookmarked: const Value(true),
                ),
              );
          continue;
        }

        // Only write when something actually differs: an unchanged snapshot
        // arriving every reconnect must not churn `version` and make every
        // activity look freshly edited to a future sync.
        if (existing.name != a.name ||
            existing.color != a.color ||
            !existing.bookmarked ||
            existing.deletedAt != null) {
          await _bump(
            a.syncId,
            ActivitiesCompanion(
              name: Value(a.name),
              color: Value(a.color),
              bookmarked: const Value(true),
              deletedAt: const Value(null),
            ),
          );
        }
      }

      // Bookmarks the snapshot no longer lists are no longer bookmarks. The
      // rows stay: the peer told us what is bookmarked, not what exists.
      final staleBookmarks = await (_db.select(_db.activities)
            ..where((t) => t.bookmarked.equals(true) & t.deletedAt.isNull()))
          .get();
      for (final row in staleBookmarks) {
        if (!incoming.containsKey(row.syncId)) {
          await _bump(row.syncId, const ActivitiesCompanion(bookmarked: Value(false)));
        }
      }
    });
  }

  /// Apply [patch] to one activity, bumping [Activities.version] for LWW sync.
  ///
  /// Also marks the row dirty: this is the single choke point for local edits,
  /// so "needs pushing" is maintained here rather than remembered at each call
  /// site. Remote adoptions bypass it deliberately — see [applyRemoteActivity].
  Future<void> _bump(String id, ActivitiesCompanion patch) async {
    final row = await (_db.select(_db.activities)
          ..where((t) => t.syncId.equals(id)))
        .getSingleOrNull();
    if (row == null) return;
    await (_db.update(_db.activities)..where((t) => t.syncId.equals(id))).write(
      patch.copyWith(version: Value(row.version + 1), dirty: const Value(true)),
    );
  }
}

class DriftChangeRepository implements ChangeRepository {
  DriftChangeRepository(this._db);
  final AppDatabase _db;

  @override
  Stream<List<ActivityChange>> watchChanges() {
    return (_db.select(_db.activityChanges)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([
            (t) => OrderingTerm.desc(t.changedAt),
            // Same-instant boundaries are vanishingly rare at millisecond
            // resolution, but a tiebreak keeps the order stable across queries.
            (t) => OrderingTerm.desc(t.syncId),
          ]))
        .watch();
  }

  @override
  Future<List<ActivityChange>> loadChanges() {
    return (_db.select(_db.activityChanges)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([
            (t) => OrderingTerm.desc(t.changedAt),
            (t) => OrderingTerm.desc(t.syncId),
          ]))
        .get();
  }

  @override
  Future<ActivityChange?> currentChange() {
    return (_db.select(_db.activityChanges)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([
            (t) => OrderingTerm.desc(t.changedAt),
            (t) => OrderingTerm.desc(t.syncId),
          ])
          ..limit(1))
        .getSingleOrNull();
  }

  @override
  Future<ActivityChange> switchTo(String activityId, {DateTime? at}) async {
    return _db.transaction(() async {
      final change = await _db
          .into(_db.activityChanges)
          .insertReturning(
            ActivityChangesCompanion.insert(
              syncId: _uuid.v4(),
              changedAt: at ?? DateTime.now(),
            ),
          );
      await _db.into(_db.activityChangeActivities).insert(
            ActivityChangeActivitiesCompanion.insert(
              activityChangeId: change.syncId,
              activityId: activityId,
            ),
          );
      return change;
    });
  }

  @override
  Future<void> applyPeerCurrentBlock({
    required String changeSyncId,
    required String activityId,
    required DateTime at,
  }) async {
    await _db.transaction(() async {
      // The activity must exist locally or the join row would break its foreign
      // key. The snapshot carries the tracked activity whole, so the caller has
      // already ensured it — this is the guard for a malformed peer.
      final activity = await (_db.select(_db.activities)
            ..where((t) => t.syncId.equals(activityId)))
          .getSingleOrNull();
      if (activity == null) return;

      final existing = await (_db.select(_db.activityChanges)
            ..where((t) => t.syncId.equals(changeSyncId)))
          .getSingleOrNull();

      if (existing == null) {
        await _db.into(_db.activityChanges).insert(
              ActivityChangesCompanion.insert(syncId: changeSyncId, changedAt: at),
            );
      } else if (existing.changedAt != at) {
        // Adopting a peer's state is not a local edit, so no version bump —
        // same rule as SyncStore, for the same reason.
        await (_db.update(_db.activityChanges)
              ..where((t) => t.syncId.equals(changeSyncId)))
            .write(ActivityChangesCompanion(changedAt: Value(at)));
      }

      final links = await (_db.select(_db.activityChangeActivities)
            ..where((t) => t.activityChangeId.equals(changeSyncId)))
          .get();
      final current = links.map((l) => l.activityId).toList();
      // Only rewrite when the set actually differs, so re-applying an unchanged
      // snapshot does not churn the join table on every push.
      if (current.length == 1 && current.first == activityId) return;

      await (_db.delete(_db.activityChangeActivities)
            ..where((t) => t.activityChangeId.equals(changeSyncId)))
          .go();
      await _db.into(_db.activityChangeActivities).insert(
            ActivityChangeActivitiesCompanion.insert(
              activityChangeId: changeSyncId,
              activityId: activityId,
            ),
          );
    });
  }

  @override
  Future<bool> applyRelayedSwitch({
    required String changeSyncId,
    required String activityId,
    required DateTime at,
  }) async {
    return _db.transaction(() async {
      final existing = await (_db.select(_db.activityChanges)
            ..where((t) => t.syncId.equals(changeSyncId)))
          .getSingleOrNull();
      // Already applied — a duplicate delivery, or our own relay coming back.
      if (existing != null) return false;

      // The activity must exist locally, or the join row would violate its
      // foreign key. A watch tapping a tile it was told about cannot hit this;
      // a stale relay naming a since-deleted activity can.
      final activity = await (_db.select(_db.activities)
            ..where((t) => t.syncId.equals(activityId)))
          .getSingleOrNull();
      if (activity == null) return false;

      await _db.into(_db.activityChanges).insert(
            ActivityChangesCompanion.insert(syncId: changeSyncId, changedAt: at),
          );
      await _db.into(_db.activityChangeActivities).insert(
            ActivityChangeActivitiesCompanion.insert(
              activityChangeId: changeSyncId,
              activityId: activityId,
            ),
            mode: InsertMode.insertOrIgnore,
          );
      return true;
    });
  }

  @override
  Stream<List<ActivityChangeActivity>> watchChangeActivityLinks() {
    return _db.select(_db.activityChangeActivities).watch();
  }

  @override
  Future<void> addActivityToChange(String changeId, String activityId) async {
    await _db.into(_db.activityChangeActivities).insert(
          ActivityChangeActivitiesCompanion.insert(
            activityChangeId: changeId,
            activityId: activityId,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  @override
  Future<void> removeActivityFromChange(String changeId, String activityId) async {
    await _db.transaction(() async {
      final count = await (_db.select(_db.activityChangeActivities)
            ..where((t) => t.activityChangeId.equals(changeId)))
          .get()
          .then((rows) => rows.length);
      // Never strip a block down to an empty set — something is always tracking.
      if (count <= 1) return;
      await (_db.delete(_db.activityChangeActivities)
            ..where((t) =>
                t.activityChangeId.equals(changeId) & t.activityId.equals(activityId)))
          .go();
    });
  }

  @override
  Future<void> setChangeActivity(String changeId, String activityId) async {
    await _db.transaction(() async {
      final change = await (_db.select(_db.activityChanges)
            ..where((t) => t.syncId.equals(changeId)))
          .getSingleOrNull();
      if (change == null) return;

      final activity = await (_db.select(_db.activities)
            ..where((t) => t.syncId.equals(activityId)))
          .getSingleOrNull();
      if (activity == null) return;

      await (_db.delete(_db.activityChangeActivities)
            ..where((t) => t.activityChangeId.equals(changeId)))
          .go();
      await _db.into(_db.activityChangeActivities).insert(
            ActivityChangeActivitiesCompanion.insert(
              activityChangeId: changeId,
              activityId: activityId,
            ),
          );

      // The set is part of the change for sync purposes, so re-pointing it has
      // to bump the change's version or the edit would never leave the device.
      await _bump(changeId, const ActivityChangesCompanion());
    });
  }

  @override
  Future<void> setComment(String changeId, String? comment) =>
      _bump(changeId, ActivityChangesCompanion(comment: Value(comment)));

  @override
  Future<void> setChangedAt(String changeId, DateTime at) =>
      _bump(changeId, ActivityChangesCompanion(changedAt: Value(at)));

  @override
  Future<void> deleteChange(String id) =>
      _bump(id, ActivityChangesCompanion(deletedAt: Value(DateTime.now())));

  @override
  Future<List<String>> activityIdsForChange(String changeId) async {
    final rows = await (_db.select(_db.activityChangeActivities)
          ..where((t) => t.activityChangeId.equals(changeId)))
        .get();
    return rows.map((r) => r.activityId).toList();
  }

  /// See [DriftActivityRepository._bump] — same contract, same reason for
  /// setting `dirty` here rather than at every call site.
  Future<void> _bump(String id, ActivityChangesCompanion patch) async {
    final row = await (_db.select(_db.activityChanges)
          ..where((t) => t.syncId.equals(id)))
        .getSingleOrNull();
    if (row == null) return;
    await (_db.update(_db.activityChanges)..where((t) => t.syncId.equals(id))).write(
      patch.copyWith(version: Value(row.version + 1), dirty: const Value(true)),
    );
  }
}
