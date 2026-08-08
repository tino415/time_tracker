import 'block.dart';

/// Geometry + edit rules for the calendar day view. Kept pure (no Flutter, no
/// database) so the awkward parts — day clipping, and the clamping that stops a
/// dragged boundary from reordering the timeline — are testable on their own.

/// One block's visible slice inside a single local calendar day.
///
/// A block can span midnight, so the calendar shows a *slice* of it rather than
/// the block itself. [continuesBefore] / [continuesAfter] say the real block
/// extends past this day, which the view draws as an open edge instead of a
/// draggable boundary — you cannot drag a boundary that is not on screen.
class DaySlice {
  const DaySlice({
    required this.block,
    required this.start,
    required this.end,
    required this.continuesBefore,
    required this.continuesAfter,
  });

  final Block block;

  /// Slice bounds, clipped to the day.
  final DateTime start;
  final DateTime end;

  final bool continuesBefore;
  final bool continuesAfter;

  Duration get duration => end.difference(start);

  /// Minutes from local midnight — the view's vertical coordinate.
  double get startMinutes => minutesFromMidnight(start);
  double get endMinutes => continuesAfter ? 24 * 60 : minutesFromMidnight(end);
}

/// Minutes elapsed since [t]'s own local midnight — the calendar's vertical
/// coordinate. Measured against the local day rather than as `hour * 60 + minute`
/// so a DST shift moves the axis with the clock instead of tearing it.
double minutesFromMidnight(DateTime t) {
  final midnight = DateTime(t.year, t.month, t.day);
  return t.difference(midnight).inMilliseconds / 60000.0;
}

/// The slices of [blocks] visible on the local calendar day containing [day],
/// chronological. The open block is measured up to [now].
///
/// Blocks that do not touch the day are dropped, as are zero-length slices.
List<DaySlice> sliceDay({
  required List<Block> blocks,
  required DateTime day,
  required DateTime now,
}) {
  final dayStart = DateTime(day.year, day.month, day.day);
  final dayEnd = DateTime(day.year, day.month, day.day + 1);

  final out = <DaySlice>[];
  for (final block in blocks) {
    final blockEnd = block.end ?? now;
    // Half-open [start, end): a block ending exactly at midnight belongs to the
    // earlier day only.
    if (!blockEnd.isAfter(dayStart) || !dayEnd.isAfter(block.start)) continue;

    final start = block.start.isAfter(dayStart) ? block.start : dayStart;
    final end = blockEnd.isBefore(dayEnd) ? blockEnd : dayEnd;
    if (!end.isAfter(start)) continue;

    out.add(DaySlice(
      block: block,
      start: start,
      end: end,
      continuesBefore: block.start.isBefore(dayStart),
      continuesAfter: blockEnd.isAfter(dayEnd),
    ));
  }

  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}

/// Where a dragged boundary is allowed to land.
///
/// Boundaries are shared: moving one retimes the end of the previous block and
/// the start of the next. Letting it cross a neighbour would reorder the
/// timeline and silently swap which activity owns which stretch of the day, so
/// the target is confined to `(previous, next)` with [minBlock] of clearance on
/// each side, and never past [notAfter] (the future holds no tracked time).
///
/// [notAfter] gets the same clearance. The running block's end is *now*, which
/// is not a boundary, so without it a drag could land exactly on the present and
/// leave a block of zero length — visible as a card too short to draw and a
/// block that cannot be grabbed again.
///
/// Returns null when the window is empty — the neighbours are closer together
/// than two [minBlock]s — meaning there is no legal position and the caller
/// should leave the boundary alone.
DateTime? clampBoundary({
  required DateTime desired,
  DateTime? previous,
  DateTime? next,
  DateTime? notAfter,
  Duration minBlock = const Duration(minutes: 1),
}) {
  final lower = previous?.add(minBlock);
  var upper = next?.subtract(minBlock);
  final latest = notAfter?.subtract(minBlock);
  if (latest != null && (upper == null || latest.isBefore(upper))) {
    upper = latest;
  }

  if (lower != null && upper != null && upper.isBefore(lower)) return null;

  var out = desired;
  if (lower != null && out.isBefore(lower)) out = lower;
  if (upper != null && out.isAfter(upper)) out = upper;
  return out;
}

/// Round [t] to the nearest multiple of [granularity], so a drag lands on tidy
/// times (05:15, not 05:14:37).
///
/// Snapping is done on the epoch, which keeps it monotonic across a DST jump;
/// real-world UTC offsets are whole minutes, so a minute-scale granularity still
/// lands on whole local minutes.
DateTime snapTime(DateTime t, Duration granularity) {
  final g = granularity.inMilliseconds;
  if (g <= 0) return t;
  final ms = t.millisecondsSinceEpoch;
  return DateTime.fromMillisecondsSinceEpoch((ms / g).round() * g);
}
