import '../data/database.dart';

/// A derived interval on the timeline. Blocks are not stored — they are computed
/// from consecutive [ActivityChange]s: a block runs from one change's
/// `changedAt` until the next change's `changedAt`, carrying that change's set of
/// active activities. The most recent block is *open* ([end] == null): it is
/// what's tracking right now (something is always tracking).
///
/// Usually [activities] has one entry. More than one is the retrospective
/// "forgot to switch" annotation — sequential-but-unknown-split, so for reports
/// the duration is divided evenly among them (see reporting.dart).
class Block {
  const Block({
    required this.change,
    required this.start,
    required this.end,
    required this.activities,
  });

  final ActivityChange change;
  final DateTime start;

  /// End of the block, or null for the current/open block.
  final DateTime? end;

  /// The active set, in name order. May be empty if the change's activities were
  /// all deleted (defensive — normally at least one).
  final List<Activity> activities;

  bool get isOpen => end == null;

  String? get comment => change.comment;

  /// Wall-clock length. For the open block this measures up to [now].
  Duration duration(DateTime now) => (end ?? now).difference(start);
}

/// Derive the ordered timeline from raw rows.
///
/// [changes] may be in any order; [activityIdsByChange] maps a change's syncId
/// to its activity ids; [activitiesById] resolves those to live [Activity]s
/// (ids missing from the map — e.g. a deleted activity — are dropped).
///
/// Returns blocks **newest first** (open block, if any, at index 0) — the order
/// the timeline and "Now" screen consume. Reverse for chronological order.
List<Block> deriveBlocks({
  required List<ActivityChange> changes,
  required Map<String, List<String>> activityIdsByChange,
  required Map<String, Activity> activitiesById,
}) {
  if (changes.isEmpty) return const [];

  // Ties (same-instant boundaries) fall back to the id so the derived order is
  // stable and matches the repository's own ordering.
  final asc = [...changes]..sort((a, b) {
    final byTime = a.changedAt.compareTo(b.changedAt);
    return byTime != 0 ? byTime : a.syncId.compareTo(b.syncId);
  });

  final blocks = <Block>[];
  for (var i = 0; i < asc.length; i++) {
    final change = asc[i];
    final end = i + 1 < asc.length ? asc[i + 1].changedAt : null;

    final acts = <Activity>[
      for (final id in activityIdsByChange[change.syncId] ?? const <String>[])
        if (activitiesById[id] != null) activitiesById[id]!,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    blocks.add(Block(change: change, start: change.changedAt, end: end, activities: acts));
  }

  return blocks.reversed.toList();
}

/// The current (open) block — the newest change's set — or null if the timeline
/// is empty. Convenience over [deriveBlocks]`.first`.
Block? currentBlock(List<Block> newestFirst) =>
    newestFirst.isEmpty ? null : newestFirst.first;
