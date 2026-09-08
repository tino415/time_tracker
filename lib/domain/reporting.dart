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

  return ReportTotals(subtree: _asDurations(subtree), direct: _asDurations(direct));
}

Map<String, Duration> _asDurations(Map<String, int> micros) =>
    micros.map((k, v) => MapEntry(k, Duration(microseconds: v)));

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

/// How much of [now]'s local day is still ahead.
///
/// The day ends at midnight, which is the boundary every report already buckets
/// by, so this needs nothing stored and nothing configured. Derived from [now]
/// rather than from a clock of its own, so a caller that already has a tick can
/// hand it over and the two numbers cannot disagree.
///
/// Uses [localDayRange]'s own end rather than adding 24 hours, so the one day a
/// year that is 23 or 25 hours long answers with the day it actually has.
Duration remainingToday(DateTime now) => localDayRange(now).end.difference(now);
