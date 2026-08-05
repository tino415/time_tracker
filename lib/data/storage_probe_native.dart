import 'storage_status.dart';

/// Off the web the database is an ordinary file — nothing to request, nothing
/// that can be evicted.
Future<StorageStatus> probeStorage() async => StorageStatus.native;
