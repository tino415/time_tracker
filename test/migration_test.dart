// Schema migrations, exercised by building an old database by hand and letting
// drift upgrade it. Cheap to write and the only thing that catches a migration
// that works on a fresh install but not on a real device's existing data.
//
//   v1 -> v2  activity_changes.changed_at moved from unix seconds to epoch
//             millis, so boundaries inside the same second stay ordered.
//   v2 -> v3  sync bookkeeping: a `dirty` flag on both syncable tables and the
//             sync_meta table holding the server cursor.

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:time_tracker/data/database.dart';

/// The v1 shape of the schema. Later migrations run over *all* of it, so it has
/// to be complete — a partial fixture would pass a migration that fails on a
/// real device.
const _v1Schema = '''
  CREATE TABLE activities (
    sync_id TEXT NOT NULL,
    parent_id TEXT NULL REFERENCES activities (sync_id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    color TEXT NOT NULL,
    bookmarked INTEGER NOT NULL DEFAULT 0,
    last_used_at INTEGER NULL,
    external_id TEXT NULL,
    version INTEGER NOT NULL DEFAULT 1,
    deleted_at INTEGER NULL,
    PRIMARY KEY (sync_id)
  );
  CREATE TABLE activity_changes (
    sync_id TEXT NOT NULL,
    changed_at INTEGER NOT NULL,
    comment TEXT NULL,
    version INTEGER NOT NULL DEFAULT 1,
    deleted_at INTEGER NULL,
    PRIMARY KEY (sync_id)
  );
  CREATE TABLE activity_change_activities (
    activity_change_id TEXT NOT NULL REFERENCES activity_changes (sync_id) ON DELETE CASCADE,
    activity_id TEXT NOT NULL REFERENCES activities (sync_id) ON DELETE CASCADE,
    PRIMARY KEY (activity_change_id, activity_id)
  );
''';

/// Writes a v1 database with one activity and one change, and returns the file.
File _writeV1(Directory dir, DateTime at) {
  final file = File('${dir.path}/db.sqlite');
  final v1 = sqlite3.open(file.path);
  v1.execute(_v1Schema);
  v1.execute(
    'INSERT INTO activities (sync_id, name, color) VALUES (?, ?, ?)',
    ['a1', 'Deep work', '#4F8FEE'],
  );
  v1.execute(
    'INSERT INTO activity_changes (sync_id, changed_at) VALUES (?, ?)',
    ['c1', at.millisecondsSinceEpoch ~/ 1000], // v1 stored seconds
  );
  v1.execute('INSERT INTO activity_change_activities VALUES (?, ?)', ['c1', 'a1']);
  v1.execute('PRAGMA user_version = 1');
  v1.close();
  return file;
}

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('time_tracker_migration');
  });

  tearDown(() => dir.delete(recursive: true));

  test('v1 -> v3 rescales changed_at from seconds to milliseconds', () async {
    final at = DateTime(2026, 1, 5, 9, 30); // whole second, so the rescale is exact
    final db = AppDatabase.forTesting(NativeDatabase(_writeV1(dir, at)));
    addTearDown(db.close);

    final rows = await db.select(db.activityChanges).get();
    expect(rows.single.changedAt, at);
  });

  test('v1 -> v3 adds sync bookkeeping, with existing rows pending', () async {
    final db = AppDatabase.forTesting(NativeDatabase(_writeV1(dir, DateTime(2026, 1, 5, 9))));
    addTearDown(db.close);

    // Everything that predates the sync feature has never reached a server, so
    // it has to start dirty or it would never be pushed.
    expect((await db.select(db.activities).getSingle()).dirty, isTrue);
    expect((await db.select(db.activityChanges).getSingle()).dirty, isTrue);

    // The cursor table exists and is empty — a first sync pulls everything.
    expect(await db.select(db.syncMeta).get(), isEmpty);
  });

  test('the upgrade preserves the data it migrates', () async {
    final db = AppDatabase.forTesting(NativeDatabase(_writeV1(dir, DateTime(2026, 1, 5, 9))));
    addTearDown(db.close);

    final activity = await db.select(db.activities).getSingle();
    expect(activity.name, 'Deep work');
    expect(activity.color, '#4F8FEE');
    expect(activity.version, 1);

    // The join survives too — a migration that dropped it would silently empty
    // every block on the timeline.
    final links = await db.select(db.activityChangeActivities).get();
    expect(links.single.activityChangeId, 'c1');
    expect(links.single.activityId, 'a1');
  });
}
