import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

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
  Future<void> touchUsed(String id, DateTime at) =>
      _bump(id, ActivitiesCompanion(lastUsedAt: Value(at)));

  @override
  Future<void> deleteActivity(String id) =>
      _bump(id, ActivitiesCompanion(deletedAt: Value(DateTime.now())));

  /// Apply [patch] to one activity, bumping [Activities.version] for LWW sync.
  Future<void> _bump(String id, ActivitiesCompanion patch) async {
    final row = await (_db.select(_db.activities)
          ..where((t) => t.syncId.equals(id)))
        .getSingleOrNull();
    if (row == null) return;
    await (_db.update(_db.activities)..where((t) => t.syncId.equals(id)))
        .write(patch.copyWith(version: Value(row.version + 1)));
  }
}

class DriftChangeRepository implements ChangeRepository {
  DriftChangeRepository(this._db);
  final AppDatabase _db;

  @override
  Stream<List<ActivityChange>> watchChanges() {
    return (_db.select(_db.activityChanges)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.changedAt)]))
        .watch();
  }

  @override
  Future<ActivityChange?> currentChange() {
    return (_db.select(_db.activityChanges)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.changedAt)])
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

  Future<void> _bump(String id, ActivityChangesCompanion patch) async {
    final row = await (_db.select(_db.activityChanges)
          ..where((t) => t.syncId.equals(id)))
        .getSingleOrNull();
    if (row == null) return;
    await (_db.update(_db.activityChanges)..where((t) => t.syncId.equals(id)))
        .write(patch.copyWith(version: Value(row.version + 1)));
  }
}
