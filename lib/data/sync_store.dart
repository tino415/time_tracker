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
  static const _tokenVersionKey = 'token_version';

  /// The sync token, or null when this device has not joined an account.
  ///
  /// Stored rather than compiled in: a token baked into a web build is served to
  /// anyone who loads the page, and it has to differ per account anyway.
  Future<String?> token() async {
    final row = await (_db.select(
      _db.syncMeta,
    )..where((t) => t.key.equals(_tokenKey))).getSingleOrNull();
    final value = row?.value ?? '';
    return value.isEmpty ? null : value;
  }

  /// The same value, as a stream.
  ///
  /// The token can now arrive from somewhere other than this device's own UI —
  /// the phone hands it to the watch over the Wear relay — so whether sync is
  /// configured has to be something the app *observes* rather than reads once at
  /// startup. Without this the watch would store a token and go on believing it
  /// had none until the next launch.
  Stream<String?> watchToken() {
    return (_db.select(
      _db.syncMeta,
    )..where((t) => t.key.equals(_tokenKey))).watchSingleOrNull().map((row) {
      final value = row?.value ?? '';
      return value.isEmpty ? null : value;
    });
  }

  /// How many times this account has been granted or revoked, anywhere.
  ///
  /// The credential is the one thing that cannot travel through the sync server,
  /// because it is what grants access to it — so it moves over the Wear relay
  /// instead, and needs its own ordering rule there. A version gives it the same
  /// one the rest of the data model uses: newest wins.
  ///
  /// It never reaches the server. [SyncRequest] carries a cursor, activities and
  /// changes and has no field for anything else, so `sync_meta` is structurally
  /// local — the isolation is by construction rather than by a rule someone has
  /// to remember, which is why the token has always lived here too.
  ///
  /// 0 means "never set", which is what a device that has never heard of an
  /// account reports.
  Future<int> credentialVersion() async {
    final row = await (_db.select(
      _db.syncMeta,
    )..where((t) => t.key.equals(_tokenVersionKey))).getSingleOrNull();
    return int.tryParse(row?.value ?? '') ?? 0;
  }

  /// Take a peer's credential at *its* version, without inventing a new one.
  ///
  /// The counterpart to [grantCredential], and the same split as `_applyPeer`
  /// against `_bump` in the repositories: adopting somebody else's state is not
  /// an edit, so it must not look newer than what it came from.
  Future<void> adoptCredential(String? token, int version) => _writeCredential(token, version);

  /// Set the credential *here*, stamping it a version nothing has used yet.
  ///
  /// Revoking is a grant of null rather than an absence — a revocation has to
  /// travel and win like any other change, and something that is merely missing
  /// cannot do either.
  Future<int> grantCredential(String? token) async {
    final next = await credentialVersion() + 1;
    await _writeCredential(token, next);
    return next;
  }

  Future<void> _writeCredential(String? token, int version) async {
    await _db.transaction(() async {
      if (token == null || token.isEmpty) {
        await (_db.delete(_db.syncMeta)..where((t) => t.key.equals(_tokenKey))).go();
      } else {
        await _db
            .into(_db.syncMeta)
            .insertOnConflictUpdate(SyncMetaCompanion.insert(key: _tokenKey, value: token));
      }
      await _db
          .into(_db.syncMeta)
          .insertOnConflictUpdate(
            SyncMetaCompanion.insert(key: _tokenVersionKey, value: '$version'),
          );
    });
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
    final row = await (_db.select(
      _db.syncMeta,
    )..where((t) => t.key.equals(_backendKey))).getSingleOrNull();
    if (row?.value == backend) return false;

    await _db.transaction(() async {
      // Everything must be offered to the new server, including rows the old one
      // had. Marking them dirty is safe even when the new server already has
      // them: the push is version-checked, and an identical version is accepted
      // rather than duplicated.
      await _db.update(_db.activities).write(const ActivitiesCompanion(dirty: Value(true)));
      await _db
          .update(_db.activityChanges)
          .write(const ActivityChangesCompanion(dirty: Value(true)));
      await (_db.delete(_db.syncMeta)..where((t) => t.key.equals(_cursorKey))).go();
      await _db
          .into(_db.syncMeta)
          .insertOnConflictUpdate(SyncMetaCompanion.insert(key: _backendKey, value: backend));
    });
    return true;
  }

  Future<String?> cursor() async {
    final row = await (_db.select(
      _db.syncMeta,
    )..where((t) => t.key.equals(_cursorKey))).getSingleOrNull();
    return row?.value;
  }

  Future<void> setCursor(String cursor) async {
    await _db
        .into(_db.syncMeta)
        .insertOnConflictUpdate(SyncMetaCompanion.insert(key: _cursorKey, value: cursor));
  }

  /// Local rows the server has not accepted yet.
  Future<List<ActivityDto>> pendingActivities() async {
    final rows = await (_db.select(_db.activities)..where((t) => t.dirty.equals(true))).get();
    return [for (final r in rows) _toActivityDto(r)];
  }

  Future<List<ChangeDto>> pendingChanges() async {
    final rows = await (_db.select(_db.activityChanges)..where((t) => t.dirty.equals(true))).get();
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

  /// Adopt a page of remote activities as one unit. Returns how many were taken.
  ///
  /// One transaction, with foreign keys deferred to the commit, because the
  /// server's order cannot satisfy them row by row. `seq` is assigned on write,
  /// so editing a *parent* after its child gives the parent the higher seq and
  /// the child arrives first — and a child inserted before its parent exists is
  /// a foreign key violation. That threw out of the apply loop before the cursor
  /// moved, so every later sync replayed the same page, hit the same row and
  /// failed the same way: a device stuck on one seq forever, still pushing its
  /// own rows and never receiving any. Deferring the check to the commit makes
  /// the *page* the unit of consistency, which is what it always was.
  ///
  /// A parent split across a page boundary would still fail — the whole batch
  /// rolls back rather than committing something inconsistent. That needs the
  /// server to page on a parents-first order, and has not happened here: a page
  /// is [MAX_PAGE] rows.
  Future<int> applyRemoteActivities(Iterable<ActivityDto> dtos) async {
    return _db.transaction(() async {
      await _db.customStatement('PRAGMA defer_foreign_keys = ON');
      var applied = 0;
      for (final dto in dtos) {
        if (await applyRemoteActivity(dto)) applied++;
      }
      return applied;
    });
  }

  /// Adopt a remote activity if it wins under [decideIncoming]. Returns whether
  /// it was taken.
  ///
  /// Prefer [applyRemoteActivities] for anything the server sent: applied alone,
  /// this enforces foreign keys immediately and so depends on delivery order.
  Future<bool> applyRemoteActivity(ActivityDto dto) async {
    return _db.transaction(() async {
      final local = await (_db.select(
        _db.activities,
      )..where((t) => t.syncId.equals(dto.syncId))).getSingleOrNull();

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
      await _db
          .into(_db.activities)
          .insertOnConflictUpdate(
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
      final local = await (_db.select(
        _db.activityChanges,
      )..where((t) => t.syncId.equals(dto.syncId))).getSingleOrNull();

      if (local != null) {
        final decision = decideIncoming(
          localVersion: local.version,
          remoteVersion: dto.version,
          localDirty: local.dirty,
        );
        if (decision == SyncDecision.keep) return false;
      }

      await _db
          .into(_db.activityChanges)
          .insertOnConflictUpdate(
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
      await (_db.delete(
        _db.activityChangeActivities,
      )..where((t) => t.activityChangeId.equals(dto.syncId))).go();
      for (final activityId in dto.activityIds) {
        final exists = await (_db.select(
          _db.activities,
        )..where((t) => t.syncId.equals(activityId))).getSingleOrNull();
        if (exists == null) continue;
        await _db
            .into(_db.activityChangeActivities)
            .insert(
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
    final rows = await (_db.select(
      _db.activityChangeActivities,
    )..where((t) => t.activityChangeId.equals(changeId))).get();
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
