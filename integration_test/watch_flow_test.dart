// The Wear OS shell on a real Wear device. Run with `just e2e-watch`.
//
// This replaces the old arrangement, where e2e-watch ran the *phone* flow on the
// watch and was expected to fail on layout. There is a watch shell now, so the
// watch emulator gets a suite that belongs to it.
//
// The peer is a FakeWearBridge: a real exchange needs two paired devices, which
// a single emulator is not. What runs here is everything the watch itself
// decides — rendering at the real screen size, applying a snapshot, and turning
// a tap into a local boundary plus a relay. Actual delivery between two devices
// is in the manual pass.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:integration_test/integration_test.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/data/drift_repositories.dart';
import 'package:time_tracker/data/sync_store.dart';
import 'package:time_tracker/data/providers.dart';
import 'package:time_tracker/data/wear_bridge.dart';
import 'package:time_tracker/data/wear_sync.dart';
import 'package:time_tracker/domain/wear_protocol.dart';
import 'package:time_tracker/watch/watch_app.dart';

import '../test/support/fake_wear_bridge.dart';
import '../test/support/flow_harness.dart';

/// A switch tile, by the activity it switches to — keyed, because the running
/// activity's name also appears in the hero above it, in the same scroll view.
Finder tile(String syncId) => find.byKey(ValueKey('tile-$syncId'));

/// Tiles arm on first tap and act on the second; a misfire on a wrist is
/// neither visible nor easy to undo.
Future<void> tapTile(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await settle(tester);
  await tester.tap(finder);
  await settle(tester);
}

/// Pump until [ready], or give up and let the assertion that follows report it.
///
/// Needed because a real device has a real database. The watch's first snapshot
/// request is sent from a fire-and-forget retry loop that reads the stored
/// credential version on its way out, so "has it asked yet" is a question about
/// elapsed time rather than about `start()` having returned. Waiting on the
/// condition rather than on a fixed number of frames keeps that explicit — and
/// keeps the test fast when the answer arrives immediately.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() ready, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!ready() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('adopts a phone snapshot, then switches and relays', (tester) async {
    final bridge = FakeWearBridge();
    addTearDown(bridge.dispose);

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          wearBridgeProvider.overrideWithValue(bridge),
          isWatchProvider.overrideWithValue(true),
        ],
        child: const WatchApp(),
      ),
    );
    await settle(tester);

    // Nothing until the phone says otherwise.
    expect(find.textContaining('bookmark on the phone'), findsOneWidget);

    // The watch's own sync service, driven by the fake peer.
    final sync = WearSyncService(
      bridge: bridge,
      activities: DriftActivityRepository(db),
      changes: DriftChangeRepository(db),
      syncStore: SyncStore(db),
      isWatch: true,
    );
    addTearDown(sync.dispose);
    await sync.start();

    await pumpUntil(tester, () => bridge.sent.whereType<SnapshotRequest>().isNotEmpty);
    expect(
      bridge.sent.whereType<SnapshotRequest>(),
      isNotEmpty,
      reason: 'the watch asks the phone for the bookmark set on start',
    );

    // emit + settle rather than receive: this binding happens to use a real
    // clock, but the widget-test one does not, and the difference is not worth
    // depending on.
    bridge.emit(
      const BookmarkSnapshot(
        activities: [
          WearActivity(syncId: 'a', name: 'Deep work', color: '#4F8FEE'),
          WearActivity(syncId: 'b', name: 'Email', color: '#EE7C4F'),
        ],
      ),
    );
    await settle(tester);

    expect(tile('a'), findsOneWidget);
    expect(tile('b'), findsOneWidget);
    expect(find.text('nothing tracked'), findsOneWidget);

    // A tap has to do both halves: record locally so the watch is honest with
    // the phone out of range, and relay so the phone converges on the same row.
    await tapTile(tester, tile('a'));

    final rows = await DriftChangeRepository(db).loadChanges();
    expect(rows, hasLength(1));
    expect(bridge.sent.whereType<SwitchRequest>().single.changeSyncId, rows.single.syncId);
    expect(find.text('nothing tracked'), findsNothing);

    // Everything above rendered on the real watch screen without overflowing.
    expect(tester.takeException(), isNull);

    await disposeApp(tester);
  });
}
