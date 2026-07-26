import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/activity_tree.dart';
import '../domain/block.dart';
import 'database.dart';
import 'drift_repositories.dart';
import 'repositories.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final activityRepositoryProvider = Provider<ActivityRepository>((ref) {
  return DriftActivityRepository(ref.watch(databaseProvider));
});

final changeRepositoryProvider = Provider<ChangeRepository>((ref) {
  return DriftChangeRepository(ref.watch(databaseProvider));
});

/// Live activity catalogue (non-tombstoned, name order).
final activitiesStreamProvider = StreamProvider<List<Activity>>((ref) {
  return ref.watch(activityRepositoryProvider).watchActivities();
});

/// Live timeline of changes (newest first).
final changesStreamProvider = StreamProvider<List<ActivityChange>>((ref) {
  return ref.watch(changeRepositoryProvider).watchChanges();
});

/// Live m:n join rows (change id -> activity id) across all changes.
final changeLinksStreamProvider =
    StreamProvider<List<ActivityChangeActivity>>((ref) {
  return ref.watch(changeRepositoryProvider).watchChangeActivityLinks();
});

/// Activities keyed by syncId (empty while the stream is loading).
final activitiesByIdProvider = Provider<Map<String, Activity>>((ref) {
  final list = ref.watch(activitiesStreamProvider).valueOrNull ?? const [];
  return {for (final a in list) a.syncId: a};
});

/// The activity hierarchy, rebuilt whenever the catalogue changes.
final activityTreeProvider = Provider<ActivityTree>((ref) {
  final list = ref.watch(activitiesStreamProvider).valueOrNull ?? const [];
  return ActivityTree.build(list);
});

/// change id -> its activity ids, from the live join rows.
final activityIdsByChangeProvider = Provider<Map<String, List<String>>>((ref) {
  final links = ref.watch(changeLinksStreamProvider).valueOrNull ?? const [];
  final map = <String, List<String>>{};
  for (final l in links) {
    (map[l.activityChangeId] ??= []).add(l.activityId);
  }
  return map;
});

/// The derived timeline (blocks, newest first; open block at index 0). Recomputes
/// reactively from changes + join rows + the activity catalogue.
final blocksProvider = Provider<List<Block>>((ref) {
  final changes = ref.watch(changesStreamProvider).valueOrNull ?? const [];
  final byChange = ref.watch(activityIdsByChangeProvider);
  final byId = ref.watch(activitiesByIdProvider);
  return deriveBlocks(
    changes: changes,
    activityIdsByChange: byChange,
    activitiesById: byId,
  );
});

/// The current/open block (what's tracking now), or null on an empty timeline.
final currentBlockProvider = Provider<Block?>((ref) {
  return currentBlock(ref.watch(blocksProvider));
});
