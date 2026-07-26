import 'activity_tree.dart';
import 'block.dart';

/// Per-category time roll-up for the Reports screen.
///
/// Rules (from ~/org/todo.org "Time-activity tracking app" → Requirements):
///  * A multi-activity block's duration is split **evenly** among its activities
///    (sequential, unknown split).
///  * Each activity's time then **rolls up the tree**: a leaf's time counts
///    toward every ancestor category. So `totals[workRootId]` is the whole Work
///    subtree's time.
///  * Blocks are **clipped to the report range** [rangeStart, rangeEnd); the
///    open block is measured up to [now]. A block straddling the range boundary
///    contributes only its in-range portion.
///
/// Returns rolled-up totals keyed by activity id (self + ancestors accrued).
Map<String, Duration> rollUpTotals({
  required List<Block> blocks,
  required ActivityTree tree,
  required DateTime rangeStart,
  required DateTime rangeEnd,
  required DateTime now,
}) {
  final micros = <String, int>{};

  for (final block in blocks) {
    final blockEnd = block.end ?? now;
    final start = block.start.isAfter(rangeStart) ? block.start : rangeStart;
    final end = blockEnd.isBefore(rangeEnd) ? blockEnd : rangeEnd;
    if (!end.isAfter(start)) continue;

    final acts = block.activities;
    if (acts.isEmpty) continue;

    final share = end.difference(start).inMicroseconds ~/ acts.length;
    if (share <= 0) continue;

    for (final a in acts) {
      for (final ancestor in tree.ancestorIdsInclusive(a.syncId)) {
        micros[ancestor] = (micros[ancestor] ?? 0) + share;
      }
    }
  }

  return micros.map((k, v) => MapEntry(k, Duration(microseconds: v)));
}

/// Local-day bucketing helper: split [start, end) at each local midnight,
/// yielding one `(dayStart, segmentStart, segmentEnd)` per calendar day the
/// interval touches. Used for per-day breakdowns (a block crossing midnight is
/// split at the boundary). The weekly per-category roll-up does not need this —
/// it only clips — but a day-resolution report does.
Iterable<({DateTime day, DateTime start, DateTime end})> splitByLocalDay(
  DateTime start,
  DateTime end,
) sync* {
  var cursor = start;
  while (cursor.isBefore(end)) {
    final nextMidnight = DateTime(cursor.year, cursor.month, cursor.day + 1);
    final segEnd = nextMidnight.isBefore(end) ? nextMidnight : end;
    yield (day: DateTime(cursor.year, cursor.month, cursor.day), start: cursor, end: segEnd);
    cursor = segEnd;
  }
}

/// The local calendar week [Monday 00:00, next Monday 00:00) containing [day].
/// Uses calendar arithmetic (not `Duration`) so DST transitions don't shift the
/// boundaries off midnight.
({DateTime start, DateTime end}) localWeekRange(DateTime day) {
  final offset = day.weekday - DateTime.monday; // Mon=0 .. Sun=6
  final start = DateTime(day.year, day.month, day.day - offset);
  final end = DateTime(start.year, start.month, start.day + 7);
  return (start: start, end: end);
}
