import 'package:flutter/material.dart';

/// Parse a stored `#RRGGBB` (or `#AARRGGBB`) hex colour. Falls back to grey on
/// anything malformed so a bad value never crashes a screen.
Color parseHexColor(String hex) {
  var v = hex.trim().replaceFirst('#', '');
  if (v.length == 6) v = 'FF$v';
  final n = int.tryParse(v, radix: 16);
  return n == null ? const Color(0xFF9A9B95) : Color(n);
}

/// Format a colour back to the stored `#RRGGBB` form (alpha dropped).
String toHexColor(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// `H:MM` or `M:SS`-free compact duration, e.g. `2h 05m`, `12m`, `0m`. Rounds
/// down to the minute, and stays in hours however large: this is the form for
/// *totals* — 25 hours of Work in a week is `25h 00m`, the unit a report is
/// read and compared in, where `1d 1h` would claim a calendar day the number
/// does not have. A single block's stretch of wall clock prints via
/// [formatSpan] instead.
String formatDurationHm(Duration d) {
  if (d.isNegative) return '0m';
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h == 0) return '${m}m';
  return '${h}h ${m.toString().padLeft(2, '0')}m';
}

/// A single block's span: [formatDurationHm] under a day, `2d 14h` past it.
///
/// A span is an interval on the calendar, so days are its natural unit —
/// `62h 14m` on a weekend-long block takes arithmetic to read. Minutes drop
/// once days appear, the same trade `2h 05m` already makes with seconds; the
/// places needing the exact figure (CSV, report totals) hold the [Duration].
String formatSpan(Duration d) {
  if (d.inHours >= 24) return '${d.inDays}d ${d.inHours % 24}h';
  return formatDurationHm(d);
}

/// `H:MM:SS` live elapsed clock for the "Now" hero card.
String formatElapsedClock(Duration d) {
  if (d.isNegative) d = Duration.zero;
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  return '$h:$mm:$ss';
}

/// `14:05` local time-of-day.
String formatTimeOfDay(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Parse a typed time-of-day onto [onDay]: `14:05`, `14.05`, `1405` or `905`.
/// Returns null for anything else, so the caller can leave the field alone
/// rather than jumping to a time nobody asked for.
///
/// The date comes from [onDay], not from today — a block that began before
/// midnight is corrected against its own clock.
///
/// Minutes must be two digits unless a separator makes the split unambiguous:
/// `145` would otherwise be both 1:45 and 14:05.
DateTime? parseTimeOfDay(String input, {required DateTime onDay}) {
  final text = input.trim();
  final separated = RegExp(r'^(\d{1,2})[:.h ](\d{1,2})$').firstMatch(text);
  final compact = RegExp(r'^(\d{3,4})$').firstMatch(text);

  final int hour, minute;
  if (separated != null) {
    hour = int.parse(separated.group(1)!);
    minute = int.parse(separated.group(2)!);
  } else if (compact != null) {
    final digits = compact.group(1)!;
    hour = int.parse(digits.substring(0, digits.length - 2));
    minute = int.parse(digits.substring(digits.length - 2));
  } else {
    return null;
  }

  if (hour > 23 || minute > 59) return null;
  return DateTime(onDay.year, onDay.month, onDay.day, hour, minute);
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// `MON 18` — weekday plus day of month, for report rows whose month is already
/// fixed by the week being shown.
String formatWeekdayDay(DateTime d) => '${_weekdays[d.weekday - 1].toUpperCase()} ${d.day}';

/// Readable local timestamp: `14:05` today, `Mon 14:05` back through the last
/// six days, `5/9 14:05` beyond that. The weekday form stops where it stops
/// being an answer — a week or more back it names the wrong-looking day, and a
/// reader pairing it with a capped clock has nothing else dating the block.
String formatTimestamp(DateTime t, DateTime now) {
  final hm = formatTimeOfDay(t);
  final day = DateTime(t.year, t.month, t.day);
  final today = DateTime(now.year, now.month, now.day);
  if (day == today) return hm;
  if (day.isAfter(DateTime(today.year, today.month, today.day - 7))) {
    return '${_weekdays[t.weekday - 1]} $hm';
  }
  return '${t.day}/${t.month} $hm';
}
