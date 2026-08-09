// Pure-domain unit tests: no plugins / no DB, so the suite runs anywhere.
// Covers block derivation, per-category roll-up (even-split + tree), CSV export,
// the activity tree, pasted-task parsing, and typed time-of-day parsing.

import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/format.dart';
import 'package:time_tracker/domain/activity_tree.dart';
import 'package:time_tracker/domain/block.dart';
import 'package:time_tracker/domain/csv_export.dart';
import 'package:time_tracker/domain/reporting.dart';
import 'package:time_tracker/domain/task_paste.dart';

Activity act(String id, String name, {String? parent, String color = '#4F8FEE'}) => Activity(
      syncId: id,
      parentId: parent,
      name: name,
      color: color,
      bookmarked: false,
      version: 1,
      dirty: false,
    );

ActivityChange chg(String id, DateTime at, {String? comment}) => ActivityChange(
      syncId: id,
      changedAt: at,
      comment: comment,
      version: 1,
      dirty: false,
    );

DateTime d(int hour, [int minute = 0]) => DateTime(2026, 1, 5, hour, minute); // Mon

void main() {
  group('deriveBlocks', () {
    final a = act('a', 'Alpha');
    final b = act('b', 'Beta');
    final byId = {'a': a, 'b': b};

    test('consecutive changes become closed blocks, newest open block first', () {
      final blocks = deriveBlocks(
        changes: [chg('c1', d(9)), chg('c2', d(10))],
        activityIdsByChange: {
          'c1': ['a'],
          'c2': ['b'],
        },
        activitiesById: byId,
      );

      expect(blocks.length, 2);
      // newest first
      expect(blocks[0].change.syncId, 'c2');
      expect(blocks[0].isOpen, isTrue);
      expect(blocks[0].activities.single.syncId, 'b');

      expect(blocks[1].change.syncId, 'c1');
      expect(blocks[1].isOpen, isFalse);
      expect(blocks[1].end, d(10));
      expect(blocks[1].duration(d(12)), const Duration(hours: 1));
    });

    test('open block measures up to now', () {
      final blocks = deriveBlocks(
        changes: [chg('c1', d(9))],
        activityIdsByChange: {'c1': ['a']},
        activitiesById: byId,
      );
      expect(blocks.single.duration(d(9, 30)), const Duration(minutes: 30));
    });

    test('unsorted input is ordered by changedAt', () {
      final blocks = deriveBlocks(
        changes: [chg('late', d(11)), chg('early', d(8))],
        activityIdsByChange: {
          'late': ['b'],
          'early': ['a'],
        },
        activitiesById: byId,
      );
      expect(blocks.map((x) => x.change.syncId), ['late', 'early']);
      expect(blocks[1].end, d(11)); // early block ends where late begins
    });

    test('missing / deleted activity ids are dropped from the set', () {
      final blocks = deriveBlocks(
        changes: [chg('c1', d(9))],
        activityIdsByChange: {'c1': ['a', 'ghost']},
        activitiesById: byId,
      );
      expect(blocks.single.activities.map((x) => x.syncId), ['a']);
    });

    test('empty input yields no blocks', () {
      expect(deriveBlocks(changes: [], activityIdsByChange: {}, activitiesById: {}), isEmpty);
    });
  });

  group('rollUpTotals', () {
    // Work > Client > Task(leaf); plus a flat Break.
    final work = act('work', 'Work');
    final client = act('client', 'Client', parent: 'work');
    final task = act('task', 'CU-1 Task', parent: 'client');
    final brk = act('break', 'Break');
    final tree = ActivityTree.build([work, client, task, brk]);
    final byId = {for (final x in [work, client, task, brk]) x.syncId: x};

    test('a leaf rolls up to every ancestor', () {
      final blocks = deriveBlocks(
        changes: [chg('c1', d(9)), chg('c2', d(10))],
        activityIdsByChange: {'c1': ['task'], 'c2': ['break']},
        activitiesById: byId,
      );
      final totals = rollUpTotals(
        blocks: blocks,
        tree: tree,
        rangeStart: d(0),
        rangeEnd: DateTime(2026, 1, 6),
        now: d(11),
      );
      // task block = 1h, break block = 1h (open, to now=11)
      expect(totals['task'], const Duration(hours: 1));
      expect(totals['client'], const Duration(hours: 1));
      expect(totals['work'], const Duration(hours: 1));
      expect(totals['break'], const Duration(hours: 1));
    });

    test('multi-activity block is even-split among its activities', () {
      // One 1h block tagged with both task (under Work) and Break.
      final blocks = deriveBlocks(
        changes: [chg('c1', d(9)), chg('c2', d(10))],
        activityIdsByChange: {
          'c1': ['task', 'break'],
          'c2': ['break'],
        },
        activitiesById: byId,
      );
      final totals = rollUpTotals(
        blocks: blocks,
        tree: tree,
        rangeStart: d(0),
        rangeEnd: DateTime(2026, 1, 6),
        now: d(10), // second block has zero duration
      );
      // 1h split → 30m task (rolled to client+work), 30m break (+ 0 from open)
      expect(totals['task'], const Duration(minutes: 30));
      expect(totals['work'], const Duration(minutes: 30));
      expect(totals['break'], const Duration(minutes: 30));
    });

    test('blocks are clipped to the range', () {
      final blocks = deriveBlocks(
        changes: [chg('c1', d(8))],
        activityIdsByChange: {'c1': ['task']},
        activitiesById: byId,
      );
      // Range covers only 09:00–09:30 of the open block.
      final totals = rollUpTotals(
        blocks: blocks,
        tree: tree,
        rangeStart: d(9),
        rangeEnd: d(9, 30),
        now: d(23),
      );
      expect(totals['work'], const Duration(minutes: 30));
    });
  });

  group('localWeekRange', () {
    test('Monday-anchored week containing a Wednesday', () {
      final w = localWeekRange(DateTime(2026, 1, 7)); // Wed
      expect(w.start, DateTime(2026, 1, 5)); // Mon
      expect(w.end, DateTime(2026, 1, 12)); // next Mon
    });

    test('Sunday belongs to the week that started the prior Monday', () {
      final w = localWeekRange(DateTime(2026, 1, 11)); // Sun
      expect(w.start, DateTime(2026, 1, 5));
    });
  });

  group('splitByLocalDay', () {
    test('an interval crossing midnight splits into two day segments', () {
      final segs = splitByLocalDay(
        DateTime(2026, 1, 5, 23, 30),
        DateTime(2026, 1, 6, 1, 0),
      ).toList();
      expect(segs.length, 2);
      expect(segs[0].end, DateTime(2026, 1, 6));
      expect(segs[1].start, DateTime(2026, 1, 6));
      expect(segs[0].day, DateTime(2026, 1, 5));
      expect(segs[1].day, DateTime(2026, 1, 6));
    });
  });

  group('ActivityTree', () {
    final work = act('work', 'Work');
    final client = act('client', 'Client', parent: 'work');
    final task = act('task', 'Task', parent: 'client');
    final tree = ActivityTree.build([task, work, client]); // any order

    test('ancestors inclusive, self first', () {
      expect(tree.ancestorIdsInclusive('task'), ['task', 'client', 'work']);
    });

    test('subtree is root + descendants', () {
      expect(tree.subtreeIds('work').toSet(), {'work', 'client', 'task'});
      expect(tree.subtreeIds('task'), ['task']);
    });

    test('pathName is root-first', () {
      expect(tree.pathName('task'), 'Work / Client / Task');
    });

    test('a node with a missing parent is treated as a root', () {
      final orphan = ActivityTree.build([act('x', 'X', parent: 'gone')]);
      expect(orphan.rootIds, ['x']);
    });

    test('depthOf reflects nesting', () {
      expect(tree.depthOf('work'), 0);
      expect(tree.depthOf('task'), 2);
    });
  });

  group('buildCsv', () {
    final work = act('work', 'Work');
    final task = act('task', 'CU-1 Task', parent: 'work');
    final brk = act('break', 'Break');
    final tree = ActivityTree.build([work, task, brk]);
    final byId = {for (final x in [work, task, brk]) x.syncId: x};

    List<Block> blocks() => deriveBlocks(
          changes: [chg('c1', d(9), comment: 'deep work'), chg('c2', d(10))],
          activityIdsByChange: {
            'c1': ['task'],
            'c2': ['break'],
          },
          activitiesById: byId,
        );

    test('one row per (block, activity) with the full block duration', () {
      final csv = buildCsv(blocks: blocks(), tree: tree, now: d(11));
      final lines = csv.trim().split('\r\n');
      expect(lines.first, 'start,end,duration_s,activity,comment');
      expect(lines.length, 3); // header + 2 blocks
      // chronological
      expect(lines[1], contains('Work / CU-1 Task'));
      expect(lines[1], contains('3600')); // 1h
      expect(lines[1], contains('deep work'));
      expect(lines[2], contains('Break'));
    });

    test('open block is omitted when no clock is supplied', () {
      final csv = buildCsv(blocks: blocks(), tree: tree, now: null);
      expect(csv.trim().split('\r\n').length, 2); // header + closed block only
    });

    test('subtree filter drops unrelated blocks', () {
      final csv = buildCsv(blocks: blocks(), tree: tree, now: d(11), subtreeRootId: 'work');
      final lines = csv.trim().split('\r\n');
      expect(lines.length, 2); // header + the task row only
      expect(csv, isNot(contains('Break')));
    });

    test('fields containing commas are quoted', () {
      final a = act('a', 'A, with comma');
      final t2 = ActivityTree.build([a]);
      final bs = deriveBlocks(
        changes: [chg('c1', d(9))],
        activityIdsByChange: {'c1': ['a']},
        activitiesById: {'a': a},
      );
      final csv = buildCsv(blocks: bs, tree: t2, now: d(10));
      expect(csv, contains('"A, with comma"'));
    });
  });

  group('parsePastedTask', () {
    test('extracts a CU-style id prefix', () {
      final p = parsePastedTask('  CU-1234 Fix the thing  ');
      expect(p.externalId, 'CU-1234');
      expect(p.name, 'CU-1234 Fix the thing');
    });

    test('uppercases the id', () {
      expect(parsePastedTask('jira-42 stuff').externalId, 'JIRA-42');
    });

    test('no id prefix -> null id, name kept', () {
      final p = parsePastedTask('just a note');
      expect(p.externalId, isNull);
      expect(p.name, 'just a note');
    });
  });

  group('csvFileName', () {
    test('date-stamped, unscoped', () {
      expect(csvFileName(DateTime(2026, 7, 3, 18, 30)), 'track-2026-07-03.csv');
    });

    test('subtree name is slugged into the file name', () {
      expect(csvFileName(DateTime(2026, 7, 30), scopeName: 'Work / Client'),
          'track-work-client-2026-07-30.csv');
    });

    test('a name with no usable characters still yields a valid file name', () {
      expect(csvFileName(DateTime(2026, 7, 30), scopeName: '★★'), 'track-subtree-2026-07-30.csv');
    });
  });

  group('parseTimeOfDay', () {
    final day = DateTime(2026, 3, 9, 22, 40);

    test('separated forms land on the given day', () {
      expect(parseTimeOfDay('14:05', onDay: day), DateTime(2026, 3, 9, 14, 5));
      expect(parseTimeOfDay('14.05', onDay: day), DateTime(2026, 3, 9, 14, 5));
      expect(parseTimeOfDay('9:5', onDay: day), DateTime(2026, 3, 9, 9, 5));
      expect(parseTimeOfDay('  7:30  ', onDay: day), DateTime(2026, 3, 9, 7, 30));
    });

    test('compact forms split the last two digits as minutes', () {
      expect(parseTimeOfDay('1405', onDay: day), DateTime(2026, 3, 9, 14, 5));
      expect(parseTimeOfDay('905', onDay: day), DateTime(2026, 3, 9, 9, 5));
    });

    test('the date comes from the block, not from today', () {
      // A block opened at 23:50 and corrected to 23:20 stays on its own day
      // rather than jumping to the current one.
      final lateBlock = DateTime(2025, 12, 31, 23, 50);
      expect(parseTimeOfDay('23:20', onDay: lateBlock), DateTime(2025, 12, 31, 23, 20));
    });

    test('rejects out-of-range and unparseable input', () {
      expect(parseTimeOfDay('24:00', onDay: day), isNull);
      expect(parseTimeOfDay('12:60', onDay: day), isNull);
      expect(parseTimeOfDay('', onDay: day), isNull);
      expect(parseTimeOfDay('soon', onDay: day), isNull);
      expect(parseTimeOfDay('12', onDay: day), isNull);
    });

    test('an ambiguous 3-digit-with-separator split is not invented', () {
      // "145" is compact 1:45; the separated branch never sees it, so there is
      // no path where the same string means both 1:45 and 14:05.
      expect(parseTimeOfDay('145', onDay: day), DateTime(2026, 3, 9, 1, 45));
    });
  });
}
