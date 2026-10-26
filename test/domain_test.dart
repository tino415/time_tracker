// Pure-domain unit tests: no plugins / no DB, so the suite runs anywhere.
// Covers block derivation, per-category roll-up (even-split + tree), CSV export,
// the activity tree, pasted-task parsing, and typed time-of-day parsing.

import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/format.dart';
import 'package:time_tracker/domain/activity_search.dart';
import 'package:time_tracker/domain/activity_tree.dart';
import 'package:time_tracker/domain/block.dart';
import 'package:time_tracker/domain/calendar.dart';
import 'package:time_tracker/domain/csv_export.dart';
import 'package:time_tracker/domain/reporting.dart';
import 'package:time_tracker/domain/task_paste.dart';

Activity act(
  String id,
  String name, {
  String? parent,
  String color = '#4F8FEE',
  List<String> aliases = const [],
}) => Activity(
  syncId: id,
  parentId: parent,
  name: name,
  color: color,
  bookmarked: false,
  aliases: aliases,
  version: 1,
  dirty: false,
);

ActivityChange chg(String id, DateTime at, {String? comment}) =>
    ActivityChange(syncId: id, changedAt: at, comment: comment, version: 1, dirty: false);

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
        activityIdsByChange: {
          'c1': ['a'],
        },
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
        activityIdsByChange: {
          'c1': ['a', 'ghost'],
        },
        activitiesById: byId,
      );
      expect(blocks.single.activities.map((x) => x.syncId), ['a']);
    });

    test('empty input yields no blocks', () {
      expect(deriveBlocks(changes: [], activityIdsByChange: {}, activitiesById: {}), isEmpty);
    });
  });

  group('reportTotals', () {
    // Work > Client > Task(leaf); plus a flat Break.
    final work = act('work', 'Work');
    final client = act('client', 'Client', parent: 'work');
    final task = act('task', 'CU-1 Task', parent: 'client');
    final brk = act('break', 'Break');
    final tree = ActivityTree.build([work, client, task, brk]);
    final byId = {
      for (final x in [work, client, task, brk]) x.syncId: x,
    };

    test('a leaf rolls up to every ancestor', () {
      final blocks = deriveBlocks(
        changes: [chg('c1', d(9)), chg('c2', d(10))],
        activityIdsByChange: {
          'c1': ['task'],
          'c2': ['break'],
        },
        activitiesById: byId,
      );
      final totals = reportTotals(
        blocks: blocks,
        tree: tree,
        rangeStart: d(0),
        rangeEnd: DateTime(2026, 1, 6),
        now: d(11),
      );
      // task block = 1h, break block = 1h (open, to now=11)
      expect(totals.subtreeOf('task'), const Duration(hours: 1));
      expect(totals.subtreeOf('client'), const Duration(hours: 1));
      expect(totals.subtreeOf('work'), const Duration(hours: 1));
      expect(totals.subtreeOf('break'), const Duration(hours: 1));
    });

    test('direct time is the node itself, subtree time includes descendants', () {
      // 1h on the leaf, then 1h on the Client category directly.
      final blocks = deriveBlocks(
        changes: [chg('c1', d(9)), chg('c2', d(10)), chg('c3', d(11))],
        activityIdsByChange: {
          'c1': ['task'],
          'c2': ['client'],
          'c3': ['break'],
        },
        activitiesById: byId,
      );
      final totals = reportTotals(
        blocks: blocks,
        tree: tree,
        rangeStart: d(0),
        rangeEnd: DateTime(2026, 1, 6),
        now: d(11), // the break block is open but zero-length
      );

      expect(totals.subtreeOf('client'), const Duration(hours: 2));
      expect(totals.directOf('client'), const Duration(hours: 1));
      // A leaf's two totals agree; a root that is never tracked itself has none.
      expect(totals.subtreeOf('task'), const Duration(hours: 1));
      expect(totals.directOf('task'), const Duration(hours: 1));
      expect(totals.subtreeOf('work'), const Duration(hours: 2));
      expect(totals.directOf('work'), Duration.zero);
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
      final totals = reportTotals(
        blocks: blocks,
        tree: tree,
        rangeStart: d(0),
        rangeEnd: DateTime(2026, 1, 6),
        now: d(10), // second block has zero duration
      );
      // 1h split → 30m task (rolled to client+work), 30m break (+ 0 from open)
      expect(totals.subtreeOf('task'), const Duration(minutes: 30));
      expect(totals.subtreeOf('work'), const Duration(minutes: 30));
      expect(totals.subtreeOf('break'), const Duration(minutes: 30));
    });

    test('blocks are clipped to the range', () {
      final blocks = deriveBlocks(
        changes: [chg('c1', d(8))],
        activityIdsByChange: {
          'c1': ['task'],
        },
        activitiesById: byId,
      );
      // Range covers only 09:00–09:30 of the open block.
      final totals = reportTotals(
        blocks: blocks,
        tree: tree,
        rangeStart: d(9),
        rangeEnd: d(9, 30),
        now: d(23),
      );
      expect(totals.subtreeOf('work'), const Duration(minutes: 30));
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

  group('localWeekOffset', () {
    test('a day of this week is 0', () {
      expect(localWeekOffset(DateTime(2026, 1, 5), DateTime(2026, 1, 11, 23)), 0);
    });

    test('a day of last week is -1', () {
      expect(localWeekOffset(DateTime(2026, 1, 4), DateTime(2026, 1, 5)), -1);
    });

    test(
      'the week before the spring DST change is still one week back',
      () => expect(localWeekOffset(DateTime(2026, 3, 25), DateTime(2026, 4, 1)), -1),
      skip: _observesSpringDst ? false : 'the test zone has no DST change on 29 March 2026',
    );
  });

  group('localMonthRange', () {
    test('runs from the 1st to the next 1st', () {
      final m = localMonthRange(DateTime(2026, 2, 17, 13, 45));
      expect(m.start, DateTime(2026, 2));
      expect(m.end, DateTime(2026, 3));
    });

    test('December ends on the 1st of January of the next year', () {
      final m = localMonthRange(DateTime(2026, 12, 31, 23, 59));
      expect(m.start, DateTime(2026, 12));
      expect(m.end, DateTime(2027));
    });

    test('a month with a DST change still ends on midnight', () {
      final m = localMonthRange(DateTime(2026, 3, 29, 12));
      expect(m.end, DateTime(2026, 4));
      expect(m.end.hour, 0);
    });
  });

  group('remainingToday', () {
    test('counts to the next midnight', () {
      expect(remainingToday(DateTime(2026, 1, 7, 9, 30)), const Duration(hours: 14, minutes: 30));
    });

    test('a minute before midnight is a minute, not a negative', () {
      expect(remainingToday(DateTime(2026, 1, 7, 23, 59)), const Duration(minutes: 1));
    });

    test('a minute after midnight is nearly the whole day', () {
      expect(remainingToday(DateTime(2026, 1, 8, 0, 1)), const Duration(hours: 23, minutes: 59));
    });

    test('midnight itself is a whole day, never zero', () {
      // The boundary belongs to the day starting, so the number never reads 0m
      // for the instant it flips. localDayRange puts midnight at a day's start.
      expect(remainingToday(DateTime(2026, 1, 7)), const Duration(days: 1));
    });
  });

  group('elapsedToday', () {
    test('a block started today counts from its start', () {
      expect(
        elapsedToday(DateTime(2026, 1, 7, 9), DateTime(2026, 1, 7, 11, 30)),
        const Duration(hours: 2, minutes: 30),
      );
    });

    test('a block started before today counts from midnight', () {
      // The weekend block: started Friday, looked at Sunday morning. The clock
      // answers "how long today", not the 62-hour running total.
      expect(
        elapsedToday(DateTime(2026, 1, 2, 18, 12), DateTime(2026, 1, 4, 8, 26)),
        const Duration(hours: 8, minutes: 26),
      );
    });

    test('a start exactly at midnight is today, whole', () {
      expect(elapsedToday(DateTime(2026, 1, 7), DateTime(2026, 1, 7, 5)), const Duration(hours: 5));
    });

    test('never exceeds the day so far', () {
      final now = DateTime(2026, 1, 7, 23, 59);
      expect(elapsedToday(DateTime(2025, 6, 1), now), lessThan(const Duration(hours: 24)));
    });
  });

  group('formatSpan', () {
    test('under a day it is formatDurationHm, verbatim', () {
      expect(formatSpan(const Duration(hours: 2, minutes: 5)), '2h 05m');
      expect(formatSpan(const Duration(minutes: 12)), '12m');
      expect(formatSpan(const Duration(hours: 23, minutes: 59)), '23h 59m');
    });

    test('a day and beyond reads in days and hours', () {
      expect(formatSpan(const Duration(hours: 62, minutes: 14)), '2d 14h');
      expect(formatSpan(const Duration(hours: 24)), '1d 0h');
    });

    test('minutes drop once days appear', () {
      // The same trade `2h 05m` already makes with seconds: past a day the
      // minutes are noise, and the exact figure lives in the Duration.
      expect(formatSpan(const Duration(days: 1, minutes: 59)), '1d 0h');
    });

    test('a total stays in hours however large', () {
      // Report totals go through formatDurationHm on purpose: 25 hours of Work
      // in a week is 25h — `1d 1h` would claim a calendar day the number does
      // not have. Days belong to spans, which occupy the calendar.
      expect(formatDurationHm(const Duration(hours: 25)), '25h 00m');
      expect(formatDurationHm(const Duration(hours: 62, minutes: 14)), '62h 14m');
    });
  });

  group('formatTimestamp', () {
    final now = DateTime(2026, 1, 7, 20); // Wed

    test('today is the bare time', () {
      expect(formatTimestamp(DateTime(2026, 1, 7, 14, 5), now), '14:05');
    });

    test('the last six days get a weekday', () {
      expect(formatTimestamp(DateTime(2026, 1, 6, 14, 5), now), 'Tue 14:05');
      expect(formatTimestamp(DateTime(2026, 1, 1, 14, 5), now), 'Thu 14:05');
    });

    test('a week or more back gets a date, not a lying weekday', () {
      // Exactly seven days back the weekday names today's own weekday — the
      // reading every capped clock would invite. The date form cannot lie.
      expect(formatTimestamp(DateTime(2025, 12, 31, 14, 5), now), '31/12 14:05');
      expect(formatTimestamp(DateTime(2025, 6, 1, 9, 0), now), '1/6 09:00');
    });
  });

  group('sliceByLocalDay', () {
    List<Block> blocksFor(List<ActivityChange> changes) => deriveBlocks(
      changes: changes,
      activityIdsByChange: {for (final c in changes) c.syncId: []},
      activitiesById: {},
    );

    test('a block inside one day is one slice, untouched', () {
      final now = DateTime(2026, 1, 5, 20);
      final blocks = blocksFor([chg('a', d(9)), chg('b', d(12))]);
      final slices = sliceByLocalDay(blocks, now);

      expect(slices, hasLength(2));
      // Newest first, same as the blocks went in.
      expect(slices[1].start, d(9));
      expect(slices[1].end, d(12));
      expect(slices[1].duration, const Duration(hours: 3));
    });

    test('sleep from 23:00 to 7:10 splits at midnight', () {
      final now = DateTime(2026, 1, 6, 20);
      final blocks = blocksFor([
        chg('sleep', DateTime(2026, 1, 5, 23)),
        chg('wake', DateTime(2026, 1, 6, 7, 10)),
      ]);
      final slices = sliceByLocalDay(blocks, now);

      expect(slices, hasLength(3));
      // The open "wake" block first, then sleep's two slices, newest first.
      final morning = slices[1];
      final evening = slices[2];
      expect(evening.start, DateTime(2026, 1, 5, 23));
      expect(evening.end, DateTime(2026, 1, 6));
      expect(evening.duration, const Duration(hours: 1));
      expect(evening.continuesAfter, isTrue);
      expect(morning.start, DateTime(2026, 1, 6));
      expect(morning.end, DateTime(2026, 1, 6, 7, 10));
      expect(morning.duration, const Duration(hours: 7, minutes: 10));
      expect(morning.continuesBefore, isTrue);
      expect(morning.continuesAfter, isFalse);
      // Both rows act on the one real block.
      expect(identical(morning.block, evening.block), isTrue);
    });

    test('an open block crossing midnight: only the last slice runs to now', () {
      final now = DateTime(2026, 1, 6, 7, 10);
      final blocks = blocksFor([chg('sleep', DateTime(2026, 1, 5, 23))]);
      final slices = sliceByLocalDay(blocks, now);

      expect(slices, hasLength(2));
      expect(slices[0].start, DateTime(2026, 1, 6));
      expect(slices[0].end, now);
      expect(slices[0].continuesAfter, isFalse);
      expect(slices[0].duration, const Duration(hours: 7, minutes: 10));
      expect(slices[1].end, DateTime(2026, 1, 6));
      expect(slices[1].continuesAfter, isTrue);
    });

    test('ending exactly at midnight belongs wholly to the earlier day', () {
      final now = DateTime(2026, 1, 6, 20);
      final blocks = blocksFor([chg('a', d(23)), chg('b', DateTime(2026, 1, 6))]);
      final slices = sliceByLocalDay(blocks, now);

      // No zero-length slice under the day the block only touches.
      final a = slices.last;
      expect(a.start, d(23));
      expect(a.end, DateTime(2026, 1, 6));
      expect(slices.where((s) => s.block == a.block), hasLength(1));
    });

    test('a multi-day block yields one slice per day it touches', () {
      final now = DateTime(2026, 1, 8, 20);
      final blocks = blocksFor([
        chg('long', DateTime(2026, 1, 5, 18)),
        chg('after', DateTime(2026, 1, 8, 6)),
      ]);
      final long = sliceByLocalDay(blocks, now).where((s) => s.block.change.syncId == 'long');

      expect(long.map((s) => s.start).toList(), [
        DateTime(2026, 1, 8),
        DateTime(2026, 1, 7),
        DateTime(2026, 1, 6),
        DateTime(2026, 1, 5, 18),
      ]);
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
    final byId = {
      for (final x in [work, task, brk]) x.syncId: x,
    };

    List<Block> blocks() => deriveBlocks(
      changes: [
        chg('c1', d(9), comment: 'deep work'),
        chg('c2', d(10)),
      ],
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
        activityIdsByChange: {
          'c1': ['a'],
        },
        activitiesById: {'a': a},
      );
      final csv = buildCsv(blocks: bs, tree: t2, now: d(10));
      expect(csv, contains('"A, with comma"'));
    });
  });

  group('activity search', () {
    final learning = act('l', 'Učenie sa', aliases: ['Learning', 'Vzdelávanie']);

    test('an alias finds the activity', () {
      expect(activityMatchesQuery(learning, 'learn'), isTrue);
      expect(activityMatchesQuery(learning, 'vzdel'), isTrue);
    });

    test('the name still matches, and an unrelated word does not', () {
      expect(activityMatchesQuery(learning, 'učenie'), isTrue);
      expect(activityMatchesQuery(learning, 'cooking'), isFalse);
    });

    test('adding an alias trims it, skips blanks and duplicates', () {
      expect(withAlias(['a'], '  b, c '), ['a', 'b, c']);
      expect(withAlias(['a'], '   '), ['a']);
      expect(withAlias(['a'], 'a'), ['a']);
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
      expect(
        csvFileName(DateTime(2026, 7, 30), scopeName: 'Work / Client'),
        'track-work-client-2026-07-30.csv',
      );
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

final _observesSpringDst =
    DateTime(2026, 3, 30).difference(DateTime(2026, 3, 29)) != const Duration(days: 1);
