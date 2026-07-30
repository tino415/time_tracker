// Schema migration: v1 stored `activity_changes.changed_at` as unix *seconds*
// (drift's dateTime() default); v2 stores epoch millis so timeline boundaries
// inside the same second stay ordered. Builds a v1 database by hand, then lets
// drift upgrade it.

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:time_tracker/data/database.dart';

void main() {
  test('v1 -> v2 rescales changed_at from seconds to milliseconds', () async {
    final dir = await Directory.systemTemp.createTemp('time_tracker_migration');
    final file = File('${dir.path}/db.sqlite');
    addTearDown(() => dir.delete(recursive: true));

    final at = DateTime(2026, 1, 5, 9, 30); // whole second, so the rescale is exact

    // The v1 shape of the table (identical DDL — only the stored unit changed).
    final v1 = sqlite3.open(file.path);
    v1.execute('''
      CREATE TABLE activity_changes (
        sync_id TEXT NOT NULL,
        changed_at INTEGER NOT NULL,
        comment TEXT NULL,
        version INTEGER NOT NULL DEFAULT 1,
        deleted_at INTEGER NULL,
        PRIMARY KEY (sync_id)
      );
    ''');
    v1.execute('INSERT INTO activity_changes (sync_id, changed_at) VALUES (?, ?)', [
      'c1',
      at.millisecondsSinceEpoch ~/ 1000,
    ]);
    v1.execute('PRAGMA user_version = 1');
    v1.close();

    final db = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(db.close);

    final rows = await db.select(db.activityChanges).get();
    expect(rows.single.changedAt, at);
  });
}
