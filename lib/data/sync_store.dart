import 'package:drift/drift.dart';

import '../domain/sync_protocol.dart';
import 'database.dart';

/// Database access for the sync engine: what still needs pushing, how to adopt
/// what came back, and where the cursor is.
///
/// Separate from the feature repositories on purpose. Those model what the app
/// *does*; this models what the wire needs, and it is the only place allowed to
/// write a row without bumping its version — adopting a remote row must not
/// look like a local edit, or two devices would ratchet each other's versions
/// upward forever.
class SyncStore {
  SyncStore(this._db);
  final AppDatabase _db;

  static const _cursorKey = 'cursor';
  static const _backendKey = 'backend';
  static const _tokenKey = 'token';

  /// The sync token, or null when this device has not joined an account.
  ///
  /// Stored rather than compiled in: a token baked into a web build is served to
  /// anyone who loads the page, and it has to differ per account anyway.
  Future<String?> token() async {
    final row = await (_db.select(_db.syncMeta)
          ..where((t) => t.key.equals(_tokenKey)))
        .getSingleOrNull();
    final value = row?.value ?? '';
    return value.isEmpty ? null : value;
  }

  Future<void> setToken(String? token) async {
    if (token == null || token.isEmpty) {
      await (_db.delete(_db.syncMeta)..where((t) => t.key.equals(_tokenKey))).go();
      return;
    }
    await _db.into(_db.syncMeta).insertOnConflictUpdate(
          SyncMetaCompanion.insert(key: _tokenKey, value: token),
        );
  }

  /// Re-point this device at [backend], clearing sync state if it changed.
  ///
  /// A cursor is a position in *one server's* sequence and `dirty` records what
  /// *that* server has accepted; neither means anything against a different
  /// backend. Carrying them over is silently destructive — the client asks for
  /// rows after a sequence number the new server has never issued, and considers
  /// its own rows already delivered, so it pushes nothing and pulls nothing and
  /// reports a perfectly healthy "0 up, 0 down".
  ///
  /// Returns whether a reset happened.
  Future<bool> adoptBackend(String backend) async {
    final row = await (_db.select(_db.syncMeta)
          ..where((t) => t.key.equals(_backendKey)))
        .getSingleOrNull();
    if (row?.value == backend) return false;

    await _db.transaction(() async {
      // Everything must be offered to the new server, including rows the old one
      // had. Marking them dirty is safe even when the new server already has
      // them: the push is version-checked, and an identical version is accepted
      // rather than duplicated.
      await _db.update(_db.activities).write(
            const ActivitiesCompanion(dirty: Value(true)),
          );
      await _db.update(_db.activityChanges).write(
            const ActivityChangesCompanion(dirty: Value(true)),
          );
      await (_db.delete(_db.syncMeta)..where((t) => t.key.equals(_cursorKey))).go();
      await _db.into(_db.syncMeta).insertOnConflictUpdate(
            SyncMetaCompanion.insert(key: _backendKey, value: backend),
          );
    });
    return true;
  }

  Future<String?> cursor() async {
    final row = await (_db.select(_db.syncMeta)
          ..where((t) => t.key.equals(_cursorKey)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> setCursor(String cursor) async {
    await _db.into(_db.syncMeta).insertOnConflictUpdate(
          SyncMetaCompanion.insert(key: _cursorKey, value: cursor),
        );
  }

  /// Local rows the server has not accepted yet.
  Future<List<ActivityDto>> pendingActivities() async {
    final rows = await (_db.select(_db.activities)
          ..where((t) => t.dirty.equals(true)))
        .get();
    return [for (final r in rows) _toActivityDto(r)];
  }

  Future<List<ChangeDto>> pendingChanges() async {
    final rows = await (_db.select(_db.activityChanges)
          ..where((t) => t.dirty.equals(true)))
        .get();
    return [
      for (final r in rows)
        ChangeDto(
          syncId: r.syncId,
          changedAt: r.changedAt,
          comment: r.comment,
          version: r.version,
          deletedAt: r.deletedAt,
          activityIds: await _activityIdsFor(r.syncId),
        ),
    ];
  }

  /// Clear the dirty flag for rows the server accepted — but only if the row has
  /// not been edited again since it was read. Comparing the version we pushed
  /// against the row now is what makes a sync concurrent with a local edit safe:
  /// without it, an edit made mid-flight would be marked clean and never pushed.
  Future<void> markSynced({
    required Map<String, int> activityVersions,
    required Map<String, int> changeVersions,
  }) async {
    await _db.transaction(() async {
      for (final entry in activityVersions.entries) {
        await (_db.update(_db.activities)
              ..where((t) => t.syncId.equals(entry.key) & t.version.equals(entry.value)))
            .write(const ActivitiesCompanion(dirty: Value(false)));
      }
      for (final entry in changeVersions.entries) {
        await (_db.update(_db.activityChanges)
              ..where((t) => t.syncId.equals(entry.key) & t.version.equals(entry.value)))
            .write(const ActivityChangesCompanion(dirty: Value(false)));
      }
    });
  }

  /// Adopt a remote activity if it wins under [decideIncoming]. Returns whether
  /// it was taken.
  Future<bool> applyRemoteActivity(ActivityDto dto) async {
    return _db.transaction(() async {
      final local = await (_db.select(_db.activities)
            ..where((t) => t.syncId.equals(dto.syncId)))
          .getSingleOrNull();

      if (local != null) {
        final decision = decideIncoming(
          localVersion: local.version,
          remoteVersion: dto.version,
          localDirty: local.dirty,
        );
        if (decision == SyncDecision.keep) return false;
      }

      // Written verbatim, version included, and *not* dirty: this is the
      // server's row, not an edit of ours.
      await _db.into(_db.activities).insertOnConflictUpdate(
            ActivitiesCompanion.insert(
              syncId: dto.syncId,
              name: dto.name,
              color: dto.color,
              parentId: Value(dto.parentId),
              bookmarked: Value(dto.bookmarked),
              lastUsedAt: Value(dto.lastUsedAt),
              externalId: Value(dto.externalId),
              version: Value(dto.version),
              deletedAt: Value(dto.deletedAt),
              dirty: const Value(false),
            ),
          );
      return true;
    });
  }

  Future<bool> applyRemoteChange(ChangeDto dto) async {
    return _db.transaction(() async {
      final local = await (_db.select(_db.activityChanges)
            ..where((t) => t.syncId.equals(dto.syncId)))
          .getSingleOrNull();

      if (local != null) {
        final decision = decideIncoming(
          localVersion: local.version,
          remoteVersion: dto.version,
          localDirty: local.dirty,
        );
        if (decision == SyncDecision.keep) return false;
      }

      await _db.into(_db.activityChanges).insertOnConflictUpdate(
            ActivityChangesCompanion.insert(
              syncId: dto.syncId,
              changedAt: dto.changedAt,
              comment: Value(dto.comment),
              version: Value(dto.version),
              deletedAt: Value(dto.deletedAt),
              dirty: const Value(false),
            ),
          );

      // The set travels with its change, so it is replaced wholesale — a
      // diff would leave a stale membership if a tag was removed remotely.
      // Links naming an activity this device has never seen are skipped rather
      // than failing the whole change: the activity may arrive in a later page,
      // and the next sync will fill it in.
      await (_db.delete(_db.activityChangeActivities)
            ..where((t) => t.activityChangeId.equals(dto.syncId)))
          .go();
      for (final activityId in dto.activityIds) {
        final exists = await (_db.select(_db.activities)
              ..where((t) => t.syncId.equals(activityId)))
            .getSingleOrNull();
        if (exists == null) continue;
        await _db.into(_db.activityChangeActivities).insert(
              ActivityChangeActivitiesCompanion.insert(
                activityChangeId: dto.syncId,
                activityId: activityId,
              ),
              mode: InsertMode.insertOrIgnore,
            );
      }
      return true;
    });
  }

  Future<List<String>> _activityIdsFor(String changeId) async {
    final rows = await (_db.select(_db.activityChangeActivities)
          ..where((t) => t.activityChangeId.equals(changeId)))
        .get();
    return [for (final r in rows) r.activityId];
  }

  ActivityDto _toActivityDto(Activity r) => ActivityDto(
        syncId: r.syncId,
        parentId: r.parentId,
        name: r.name,
        color: r.color,
        bookmarked: r.bookmarked,
        lastUsedAt: r.lastUsedAt,
        externalId: r.externalId,
        version: r.version,
        deletedAt: r.deletedAt,
      );
}
