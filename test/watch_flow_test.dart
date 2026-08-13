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
import 'package:time_tracker/data/sync_store.dart';
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
/// A switch tile, by the activity it switches to.
///
/// Keyed rather than found by text: the running activity's name also appears in
/// the hero above, and both live in the same scroll view.
Finder tile(String syncId) => find.byKey(ValueKey('tile-$syncId'));

/// Tiles arm on first tap and act on the second — a watch is operated by feel,
/// and a misfire there is neither visible nor easy to undo.
Future<void> tapTile(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await settle(tester);
  await tester.tap(finder);
  await settle(tester);
}

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

/// Ids of the seeded activities, so tests can address tiles by identity.
late String deepWorkId;
late String emailId;

Future<void> seedBookmarks(AppDatabase db) async {
  final activities = DriftActivityRepository(db);
  deepWorkId =
      (await activities.createActivity(name: 'Deep work', color: '#4F8FEE', bookmarked: true))
          .syncId;
  emailId =
      (await activities.createActivity(name: 'Email', color: '#EE7C4F', bookmarked: true)).syncId;
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
      syncStore: SyncStore(db),
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

    await tapTile(tester, tile(deepWorkId));

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

    await tapTile(tester, tile(deepWorkId));
    final before = (await DriftChangeRepository(db).loadChanges()).length;

    // Tapping what is already running would only split the block.
    await tapTile(tester, tile(deepWorkId));

    expect((await DriftChangeRepository(db).loadChanges()).length, before);

    await disposeApp(tester);
  });

  testWidgets('start now works with no bookmarks at all', (tester) async {
    final bridge = FakeWearBridge();
    addTearDown(bridge.dispose);
    final db = await pumpWatch(tester, bridge);

    // The screen is never empty: "start now" is the action that matters on a
    // watch, and it needs no catalogue.
    expect(tile(kUnsortedActivityId), findsOneWidget);
    expect(find.text('start now'), findsOneWidget);
    expect(find.textContaining('bookmark on the phone'), findsOneWidget);

    await tapTile(tester, tile(kUnsortedActivityId));

    // The catch-all is created locally — the phone only ever sends *bookmarked*
    // activities, and this one is not a bookmark.
    final local = await DriftActivityRepository(db).loadActivities();
    expect(local.single.syncId, kUnsortedActivityId);
    final rows = await DriftChangeRepository(db).loadChanges();
    expect(rows, hasLength(1));
    expect(bridge.sent.whereType<SwitchRequest>().single.activityId, kUnsortedActivityId);

    await disposeApp(tester);
  });

  testWidgets('the timer stays clear of the round screen edge, and does not scroll', (tester) async {
    // Reported: the clock was invisible, cut off by the curve. A circular
    // display narrows towards the top, and the hero had been sitting at the top
    // of a scroll view — flush against exactly where it cuts.
    final bridge = FakeWearBridge();
    addTearDown(bridge.dispose);
    await pumpWatch(tester, bridge, seed: seedBookmarks);

    await tapTile(tester, tile(deepWorkId));

    final clock = find.textContaining(':');
    expect(clock, findsWidgets);
    final rect = tester.getRect(clock.first);

    // Inside the inscribed square of a 227px circle: anything within ~15% of an
    // edge risks the curve.
    const margin = 227 * 0.07;
    expect(rect.top, greaterThan(margin), reason: 'clipped by the top curve');
    expect(rect.left, greaterThan(0));
    expect(rect.right, lessThan(227));

    // And it is not inside the scrollable, so it cannot be scrolled away from.
    expect(
      find.descendant(of: find.byType(ListView), matching: clock.first),
      findsNothing,
      reason: 'the clock is the reason to glance at a watch; it must stay put',
    );

    await disposeApp(tester);
  });

  testWidgets('one tap arms, it does not switch', (tester) async {
    // A watch is operated by feel, with big targets under a thumb. A misfire
    // there is neither visible nor easy to undo, so the first tap only asks.
    final bridge = FakeWearBridge();
    addTearDown(bridge.dispose);
    final db = await pumpWatch(tester, bridge, seed: seedBookmarks);

    await tester.tap(tile(deepWorkId));
    await settle(tester);

    expect(await DriftChangeRepository(db).loadChanges(), isEmpty);
    expect(bridge.sent.whereType<SwitchRequest>(), isEmpty);
    expect(find.text('tap again'), findsOneWidget);

    await tester.tap(tile(deepWorkId));
    await settle(tester);
    expect(await DriftChangeRepository(db).loadChanges(), hasLength(1));

    await disposeApp(tester);
  });

  testWidgets('arming one tile disarms another', (tester) async {
    final bridge = FakeWearBridge();
    addTearDown(bridge.dispose);
    final db = await pumpWatch(tester, bridge, seed: seedBookmarks);

    await tester.tap(tile(deepWorkId));
    await settle(tester);
    await tester.tap(tile(emailId));
    await settle(tester);

    // Only one question at a time, and confirming Email must not switch to
    // whatever was armed before it.
    expect(find.text('tap again'), findsOneWidget);
    await tester.tap(tile(emailId));
    await settle(tester);

    final rows = await DriftChangeRepository(db).loadChanges();
    expect(rows, hasLength(1));
    expect(await DriftChangeRepository(db).activityIdsForChange(rows.single.syncId), [emailId]);

    await disposeApp(tester);
  });

  testWidgets('two unnamed blocks can be started in a row', (tester) async {
    // Reported from wearing the watch: the tile used to be disabled while an
    // unnamed block ran, and the controller would have no-opped anyway. Two in a
    // row are two different things to name later.
    final bridge = FakeWearBridge();
    addTearDown(bridge.dispose);
    final db = await pumpWatch(tester, bridge);

    await tapTile(tester, tile(kUnsortedActivityId));
    expect(find.text('start another'), findsOneWidget);

    await tapTile(tester, tile(kUnsortedActivityId));

    final rows = await DriftChangeRepository(db).loadChanges();
    expect(rows, hasLength(2));
    expect(bridge.sent.whereType<SwitchRequest>(), hasLength(2));

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
