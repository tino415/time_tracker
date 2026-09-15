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

/// Every day's slices of [newestFirst], newest first — the timeline list's
/// rows. The open block's last slice ends at [now].
///
/// Cuts fall at `DateTime(y, m, d + 1)`, half-open: a block ending exactly at
/// midnight belongs to the earlier day only, and on a DST day the cut lands
/// where the local clock says, not 24 hours along. [sliceDay] filters this, so
/// the timeline and the calendar cannot disagree about which day owns a
/// stretch — and neither can the daily report, which clips to the same
/// `localDayRange` boundary.
List<DaySlice> sliceByLocalDay(List<Block> newestFirst, DateTime now) {
  final out = <DaySlice>[];
  for (final b in newestFirst) {
    final end = b.end ?? now;
    final points = [b.start];
    var midnight = DateTime(b.start.year, b.start.month, b.start.day + 1);
    while (midnight.isBefore(end)) {
      points.add(midnight);
      midnight = DateTime(midnight.year, midnight.month, midnight.day + 1);
    }
    points.add(end);

    for (var i = points.length - 2; i >= 0; i--) {
      out.add(
        DaySlice(
          block: b,
          start: points[i],
          end: points[i + 1],
          continuesBefore: i > 0,
          continuesAfter: i < points.length - 2,
        ),
      );
    }
  }
  return out;
}

/// The slices of [blocks] visible on the local calendar day containing [day],
/// chronological. The open block is measured up to [now].
///
/// A filter over [sliceByLocalDay] — the one owner of the midnight rule —
/// keeping only [day]'s slices. Blocks that do not touch the day are dropped,
/// as are zero-length slices (a boundary opened this instant has nothing for a
/// calendar to draw, though the timeline list still shows it as a row).
List<DaySlice> sliceDay({
  required List<Block> blocks,
  required DateTime day,
  required DateTime now,
}) {
  final dayStart = DateTime(day.year, day.month, day.day);
  final out = sliceByLocalDay(blocks, now)
      .where(
        (s) =>
            DateTime(s.start.year, s.start.month, s.start.day) == dayStart &&
            s.end.isAfter(s.start),
      )
      .toList();
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
