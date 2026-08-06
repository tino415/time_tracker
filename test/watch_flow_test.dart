// The Wear OS shell at the size it actually runs: 227x227, which is what the
// e2e run on the Wear emulator measured. The phone layout does not fit here —
// that is the whole reason this shell exists — so these tests are as much about
// "does it fit" as "does it work".

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/data/drift_repositories.dart';
import 'package:time_tracker/data/providers.dart';
import 'package:time_tracker/data/wear_bridge.dart';
import 'package:time_tracker/data/wear_sync.dart';
import 'package:time_tracker/domain/unsorted.dart';
import 'package:time_tracker/domain/wear_protocol.dart';
import 'package:time_tracker/watch/watch_app.dart';

import 'support/fake_wear_bridge.dart';
import 'support/flow_harness.dart';

/// The Wear emulator's logical size.
const _watch = Size(227, 227);

/// A tile in the switch list. Scoped, because once an activity is running its
/// name also appears in the header — the two are different affordances.
Finder tile(String name) =>
    find.descendant(of: find.byType(ListView), matching: find.text(name));

Future<AppDatabase> pumpWatch(
  WidgetTester tester,
  FakeWearBridge bridge, {
  Future<void> Function(AppDatabase db)? seed,
}) async {
  tester.view.physicalSize = _watch;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  if (seed != null) await seed(db);

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
  return db;
}

Future<void> seedBookmarks(AppDatabase db) async {
  final activities = DriftActivityRepository(db);
  await activities.createActivity(name: 'Deep work', color: '#4F8FEE', bookmarked: true);
  await activities.createActivity(name: 'Email', color: '#EE7C4F', bookmarked: true);
  // Not a bookmark: must not reach the watch's list.
  await activities.createActivity(name: 'Admin', color: '#888888');
}

void main() {
  testWidgets('lists the bookmarked activities and nothing else', (tester) async {
    final bridge = FakeWearBridge();
    addTearDown(bridge.dispose);
    await pumpWatch(tester, bridge, seed: seedBookmarks);

    expect(find.text('Deep work'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Admin'), findsNothing);
    expect(find.text('nothing tracked'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await disposeApp(tester);
  });

  testWidgets('shows what the phone is tracking', (tester) async {
    // The regression this guards: the watch read "nothing tracked" while the
    // phone was running, because the snapshot's current block was discarded.
    final bridge = FakeWearBridge();
    addTearDown(bridge.dispose);
    final db = await pumpWatch(tester, bridge, seed: seedBookmarks);

    final sync = WearSyncService(
      bridge: bridge,
      activities: DriftActivityRepository(db),
      changes: DriftChangeRepository(db),
      isWatch: true,
    );
    addTearDown(sync.dispose);
    await sync.start();

    // emit + settle, not receive: receive awaits a real timer, and inside
    // testWidgets timers only fire when the tester pumps.
    bridge.emit(BookmarkSnapshot(
      activities: const [WearActivity(syncId: 'a', name: 'Deep work', color: '#4F8FEE')],
      current: CurrentBlock(
        changeId: 'phone-change',
        startedAt: DateTime.now().subtract(const Duration(minutes: 12)),
        activity: const WearActivity(syncId: 'a', name: 'Deep work', color: '#4F8FEE'),
      ),
    ));
    await settle(tester);

    expect(find.text('nothing tracked'), findsNothing);
    // Named in the header as well as listed as a tile.
    expect(find.text('Deep work'), findsWidgets);

    await disposeApp(tester);
  });

  testWidgets('tapping a tile starts tracking it and relays the switch', (tester) async {
    final bridge = FakeWearBridge();
    addTearDown(bridge.dispose);
    final db = await pumpWatch(tester, bridge, seed: seedBookmarks);

    await tester.tap(tile('Deep work'));
    await settle(tester);

    final changes = DriftChangeRepository(db);
    final rows = await changes.loadChanges();
    expect(rows, hasLength(1));

    final relayed = bridge.sent.whereType<SwitchRequest>().single;
    expect(relayed.changeSyncId, rows.single.syncId);

    // The header now shows what is running.
    expect(find.text('nothing tracked'), findsNothing);

    await disposeApp(tester);
  });

  testWidgets('the running activity is marked and not re-tappable', (tester) async {
    final bridge = FakeWearBridge();
    addTearDown(bridge.dispose);
    final db = await pumpWatch(tester, bridge, seed: seedBookmarks);

    await tester.tap(tile('Deep work'));
    await settle(tester);
    final before = (await DriftChangeRepository(db).loadChanges()).length;

    // Tapping what is already running would only split the block.
    await tester.tap(tile('Deep work'));
    await settle(tester);

    expect((await DriftChangeRepository(db).loadChanges()).length, before);

    await disposeApp(tester);
  });

  testWidgets('start now works with no bookmarks at all', (tester) async {
    final bridge = FakeWearBridge();
    addTearDown(bridge.dispose);
    final db = await pumpWatch(tester, bridge);

    // The screen is never empty: "start now" is the action that matters on a
    // watch, and it needs no catalogue.
    expect(tile('start now'), findsOneWidget);
    expect(find.textContaining('bookmark on the phone'), findsOneWidget);

    await tester.tap(tile('start now'));
    await settle(tester);

    // The catch-all is created locally — the phone only ever sends *bookmarked*
    // activities, and this one is not a bookmark.
    final local = await DriftActivityRepository(db).loadActivities();
    expect(local.single.syncId, kUnsortedActivityId);
    final rows = await DriftChangeRepository(db).loadChanges();
    expect(rows, hasLength(1));
    expect(bridge.sent.whereType<SwitchRequest>().single.activityId, kUnsortedActivityId);

    await disposeApp(tester);
  });

  testWidgets('a long bookmark list scrolls without overflowing', (tester) async {
    final bridge = FakeWearBridge();
    addTearDown(bridge.dispose);
    await pumpWatch(tester, bridge, seed: (db) async {
      final activities = DriftActivityRepository(db);
      for (var i = 0; i < 12; i++) {
        await activities.createActivity(
          name: 'Activity number $i with a long name',
          color: '#4F8FEE',
          bookmarked: true,
        );
      }
    });

    // 12 tall tiles cannot fit 227px — the list must scroll rather than assert.
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(ListView), const Offset(0, -120));
    await settle(tester);
    expect(tester.takeException(), isNull);

    await disposeApp(tester);
  });
}
