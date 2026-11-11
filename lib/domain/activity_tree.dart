import '../data/database.dart';

/// An in-memory view over the activity catalogue's hierarchy. Built once from a
/// flat `List<Activity>` and used everywhere a parent/child/ancestor/subtree
/// relation is needed: the Activities tree screen, per-category report roll-up,
/// and subtree-filtered CSV export.
///
/// Only *live* (non-tombstoned) activities should be passed in — deletion is a
/// soft-delete in the DB, but a deleted node has no place in the tree.
class ActivityTree {
  ActivityTree._(this.byId, this._childIds, this.rootIds);

  /// Every activity, keyed by [Activity.syncId].
  final Map<String, Activity> byId;

  /// parent id -> child ids, in name order. Top-level ids live under [rootIds].
  final Map<String, List<String>> _childIds;

  /// Top-level activity ids (parentId == null / missing), in name order.
  final List<String> rootIds;

  static ActivityTree build(List<Activity> activities) {
    final byId = {for (final a in activities) a.syncId: a};
    final childIds = <String, List<String>>{};
    final rootIds = <String>[];

    final sorted = [...activities]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    for (final a in sorted) {
      final parent = a.parentId;
      // A dangling parent (parent deleted/missing) is treated as a root so the
      // node never vanishes from the tree.
      if (parent == null || !byId.containsKey(parent)) {
        rootIds.add(a.syncId);
      } else {
        (childIds[parent] ??= []).add(a.syncId);
      }
    }
    return ActivityTree._(byId, childIds, rootIds);
  }

  Activity? operator [](String id) => byId[id];

  List<String> childrenOf(String id) => _childIds[id] ?? const [];

  bool isLeaf(String id) => childrenOf(id).isEmpty;

  /// Self + every ancestor up to the root. Order: self first, root last.
  /// Cycle-guarded (a corrupt parent chain can't loop forever).
  List<String> ancestorIdsInclusive(String id) {
    final out = <String>[];
    final seen = <String>{};
    var cur = id;
    while (byId.containsKey(cur) && seen.add(cur)) {
      out.add(cur);
      final parent = byId[cur]!.parentId;
      if (parent == null || !byId.containsKey(parent)) break;
      cur = parent;
    }
    return out;
  }

  /// [rootId] + every descendant (depth-first, name order).
  List<String> subtreeIds(String rootId) {
    final out = <String>[];
    void walk(String id) {
      out.add(id);
      for (final c in childrenOf(id)) {
        walk(c);
      }
    }

    if (byId.containsKey(rootId)) walk(rootId);
    return out;
  }

  /// Human-readable path, root first: `Work / Client / CU-1234`.
  String pathName(String id, {String separator = ' / '}) {
    final chain = ancestorIdsInclusive(id).reversed.map((i) => byId[i]?.name ?? '?').toList();
    return chain.join(separator);
  }

  /// Depth from the root (0 = top level), for indenting the tree view.
  int depthOf(String id) => ancestorIdsInclusive(id).length - 1;

  /// All ids in a stable depth-first, name-ordered walk (roots then children).
  List<String> flattened() {
    final out = <String>[];
    void walk(String id) {
      out.add(id);
      for (final c in childrenOf(id)) {
        walk(c);
      }
    }

    for (final r in rootIds) {
      walk(r);
    }
    return out;
  }

  /// [flattened] without the children of any id not in [expanded].
  List<String> visibleIds(Set<String> expanded) {
    final out = <String>[];
    void walk(String id) {
      out.add(id);
      if (!expanded.contains(id)) return;
      for (final c in childrenOf(id)) {
        walk(c);
      }
    }

    for (final r in rootIds) {
      walk(r);
    }
    return out;
  }
}
