import 'activity_tree.dart';
import 'block.dart';

/// Time totals for one report range, keyed by activity id.
///
/// Both maps come out of a single pass over the blocks, so they cannot disagree
/// about clipping or about the even split.
class ReportTotals {
  const ReportTotals({required this.subtree, required this.direct});

  /// Time on an activity **and everything under it** — which is what "how much
  /// did I work for Payout" means once Payout has sub-tasks of its own. So
  /// `subtree[workRootId]` is the whole Work subtree's time.
  final Map<String, Duration> subtree;

  /// Time booked on the activity *itself*, with no descendants counted.
  ///
  /// A node's [subtree] total minus its [direct] time is exactly what its
  /// children account for. Without this the drill-down would show children that
  /// silently fail to add up to their parent.
  final Map<String, Duration> direct;

  Duration subtreeOf(String id) => subtree[id] ?? Duration.zero;

  Duration directOf(String id) => direct[id] ?? Duration.zero;
}

/// Per-activity time roll-up for the Reports screen.
///
/// Rules (from ~/org/todo.org "Time-activity tracking app" → Requirements):
///  * A multi-activity block's duration is split **evenly** among its activities
///    (sequential, unknown split).
///  * Each activity's time then **rolls up the tree**: a leaf's time counts
///    toward every ancestor category.
///  * Blocks are **clipped to the report range** [rangeStart, rangeEnd); the
///    open block is measured up to [now]. A block straddling the range boundary
///    contributes only its in-range portion.
ReportTotals reportTotals({
  required List<Block> blocks,
  required ActivityTree tree,
  required DateTime rangeStart,
  required DateTime rangeEnd,
  required DateTime now,
}) {
  final subtree = <String, int>{};
  final direct = <String, int>{};

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
      direct[a.syncId] = (direct[a.syncId] ?? 0) + share;
      for (final ancestor in tree.ancestorIdsInclusive(a.syncId)) {
        subtree[ancestor] = (subtree[ancestor] ?? 0) + share;
      }
    }
  }

  return ReportTotals(
    subtree: _asDurations(subtree),
    direct: _asDurations(direct),
  );
}

/// One local day of a report range, split across the top-level categories.
class DayTotals {
  const DayTotals({required this.day, required this.byRoot});

  /// Local midnight the day starts at.
  final DateTime day;

  /// Top-level activity id -> time booked anywhere in that root's subtree.
  final Map<String, Duration> byRoot;

  Duration get total => byRoot.values.fold(Duration.zero, (a, b) => a + b);

  Duration of(String rootId) => byRoot[rootId] ?? Duration.zero;
}

/// Day-resolution breakdown of [rangeStart, rangeEnd), oldest day first.
///
/// Same rules as [reportTotals] — even split across a block's activities, time
/// rolled up the tree — but only as far as the root, because a day is read as a
/// stacked bar of top-level categories rather than drilled into. So each day's
/// [DayTotals.total] equals what the per-category bars for that day add up to.
///
/// A block crossing midnight is cut at the boundary ([splitByLocalDay]) and each
/// side lands on its own day. Days that have not happened yet are left out, so
/// the current week ends at today rather than trailing empty rows.
List<DayTotals> dailyTotals({
  required List<Block> blocks,
  required ActivityTree tree,
  required DateTime rangeStart,
  required DateTime rangeEnd,
  required DateTime now,
}) {
  final micros = <DateTime, Map<String, int>>{};

  for (final block in blocks) {
    final blockEnd = block.end ?? now;
    final start = block.start.isAfter(rangeStart) ? block.start : rangeStart;
    final end = blockEnd.isBefore(rangeEnd) ? blockEnd : rangeEnd;
    if (!end.isAfter(start)) continue;

    final acts = block.activities;
    if (acts.isEmpty) continue;

    for (final seg in splitByLocalDay(start, end)) {
      final share = seg.end.difference(seg.start).inMicroseconds ~/ acts.length;
      if (share <= 0) continue;

      final buckets = micros[seg.day] ??= {};
      for (final a in acts) {
        final root = tree.ancestorIdsInclusive(a.syncId).lastOrNull;
        if (root == null) continue; // not in the catalogue: no bar to land on
        buckets[root] = (buckets[root] ?? 0) + share;
      }
    }
  }

  final lastDay = rangeEnd.isBefore(now) ? rangeEnd : now;
  final out = <DayTotals>[];
  for (var day = rangeStart;
      day.isBefore(rangeEnd) && !day.isAfter(lastDay);
      day = DateTime(day.year, day.month, day.day + 1)) {
    out.add(DayTotals(day: day, byRoot: _asDurations(micros[day] ?? const {})));
  }
  return out;
}

Map<String, Duration> _asDurations(Map<String, int> micros) =>
    micros.map((k, v) => MapEntry(k, Duration(microseconds: v)));

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

/// The local day `[midnight, next midnight)` containing [day] — the week range's
/// counterpart, for a report scoped to a single day.
({DateTime start, DateTime end}) localDayRange(DateTime day) {
  final start = DateTime(day.year, day.month, day.day);
  return (start: start, end: DateTime(start.year, start.month, start.day + 1));
}
