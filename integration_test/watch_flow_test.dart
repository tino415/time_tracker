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
import 'package:time_tracker/data/providers.dart';
import 'package:time_tracker/data/wear_bridge.dart';
import 'package:time_tracker/data/wear_sync.dart';
import 'package:time_tracker/domain/wear_protocol.dart';
import 'package:time_tracker/watch/watch_app.dart';

import '../test/support/fake_wear_bridge.dart';
import '../test/support/flow_harness.dart';

Finder tile(String name) =>
    find.descendant(of: find.byType(ListView), matching: find.text(name));

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
    expect(find.textContaining('bookmark activities'), findsOneWidget);

    // The watch's own sync service, driven by the fake peer.
    final sync = WearSyncService(
      bridge: bridge,
      activities: DriftActivityRepository(db),
      changes: DriftChangeRepository(db),
      isWatch: true,
    );
    addTearDown(sync.dispose);
    await sync.start();

    expect(bridge.sent.whereType<SnapshotRequest>(), isNotEmpty,
        reason: 'the watch asks the phone for the bookmark set on start');

    await bridge.receive(const BookmarkSnapshot(activities: [
      WearActivity(syncId: 'a', name: 'Deep work', color: '#4F8FEE'),
      WearActivity(syncId: 'b', name: 'Email', color: '#EE7C4F'),
    ]));
    await settle(tester);

    expect(tile('Deep work'), findsOneWidget);
    expect(tile('Email'), findsOneWidget);
    expect(find.text('nothing tracked'), findsOneWidget);

    // A tap has to do both halves: record locally so the watch is honest with
    // the phone out of range, and relay so the phone converges on the same row.
    await tester.tap(tile('Deep work'));
    await settle(tester);

    final rows = await DriftChangeRepository(db).loadChanges();
    expect(rows, hasLength(1));
    expect(bridge.sent.whereType<SwitchRequest>().single.changeSyncId, rows.single.syncId);
    expect(find.text('nothing tracked'), findsNothing);

    // Everything above rendered on the real watch screen without overflowing.
    expect(tester.takeException(), isNull);

    await disposeApp(tester);
  });
}
