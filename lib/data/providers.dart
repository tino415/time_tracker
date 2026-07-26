import 'package:flutter_riverpod/flutter_riverpod.dart';

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
