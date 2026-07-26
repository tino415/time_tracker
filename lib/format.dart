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

/// `H:MM` or `M:SS`-free compact duration for the timeline / reports, e.g.
/// `2h 05m`, `12m`, `0m`. Rounds down to the minute.
String formatDurationHm(Duration d) {
  if (d.isNegative) return '0m';
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h == 0) return '${m}m';
  return '${h}h ${m.toString().padLeft(2, '0')}m';
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

/// Readable local timestamp, e.g. `14:05` today or `Mon 14:05` otherwise.
String formatTimestamp(DateTime t, DateTime now) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final sameDay = t.year == now.year && t.month == now.month && t.day == now.day;
  final hm = formatTimeOfDay(t);
  return sameDay ? hm : '${days[t.weekday - 1]} $hm';
}
