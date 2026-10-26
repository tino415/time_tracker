import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

// The change-point / event-log data model (see ~/org/todo.org
// "Time-activity tracking app" → Data model). Every table is keyed by a uuid
// `syncId` string — the same identity used locally, across the (future) Wear
// bridge, and on the (future) sync backend, so no id synthesis is needed.
// `activity` and `activity_change` carry `version` + `deletedAt` for
// version-LWW + tombstone sync layered on later.

/// Catalogue of activities, an arbitrary-depth tree via [parentId]
/// (Work > Client > Task; a work task is just a leaf). Bookmarked activities
/// populate the quick-switch grid and the watch's predefined set.
class Activities extends Table {
  TextColumn get syncId => text()();

  /// Parent in the hierarchy, or null for a top-level activity. Self-FK.
  /// Soft-delete (see [deletedAt]) is the norm, so this cascade only bites on
  /// a genuine hard delete.
  TextColumn get parentId =>
      text().nullable().references(Activities, #syncId, onDelete: KeyAction.cascade)();

  TextColumn get name => text()();

  /// Concrete hex colour (e.g. `#4F8FEE`) on every node — pre-filled from the
  /// parent on creation but editable.
  TextColumn get color => text()();

  BoolColumn get bookmarked => boolean().withDefault(const Constant(false))();

  /// Recency, for last-used-first autocomplete when picking/pasting a task.
  DateTimeColumn get lastUsedAt => dateTime().nullable()();

  /// Optional pasted work-tracker id (e.g. `CU-1042`) for a leaf task.
  TextColumn get externalId => text().nullable()();

  /// Other words the activity is searched by.
  TextColumn get aliases =>
      text().map(const AliasListConverter()).withDefault(const Constant('[]'))();

  IntColumn get version => integer().withDefault(const Constant(1))();

  /// Non-null marks a tombstone: archived/deleted at this instant, row kept
  /// (with bumped [version]) so the deletion participates in version-LWW sync.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  /// Set by every local write, cleared once the server has accepted the row.
  ///
  /// This is what "needs pushing" means — an `updatedAt > lastSync` comparison
  /// would be at the mercy of clock skew between devices, and a row edited while
  /// a sync was in flight would be missed.
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {syncId};
}

/// Sync bookkeeping: the server cursor, and anything else that is about the
/// *connection* rather than the data. One row per key.
class SyncMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Stores a [DateTime] as epoch **milliseconds**.
///
/// Drift's own `dateTime()` column stores unix *seconds*, which is too coarse
/// for a timeline boundary: two switches inside the same second would compare
/// equal, leaving "which block is current" and the timeline order ambiguous.
/// Epoch millis sort exactly as integers (unlike ISO text with a UTC offset,
/// whose lexicographic order breaks across a DST change) and are also what a
/// sync DTO would carry.
class EpochMillisConverter extends TypeConverter<DateTime, int> {
  const EpochMillisConverter();

  @override
  DateTime fromSql(int fromDb) => DateTime.fromMillisecondsSinceEpoch(fromDb);

  @override
  int toSql(DateTime value) => value.millisecondsSinceEpoch;
}

class AliasListConverter extends TypeConverter<List<String>, String> {
  const AliasListConverter();

  @override
  List<String> fromSql(String fromDb) => List<String>.from(jsonDecode(fromDb) as List);

  @override
  String toSql(List<String> value) => jsonEncode(value);
}

/// A switch event — one boundary on the timeline. The block that starts here
/// runs until the next change; its active set is the joined [Activities]. A
/// single [comment] annotates the whole block.
class ActivityChanges extends Table {
  TextColumn get syncId => text()();

  /// The boundary instant, epoch millis (see [EpochMillisConverter]).
  IntColumn get changedAt => integer().map(const EpochMillisConverter())();
  TextColumn get comment => text().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  /// See [Activities.dirty].
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {syncId};
}

/// m:n — which activities are active from a change until the next. Usually one;
/// more than one is the retrospective "forgot to switch" annotation (time is
/// even-split among them for reporting). The join is owned by its change (it
/// travels inside a ChangeUpsert), so it has no independent version.
class ActivityChangeActivities extends Table {
  TextColumn get activityChangeId =>
      text().references(ActivityChanges, #syncId, onDelete: KeyAction.cascade)();
  TextColumn get activityId =>
      text().references(Activities, #syncId, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {activityChangeId, activityId};
}

/// Relay messages this device could not deliver, kept until the peer is back.
///
/// The counterpart to the *inbound* queue in `WearQueue.kt`, and deliberately
/// not its mirror image: that one is native because its writer is native — the
/// listener service runs with no Flutter engine and cannot reach Drift. This
/// one is written and drained from Dart while the app is running, so a native
/// queue would cost two channel hops and every test that can be written against
/// it.
///
/// [collapseKey] is what bounds the table semantically rather than by age. A
/// correction states the sender's whole answer for one boundary, so only the
/// newest per boundary is worth keeping; a switch is a distinct event and
/// carries a null key, so every one survives.
class WearOutbox extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// [WearMessage.type], and [payload] is its `toPayload()` as JSON.
  TextColumn get type => text()();
  TextColumn get payload => text()();

  /// Null keeps every entry; otherwise a new entry replaces the one it matches.
  TextColumn get collapseKey => text().nullable()();
}

@DriftDatabase(
  tables: [Activities, ActivityChanges, ActivityChangeActivities, SyncMeta, WearOutbox],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // v1 stored changed_at as unix *seconds* (drift's dateTime() default);
        // v2 stores epoch millis. Column type is unchanged (INTEGER), so this is
        // a pure data conversion.
        await customStatement('UPDATE activity_changes SET changed_at = changed_at * 1000');
      }
      if (from < 3) {
        // Sync bookkeeping. Everything already on the device predates any
        // server, so it all starts dirty and gets pushed on the first sync.
        await m.addColumn(activities, activities.dirty);
        await m.addColumn(activityChanges, activityChanges.dirty);
        await m.createTable(syncMeta);
      }
      if (from < 4) {
        // Purely additive: an empty outbox is the same as not having one, so
        // there is nothing to backfill. Anything the watch failed to relay
        // before this upgrade was already dropped and cannot be recovered.
        await m.createTable(wearOutbox);
      }
      if (from < 5) {
        await m.addColumn(activities, activities.aliases);
      }
    },
    beforeOpen: (details) async {
      // Drift / sqlite3 do not enable FKs by default; without this the
      // ON DELETE cascades silently no-op.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  static QueryExecutor _openConnection() => driftDatabase(
    name: 'time_tracker',
    // Web keeps a local DB too (offline-first PWA) via wasm/OPFS — these
    // assets live in web/. Requires COOP/COEP headers when served (phase: PWA).
    web: DriftWebOptions(
      sqlite3Wasm: Uri.parse('sqlite3.wasm'),
      driftWorker: Uri.parse('drift_worker.js'),
    ),
  );
}
