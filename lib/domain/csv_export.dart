import 'activity_tree.dart';
import 'block.dart';

/// Client-side CSV export (every platform). One row per **(block, activity)**:
/// `start,end,duration_s,activity,comment`. `duration_s` is the *whole block*
/// duration (not the even-split share) — downstream tooling picks its own
/// attribution; the app's own reports apply the even-split separately.
///
/// [subtreeRootId] filters to a subtree (e.g. only the Work subtree → just work
/// tasks); null exports everything. A block appears once per activity of its set
/// that passes the filter, so a filtered export naturally drops unrelated blocks.
///
/// Times are ISO-8601 in the block's own (local) instants. The open block's end
/// is [now]; if [now] is null the open block is omitted (an unfinished interval
/// has no meaningful end to export).
String buildCsv({
  required List<Block> blocks,
  required ActivityTree tree,
  DateTime? now,
  String? subtreeRootId,
}) {
  final allowed = subtreeRootId == null ? null : tree.subtreeIds(subtreeRootId).toSet();

  final rows = <String>['start,end,duration_s,activity,comment'];

  // Chronological order reads better in a spreadsheet than newest-first.
  for (final block in blocks.reversed) {
    final end = block.end ?? now;
    if (end == null) continue; // open block, no clock supplied
    final durationS = end.difference(block.start).inSeconds;

    for (final a in block.activities) {
      if (allowed != null && !allowed.contains(a.syncId)) continue;
      rows.add(
        [
          _f(block.start.toIso8601String()),
          _f(end.toIso8601String()),
          '$durationS',
          _f(tree.pathName(a.syncId)),
          _f(block.comment ?? ''),
        ].join(','),
      );
    }
  }

  return '${rows.join('\r\n')}\r\n';
}

/// RFC-4180 field escaping: quote when the value contains a comma, quote,
/// CR or LF, doubling embedded quotes.
String _f(String value) {
  if (value.contains(RegExp('[",\r\n]'))) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}
