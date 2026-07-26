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
  TextColumn get parentId => text()
      .nullable()
      .references(Activities, #syncId, onDelete: KeyAction.cascade)();

  TextColumn get name => text()();

  /// Concrete hex colour (e.g. `#4F8FEE`) on every node — pre-filled from the
  /// parent on creation but editable.
  TextColumn get color => text()();

  BoolColumn get bookmarked => boolean().withDefault(const Constant(false))();

  /// Recency, for last-used-first autocomplete when picking/pasting a task.
  DateTimeColumn get lastUsedAt => dateTime().nullable()();

  /// Optional pasted work-tracker id (e.g. `CU-1042`) for a leaf task.
  TextColumn get externalId => text().nullable()();

  IntColumn get version => integer().withDefault(const Constant(1))();

  /// Non-null marks a tombstone: archived/deleted at this instant, row kept
  /// (with bumped [version]) so the deletion participates in version-LWW sync.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {syncId};
}

/// A switch event — one boundary on the timeline. The block that starts here
/// runs until the next change; its active set is the joined [Activities]. A
/// single [comment] annotates the whole block.
class ActivityChanges extends Table {
  TextColumn get syncId => text()();
  DateTimeColumn get changedAt => dateTime()();
  TextColumn get comment => text().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {syncId};
}

/// m:n — which activities are active from a change until the next. Usually one;
/// more than one is the retrospective "forgot to switch" annotation (time is
/// even-split among them for reporting). The join is owned by its change (it
/// travels inside a ChangeUpsert), so it has no independent version.
class ActivityChangeActivities extends Table {
  TextColumn get activityChangeId => text()
      .references(ActivityChanges, #syncId, onDelete: KeyAction.cascade)();
  TextColumn get activityId =>
      text().references(Activities, #syncId, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {activityChangeId, activityId};
}

@DriftDatabase(
  tables: [Activities, ActivityChanges, ActivityChangeActivities],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
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
