// The shell's half of automatic syncing: starting the service once it exists.
//
// Scheduling is auto_sync_test.dart's subject. This is the one thing the shell
// owns, and the one that is silent when it breaks: the service is null at the
// first frame, because whether sync is configured is read from a stream that has
// not emitted yet — and on the watch the token arrives later still, over the
// Wear relay. A shell that reads once at boot therefore starts nothing, on
// either form factor, and the only surviving trigger is the resume one, which
// fires before the edit it should have carried.

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/data/auto_sync.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/data/providers.dart';
import 'package:time_tracker/data/sync_service.dart';
import 'package:time_tracker/data/wear_bridge.dart';
import 'package:time_tracker/main.dart';

import 'support/fake_wear_bridge.dart';

/// Counts round trips, so these tests are about whether the service was ever
/// started rather than what it exchanges.
class _CountingSync implements SyncService {
  int calls = 0;

  @override
  Future<SyncResult> syncNow() async {
    calls++;
    return SyncResult.none;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Stands in for the token stream's first emission: false is the state every
/// launch begins in, whatever is already stored on the device.
final _configured = StateProvider<bool>((ref) => false);

void main() {
  late _CountingSync sync;
  late AutoSyncService auto;

  setUp(() {
    sync = _CountingSync();
    auto = AutoSyncService(sync: sync, localChanges: const Stream<Object?>.empty());
  });

  tearDown(() => auto.dispose());

  Future<ProviderContainer> bootRoot(WidgetTester tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          wearBridgeProvider.overrideWithValue(FakeWearBridge()),
          autoSyncProvider.overrideWith((ref) => ref.watch(_configured) ? auto : null),
        ],
        child: const TimeTrackerRoot(isWatch: false),
      ),
    );
    await tester.pump();
    return ProviderScope.containerOf(tester.element(find.byType(TimeTrackerRoot)));
  }

  testWidgets('starts syncing when the token arrives, not only if it is there at boot', (
    tester,
  ) async {
    final container = await bootRoot(tester);
    expect(sync.calls, 0, reason: 'there is no service to start yet');

    container.read(_configured.notifier).state = true;
    await tester.pump();

    expect(sync.calls, 1, reason: 'the service appeared after the first frame and must be started');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('starts syncing at boot when the service is already there', (tester) async {
    sync = _CountingSync();
    auto = AutoSyncService(sync: sync, localChanges: const Stream<Object?>.empty());

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          wearBridgeProvider.overrideWithValue(FakeWearBridge()),
          autoSyncProvider.overrideWithValue(auto),
        ],
        child: const TimeTrackerRoot(isWatch: false),
      ),
    );
    await tester.pump();

    expect(sync.calls, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  });
}
