import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../domain/calendar.dart';
import '../domain/sync_protocol.dart';
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
      final row = await (_db.select(
        _db.activities,
      )..where((t) => t.syncId.equals(at))).getSingleOrNull();
      cursor = row?.parentId;
    }
    return false;
  }

  @override
  Future<void> touchUsed(String id, DateTime at, {bool push = true}) {
    final patch = ActivitiesCompanion(lastUsedAt: Value(at));
    return push ? _bump(id, patch) : _applyPeer(id, patch);
  }

  @override
  Future<void> ensurePeerActivity(WearActivity activity) async {
    await _db.transaction(() async {
      final existing = await (_db.select(
        _db.activities,
      )..where((t) => t.syncId.equals(activity.syncId))).getSingleOrNull();

      if (existing == null) {
        await _db
            .into(_db.activities)
            .insert(
              ActivitiesCompanion.insert(
                syncId: activity.syncId,
                name: activity.name,
                color: activity.color,
                // `dirty` defaults to true, which is right for a row this device
                // authored and wrong for one it was told about.
                dirty: const Value(false),
                // Deliberately not a bookmark: being tracked is not the same as
                // being pinned to the watch's switch list.
              ),
            );
        return;
      }

      // Only write on a real difference — see applyBookmarkSnapshot.
      if (existing.name != activity.name || existing.color != activity.color) {
        await _applyPeer(
          activity.syncId,
          ActivitiesCompanion(name: Value(activity.name), color: Value(activity.color)),
        );
      }
    });
  }

  @override
  Future<Activity> ensureUnsorted() async {
    return _db.transaction(() async {
      final existing = await (_db.select(
        _db.activities,
      )..where((t) => t.syncId.equals(kUnsortedActivityId))).getSingleOrNull();

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
          return (await (_db.select(
            _db.activities,
          )..where((t) => t.syncId.equals(kUnsortedActivityId))).getSingle());
        }
        return existing;
      }

      return _db
          .into(_db.activities)
          .insertReturning(
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
        final existing = await (_db.select(
          _db.activities,
        )..where((t) => t.syncId.equals(a.syncId))).getSingleOrNull();

        if (existing == null) {
          await _db
              .into(_db.activities)
              .insert(
                ActivitiesCompanion.insert(
                  syncId: a.syncId,
                  name: a.name,
                  color: a.color,
                  bookmarked: const Value(true),
                  // The peer's row, not this device's — see _applyPeer.
                  dirty: const Value(false),
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
          await _applyPeer(
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
      final staleBookmarks = await (_db.select(
        _db.activities,
      )..where((t) => t.bookmarked.equals(true) & t.deletedAt.isNull())).get();
      for (final row in staleBookmarks) {
        if (!incoming.containsKey(row.syncId)) {
          await _applyPeer(row.syncId, const ActivitiesCompanion(bookmarked: Value(false)));
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
    final row = await (_db.select(
      _db.activities,
    )..where((t) => t.syncId.equals(id))).getSingleOrNull();
    if (row == null) return;
    await (_db.update(_db.activities)..where((t) => t.syncId.equals(id))).write(
      patch.copyWith(version: Value(row.version + 1), dirty: const Value(true)),
    );
  }

  /// Apply [patch] as a *peer's* statement rather than this device's edit: no
  /// version bump, and not marked for pushing.
  ///
  /// The counterpart to [_bump], and the rule [applyPeerCurrentBlock] already
  /// follows — "adopting a peer's state is not a local edit". It matters more
  /// now that the watch reaches the server itself: without this it would offer
  /// the server rows that are really the phone's facts, arriving over the relay,
  /// on the device least able to spare the traffic.
  ///
  /// Not a correctness fix. Pushes are version-checked and the content comes
  /// from the phone either way, so the worst case was a redundant write, never
  /// divergence.
  Future<void> _applyPeer(String id, ActivitiesCompanion patch) =>
      (_db.update(_db.activities)..where((t) => t.syncId.equals(id))).write(patch);
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
          ..orderBy([(t) => OrderingTerm.desc(t.changedAt), (t) => OrderingTerm.desc(t.syncId)]))
        .get();
  }

  @override
  Future<ActivityChange?> currentChange() {
    return (_db.select(_db.activityChanges)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.changedAt), (t) => OrderingTerm.desc(t.syncId)])
          ..limit(1))
        .getSingleOrNull();
  }

  @override
  Future<ActivityChange?> changeById(String syncId) {
    return (_db.select(
      _db.activityChanges,
    )..where((t) => t.syncId.equals(syncId))).getSingleOrNull();
  }

  @override
  Future<bool> applyRelayedRetime({
    required String changeSyncId,
    required DateTime at,
    required int version,
    DateTime Function()? clock,
  }) {
    return _db.transaction(() async {
      final existing = await changeById(changeSyncId);
      if (existing == null || !_adopts(existing, version)) return false;

      // Still clamped against *this* device's neighbours, even though the value
      // is being adopted rather than computed. Version says whose answer is
      // newer; it says nothing about whether that answer fits here, and the
      // sender may have been working from a stale snapshot that did not know
      // about a boundary already on the record. A relay must not be able to
      // reorder two blocks.
      //
      // The gap that opens when the two devices clamp differently is closed the
      // way it already was: the phone's next snapshot carries its own answer and
      // applyPeerCurrentBlock re-points the watch onto it.
      final ascending = (await loadChanges()).reversed.toList();
      final i = ascending.indexWhere((c) => c.syncId == changeSyncId);
      if (i < 0) return false;
      final target = clampBoundary(
        desired: at,
        previous: i > 0 ? ascending[i - 1].changedAt : null,
        next: i + 1 < ascending.length ? ascending[i + 1].changedAt : null,
        notAfter: (clock ?? DateTime.now)(),
      );
      // No instant this boundary could legally occupy — refuse outright rather
      // than take the version without the value it stands for.
      if (target == null) return false;

      await (_db.update(_db.activityChanges)..where((t) => t.syncId.equals(changeSyncId))).write(
        ActivityChangesCompanion(
          changedAt: Value(target),
          version: Value(version),
          dirty: _unpushed,
        ),
      );
      return true;
    });
  }

  @override
  Future<bool> applyRelayedAssign({
    required String changeSyncId,
    required String activityId,
    required int version,
  }) {
    return _db.transaction(() async {
      final existing = await changeById(changeSyncId);
      if (existing == null || !_adopts(existing, version)) return false;

      final activity = await (_db.select(
        _db.activities,
      )..where((t) => t.syncId.equals(activityId))).getSingleOrNull();
      if (activity == null) return false;

      await (_db.update(_db.activityChanges)..where((t) => t.syncId.equals(changeSyncId))).write(
        ActivityChangesCompanion(version: Value(version), dirty: _unpushed),
      );
      // Re-pointing replaces the whole set, like assignBlock: a corrected block
      // tracks the one activity named, not that one plus whatever was there.
      await (_db.delete(
        _db.activityChangeActivities,
      )..where((t) => t.activityChangeId.equals(changeSyncId))).go();
      await _db
          .into(_db.activityChangeActivities)
          .insert(
            ActivityChangeActivitiesCompanion.insert(
              activityChangeId: changeSyncId,
              activityId: activityId,
            ),
          );
      return true;
    });
  }

  /// The rule `SyncStore` applies to a pulled row, applied to a relayed one.
  bool _adopts(ActivityChange local, int incomingVersion) =>
      decideIncoming(
        localVersion: local.version,
        remoteVersion: incomingVersion,
        localDirty: local.dirty,
      ) ==
      SyncDecision.adopt;

  /// Adopted, but *not* clean — unlike a pulled row, which is on the server by
  /// definition. This value arrived over the relay and may never have been
  /// anywhere else; on a pair with no account the relay is the only route it
  /// has. Leaving it dirty is what gets it pushed if an account appears later.
  static const _unpushed = Value(true);

  @override
  Future<ActivityChange> switchTo(String activityId, {DateTime? at}) async {
    return _db.transaction(() async {
      final change = await _db
          .into(_db.activityChanges)
          .insertReturning(
            ActivityChangesCompanion.insert(syncId: _uuid.v4(), changedAt: at ?? DateTime.now()),
          );
      await _db
          .into(_db.activityChangeActivities)
          .insert(
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
    required int? version,
  }) async {
    await _db.transaction(() async {
      // The activity must exist locally or the join row would break its foreign
      // key. The snapshot carries the tracked activity whole, so the caller has
      // already ensured it — this is the guard for a malformed peer.
      final activity = await (_db.select(
        _db.activities,
      )..where((t) => t.syncId.equals(activityId))).getSingleOrNull();
      if (activity == null) return;

      final existing = await (_db.select(
        _db.activityChanges,
      )..where((t) => t.syncId.equals(changeSyncId))).getSingleOrNull();

      // The sender's number, not a bump: adopting a peer's state is not a local
      // edit, same rule as SyncStore. Taking it is what makes the two counters
      // comparable at all — a row seeded here at the column default sits below
      // whatever the sender has already reached, and every correction relayed
      // back from this device would then read as stale and be refused for good.
      if (existing == null) {
        await _db
            .into(_db.activityChanges)
            .insert(
              ActivityChangesCompanion.insert(
                syncId: changeSyncId,
                changedAt: at,
                version: version == null ? const Value.absent() : Value(version),
              ),
            );
      } else {
        // Only upwards. A snapshot that crossed with a local correction is
        // behind it, and lowering the version here would drop that correction's
        // rank before it has been relayed.
        final ahead = version != null && version > existing.version ? version : null;
        if (existing.changedAt != at || ahead != null) {
          await (_db.update(
            _db.activityChanges,
          )..where((t) => t.syncId.equals(changeSyncId))).write(
            ActivityChangesCompanion(
              changedAt: Value(at),
              version: ahead == null ? const Value.absent() : Value(ahead),
            ),
          );
        }
      }

      final links = await (_db.select(
        _db.activityChangeActivities,
      )..where((t) => t.activityChangeId.equals(changeSyncId))).get();
      final current = links.map((l) => l.activityId).toList();
      // Only rewrite when the set actually differs, so re-applying an unchanged
      // snapshot does not churn the join table on every push.
      if (current.length == 1 && current.first == activityId) return;

      await (_db.delete(
        _db.activityChangeActivities,
      )..where((t) => t.activityChangeId.equals(changeSyncId))).go();
      await _db
          .into(_db.activityChangeActivities)
          .insert(
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
      final existing = await (_db.select(
        _db.activityChanges,
      )..where((t) => t.syncId.equals(changeSyncId))).getSingleOrNull();
      // Already applied — a duplicate delivery, or our own relay coming back.
      if (existing != null) return false;

      // The activity must exist locally, or the join row would violate its
      // foreign key. A watch tapping a tile it was told about cannot hit this;
      // a stale relay naming a since-deleted activity can.
      final activity = await (_db.select(
        _db.activities,
      )..where((t) => t.syncId.equals(activityId))).getSingleOrNull();
      if (activity == null) return false;

      await _db
          .into(_db.activityChanges)
          .insert(ActivityChangesCompanion.insert(syncId: changeSyncId, changedAt: at));
      await _db
          .into(_db.activityChangeActivities)
          .insert(
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
    await _db.transaction(() async {
      final already =
          await (_db.select(_db.activityChangeActivities)..where(
                (t) => t.activityChangeId.equals(changeId) & t.activityId.equals(activityId),
              ))
              .getSingleOrNull();
      // Already tagged: nothing changed, so nothing to push. Bumping anyway
      // would re-send an identical block every time the sheet was opened.
      if (already != null) return;

      await _db
          .into(_db.activityChangeActivities)
          .insert(
            ActivityChangeActivitiesCompanion.insert(
              activityChangeId: changeId,
              activityId: activityId,
            ),
            mode: InsertMode.insertOrIgnore,
          );
      // The set travels inside the change and the join row carries no version of
      // its own, so without this the tag stays on this device — the same reason
      // setChangeActivity bumps, which this had simply not been given.
      await _bump(changeId, const ActivityChangesCompanion());
    });
  }

  @override
  Future<void> removeActivityFromChange(String changeId, String activityId) async {
    await _db.transaction(() async {
      final count = await (_db.select(
        _db.activityChangeActivities,
      )..where((t) => t.activityChangeId.equals(changeId))).get().then((rows) => rows.length);
      // Never strip a block down to an empty set — something is always tracking.
      if (count <= 1) return;
      final removed = await (_db.delete(
        _db.activityChangeActivities,
      )..where((t) => t.activityChangeId.equals(changeId) & t.activityId.equals(activityId))).go();
      // Only when something actually went. A refused or no-op untag must not
      // dirty the row, or every sync would re-send an unchanged block.
      if (removed == 0) return;
      await _bump(changeId, const ActivityChangesCompanion());
    });
  }

  @override
  Future<void> replaceActivityInChange(String changeId, String from, String to) async {
    await _db.transaction(() async {
      final links = await (_db.select(
        _db.activityChangeActivities,
      )..where((t) => t.activityChangeId.equals(changeId))).get();
      final ids = links.map((l) => l.activityId).toSet();
      // Nothing to swap, or the destination is already here — either way the set
      // would be unchanged, and an unchanged set must not be marked for pushing.
      if (!ids.contains(from) || ids.contains(to)) return;

      final activity = await (_db.select(
        _db.activities,
      )..where((t) => t.syncId.equals(to))).getSingleOrNull();
      if (activity == null) return;

      await (_db.delete(
        _db.activityChangeActivities,
      )..where((t) => t.activityChangeId.equals(changeId) & t.activityId.equals(from))).go();
      await _db
          .into(_db.activityChangeActivities)
          .insert(
            ActivityChangeActivitiesCompanion.insert(activityChangeId: changeId, activityId: to),
            mode: InsertMode.insertOrIgnore,
          );
      // The set is part of the change for sync — same rule as everywhere else.
      await _bump(changeId, const ActivityChangesCompanion());
    });
  }

  @override
  Future<void> setChangeActivity(String changeId, String activityId) async {
    await _db.transaction(() async {
      final change = await (_db.select(
        _db.activityChanges,
      )..where((t) => t.syncId.equals(changeId))).getSingleOrNull();
      if (change == null) return;

      final activity = await (_db.select(
        _db.activities,
      )..where((t) => t.syncId.equals(activityId))).getSingleOrNull();
      if (activity == null) return;

      await (_db.delete(
        _db.activityChangeActivities,
      )..where((t) => t.activityChangeId.equals(changeId))).go();
      await _db
          .into(_db.activityChangeActivities)
          .insert(
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
  Future<bool> swapActivitySets(String changeA, String changeB) async {
    if (changeA == changeB) return false;
    return _db.transaction(() async {
      final a = await (_db.select(
        _db.activityChanges,
      )..where((t) => t.syncId.equals(changeA))).getSingleOrNull();
      final b = await (_db.select(
        _db.activityChanges,
      )..where((t) => t.syncId.equals(changeB))).getSingleOrNull();
      if (a == null || b == null) return false;

      final idsA = await _activityIdsOf(changeA);
      final idsB = await _activityIdsOf(changeB);
      // Same rule as every other write here: a swap that changes nothing must
      // not dirty two rows, or each sync would re-send both blocks unaltered.
      final sameSet = idsA.length == idsB.length && idsA.containsAll(idsB);
      if (sameSet && a.comment == b.comment) return false;

      // Both sides go before either comes back. The join's primary key is
      // {activityChangeId, activityId}, so writing B's ids onto A while A's are
      // still on B collides on any id the two have in common.
      await (_db.delete(
        _db.activityChangeActivities,
      )..where((t) => t.activityChangeId.isIn([changeA, changeB]))).go();
      await _link(changeA, idsB);
      await _link(changeB, idsA);

      // The comment describes the activity, so it travels with it. A note about
      // a call left on the block that no longer tracks the call is the same
      // error this action exists to correct.
      await _bump(changeA, ActivityChangesCompanion(comment: Value(b.comment)));
      await _bump(changeB, ActivityChangesCompanion(comment: Value(a.comment)));
      return true;
    });
  }

  Future<Set<String>> _activityIdsOf(String changeId) async {
    final links = await (_db.select(
      _db.activityChangeActivities,
    )..where((t) => t.activityChangeId.equals(changeId))).get();
    return links.map((l) => l.activityId).toSet();
  }

  Future<void> _link(String changeId, Set<String> activityIds) async {
    for (final id in activityIds) {
      await _db
          .into(_db.activityChangeActivities)
          .insert(
            ActivityChangeActivitiesCompanion.insert(activityChangeId: changeId, activityId: id),
            mode: InsertMode.insertOrIgnore,
          );
    }
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
    final rows = await (_db.select(
      _db.activityChangeActivities,
    )..where((t) => t.activityChangeId.equals(changeId))).get();
    return rows.map((r) => r.activityId).toList();
  }

  /// See [DriftActivityRepository._bump] — same contract, same reason for
  /// setting `dirty` here rather than at every call site.
  Future<void> _bump(String id, ActivityChangesCompanion patch) async {
    final row = await (_db.select(
      _db.activityChanges,
    )..where((t) => t.syncId.equals(id))).getSingleOrNull();
    if (row == null) return;
    await (_db.update(_db.activityChanges)..where((t) => t.syncId.equals(id))).write(
      patch.copyWith(version: Value(row.version + 1), dirty: const Value(true)),
    );
  }
}
