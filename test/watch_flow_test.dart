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

/// Swipe [dx] across the shell over [over] — negative is right-to-left.
///
/// The shell reads travel *and* lift-off velocity, so a swipe has to be moved
/// the way a thumb moves: evenly, over stated time. Two things this gets right
/// that the obvious spellings do not.
///
/// [over] is stamped on the pointer events, not merely pumped between them.
/// Velocity comes from event timestamps, which default to zero however far the
/// clock is advanced — unstamped, every swipe lifts at 0px/s and the fling gate
/// goes untested.
///
/// And the travel is spread evenly rather than led by one jump clearing
/// `kTouchSlop`. A big first move followed by small ones fits a decelerating
/// curve, which for a short swipe reports a velocity that is far too low or
/// outright the wrong sign. `DragStartBehavior.down` hands back the offsets
/// banked before the recognizer was accepted, so an even drag still delivers
/// exactly [dx].
Future<void> swipe(
  WidgetTester tester,
  double dx, {
  Duration over = const Duration(milliseconds: 100),
}) async {
  const steps = 8;
  final step = Duration(microseconds: over.inMicroseconds ~/ steps);
  final gesture = await tester.startGesture(shellCentre(tester));
  await tester.pump();

  var at = Duration.zero;
  for (var i = 0; i < steps; i++) {
    at += step;
    await gesture.moveBy(Offset(dx / steps, 0), timeStamp: at);
    await tester.pump(step);
  }
  await gesture.up(timeStamp: at);
  await settle(tester);
}

Offset shellCentre(WidgetTester tester) =>
    tester.getCenter(find.byKey(const ValueKey('watch-shell')));

Future<void> openMenu(WidgetTester tester) => swipe(tester, -80);

Future<void> openStartTime(WidgetTester tester) async {
  await openMenu(tester);
  await tester.tap(find.byKey(const ValueKey('menu-edit-start')));
  await settle(tester);
}

Future<void> openSwap(WidgetTester tester) async {
  await openMenu(tester);
  await tester.tap(find.byKey(const ValueKey('menu-swap')));
  await settle(tester);
}

/// Whether a back press would leave the app rather than unwind a pane.
///
/// By predicate and scoped to the shell: `find.byType` matches nothing for a
/// generic widget class, and this must read the shell's own [PopScope] rather
/// than whatever the app scaffolding wraps around it.
bool backWouldExit(WidgetTester tester) => tester
    .widget<PopScope>(
      find.ancestor(
        of: find.byKey(const ValueKey('watch-shell')),
        matching: find.byWidgetPredicate((w) => w is PopScope),
      ),
    )
    .canPop;

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
  deepWorkId = (await activities.createActivity(
    name: 'Deep work',
    color: '#4F8FEE',
    bookmarked: true,
  )).syncId;
  emailId = (await activities.createActivity(
    name: 'Email',
    color: '#EE7C4F',
    bookmarked: true,
  )).syncId;
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
    bridge.emit(
      BookmarkSnapshot(
        activities: const [WearActivity(syncId: 'a', name: 'Deep work', color: '#4F8FEE')],
        current: CurrentBlock(
          changeId: 'phone-change',
          startedAt: DateTime.now().subtract(const Duration(minutes: 12)),
          activity: const WearActivity(syncId: 'a', name: 'Deep work', color: '#4F8FEE'),
        ),
      ),
    );
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

  testWidgets('the timer stays clear of the round screen edge, and does not scroll', (
    tester,
  ) async {
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
    await pumpWatch(
      tester,
      bridge,
      seed: (db) async {
        final activities = DriftActivityRepository(db);
        for (var i = 0; i < 12; i++) {
          await activities.createActivity(
            name: 'Activity number $i with a long name',
            color: '#4F8FEE',
            bookmarked: true,
          );
        }
      },
    );

    // 12 tall tiles cannot fit 227px — the list must scroll rather than assert.
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(ListView), const Offset(0, -120));
    await settle(tester);
    expect(tester.takeException(), isNull);
    // And the shell's horizontal drag must not have taken the vertical one.
    expect(find.byKey(const ValueKey('menu-edit-start')), findsNothing);

    await disposeApp(tester);
  });

  testWidgets('a right-to-left swipe opens the block menu', (tester) async {
    final bridge = FakeWearBridge();
    addTearDown(bridge.dispose);
    await pumpWatch(tester, bridge, seed: seedBookmarks);
    await tapTile(tester, tile(deepWorkId));

    await openMenu(tester);

    expect(find.byKey(const ValueKey('menu-edit-start')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu-swap')), findsOneWidget);
    // A pane, not an overlay: the switch list is gone while the menu is up.
    expect(tile(deepWorkId), findsNothing);

    await disposeApp(tester);
  });

  testWidgets('the menu does not open with nothing tracked', (tester) async {
    // Both its actions edit the running block, and an empty timeline has none.
    final bridge = FakeWearBridge();
    addTearDown(bridge.dispose);
    await pumpWatch(tester, bridge, seed: seedBookmarks);

    await openMenu(tester);

    expect(find.byKey(const ValueKey('menu-edit-start')), findsNothing);
    expect(find.byKey(const ValueKey('menu-hint')), findsNothing);
    expect(tile(deepWorkId), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('a short swipe dawdles its way out of navigating', (tester) async {
    // The same 40px the flick below navigates on, taken slowly: short of the
    // distance gate, so only speed is left to carry it, and it has none. A
    // thumb dragged across the glass on the way to a tile.
    final bridge = FakeWearBridge();
    addTearDown(bridge.dispose);
    await pumpWatch(tester, bridge, seed: seedBookmarks);
    await tapTile(tester, tile(deepWorkId));

    await swipe(tester, -40, over: const Duration(milliseconds: 200));

    expect(find.byKey(const ValueKey('menu-edit-start')), findsNothing);
    expect(tile(emailId), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('a flick navigates only once it outruns what a tap can wander', (tester) async {
    // Both of these are far short of the distance gate, so the fling gate is
    // what decides them. A tap is rejected at kTouchSlop, which is about how
    // far a thumb rolls coming off a tile — so the flick has to want it more
    // than that, or the misfire the two-tap arming exists to catch becomes a
    // navigation instead.
    final bridge = FakeWearBridge();
    addTearDown(bridge.dispose);
    await pumpWatch(tester, bridge, seed: seedBookmarks);
    await tapTile(tester, tile(deepWorkId));

    await swipe(tester, -20, over: const Duration(milliseconds: 40));
    expect(find.byKey(const ValueKey('menu-edit-start')), findsNothing);

    await swipe(tester, -40, over: const Duration(milliseconds: 60));
    expect(find.byKey(const ValueKey('menu-edit-start')), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('a tap that drifts sideways still commits a tile', (tester) async {
    // The gesture a wrist actually makes. If the shell's horizontal drag took
    // the arena on any lateral movement, the tiles would stop working.
    final bridge = FakeWearBridge();
    addTearDown(bridge.dispose);
    final db = await pumpWatch(tester, bridge, seed: seedBookmarks);

    for (var i = 0; i < 2; i++) {
      final gesture = await tester.startGesture(tester.getCenter(tile(deepWorkId)));
      await tester.pump();
      await gesture.moveBy(const Offset(6, 0));
      await tester.pump();
      await gesture.up();
      await settle(tester);
    }

    expect(await DriftChangeRepository(db).loadChanges(), hasLength(1));

    await disposeApp(tester);
  });

  testWidgets('the hint appears only when there is a block to edit', (tester) async {
    // A swipe is invisible; the caret is the only thing on screen saying the
    // menu is there.
    final bridge = FakeWearBridge();
    addTearDown(bridge.dispose);
    await pumpWatch(tester, bridge, seed: seedBookmarks);

    expect(find.byKey(const ValueKey('menu-hint')), findsNothing);

    await tapTile(tester, tile(deepWorkId));

    expect(find.byKey(const ValueKey('menu-hint')), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('the two menu options lead to their own screens', (tester) async {
    final bridge = FakeWearBridge();
    addTearDown(bridge.dispose);
    await pumpWatch(tester, bridge, seed: seedBookmarks);
    await tapTile(tester, tile(deepWorkId));

    await openStartTime(tester);
    for (final m in [-15, -5, -1, 1, 5, 15]) {
      expect(find.byKey(ValueKey('nudge-$m')), findsOneWidget, reason: 'nudge $m missing');
    }
    expect(find.textContaining('started'), findsOneWidget);
    // Splitting the panel is the point: swapping is the other screen now.
    expect(find.byKey(ValueKey('repoint-$emailId')), findsNothing);

    await swipe(tester, 80);
    await tester.tap(find.byKey(const ValueKey('menu-swap')));
    await settle(tester);

    expect(find.byKey(ValueKey('repoint-$emailId')), findsOneWidget);
    expect(find.byKey(const ValueKey('nudge--5')), findsNothing);

    await disposeApp(tester);
  });

  testWidgets('swap pins what is running above what it can become', (tester) async {
    final bridge = FakeWearBridge();
    addTearDown(bridge.dispose);
    await pumpWatch(tester, bridge, seed: seedBookmarks);
    await tapTile(tester, tile(deepWorkId));

    await openSwap(tester);

    final pinned = find.byKey(const ValueKey('swap-current'));
    final candidate = find.byKey(ValueKey('repoint-$emailId'));
    expect(pinned, findsOneWidget);
    expect(candidate, findsOneWidget);
    // Swapping to what is already running would be a no-op the tap would have
    // to be told is a no-op.
    expect(find.byKey(ValueKey('repoint-$deepWorkId')), findsNothing);

    expect(tester.getRect(pinned).bottom, lessThan(tester.getRect(candidate).top));

    await disposeApp(tester);
  });

  testWidgets('a committed swap returns home', (tester) async {
    // Staying would reshuffle the rows under a finger still on the glass: the
    // pinned tile and the candidate list both re-derive from what is running.
    final bridge = FakeWearBridge();
    addTearDown(bridge.dispose);
    await pumpWatch(tester, bridge, seed: seedBookmarks);
    await tapTile(tester, tile(deepWorkId));

    await openSwap(tester);
    await tapTile(tester, find.byKey(ValueKey('repoint-$emailId')));

    expect(find.byKey(const ValueKey('swap-current')), findsNothing);
    expect(tile(deepWorkId), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('a left-to-right swipe goes back one level at a time', (tester) async {
    final bridge = FakeWearBridge();
    addTearDown(bridge.dispose);
    await pumpWatch(tester, bridge, seed: seedBookmarks);
    await tapTile(tester, tile(deepWorkId));

    await openStartTime(tester);
    await swipe(tester, 80);

    expect(find.byKey(const ValueKey('menu-edit-start')), findsOneWidget);
    expect(find.byKey(const ValueKey('nudge--5')), findsNothing);

    await swipe(tester, 80);

    expect(tile(deepWorkId), findsOneWidget);
    expect(find.byKey(const ValueKey('menu-edit-start')), findsNothing);

    await disposeApp(tester);
  });

  testWidgets('a left-to-right swipe at home does nothing', (tester) async {
    final bridge = FakeWearBridge();
    addTearDown(bridge.dispose);
    await pumpWatch(tester, bridge, seed: seedBookmarks);
    await tapTile(tester, tile(deepWorkId));

    await swipe(tester, 80);

    expect(tile(emailId), findsOneWidget);
    expect(tester.takeException(), isNull);

    await disposeApp(tester);
  });

  testWidgets('the physical back unwinds one level and only exits at home', (tester) async {
    // The watch has a hardware button, and it must not drop out of the app from
    // three screens in.
    final bridge = FakeWearBridge();
    addTearDown(bridge.dispose);
    await pumpWatch(tester, bridge, seed: seedBookmarks);
    await tapTile(tester, tile(deepWorkId));

    await openSwap(tester);
    expect(backWouldExit(tester), isFalse);

    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.byKey(const ValueKey('menu-swap')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(tile(deepWorkId), findsOneWidget);
    expect(backWouldExit(tester), isTrue);

    await disposeApp(tester);
  });

  testWidgets('the block ending unwinds the whole stack', (tester) async {
    // A one-level pop would land on a menu with nothing left to act on, and the
    // swap pane names the running block from activities.first.
    final bridge = FakeWearBridge();
    addTearDown(bridge.dispose);
    final db = await pumpWatch(tester, bridge, seed: seedBookmarks);
    await tapTile(tester, tile(deepWorkId));

    await openStartTime(tester);

    final changes = DriftChangeRepository(db);
    for (final c in await changes.loadChanges()) {
      await changes.deleteChange(c.syncId);
    }
    await settle(tester);

    expect(find.byKey(const ValueKey('nudge--5')), findsNothing);
    expect(find.byKey(const ValueKey('menu-swap')), findsNothing);
    expect(find.text('nothing tracked'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await disposeApp(tester);
  });

  testWidgets('arming does not survive leaving the screen it was started on', (tester) async {
    // Otherwise a tile armed, navigated away from and returned to inside the
    // four-second window commits on a single tap.
    final bridge = FakeWearBridge();
    addTearDown(bridge.dispose);
    final db = await pumpWatch(tester, bridge, seed: seedBookmarks);
    await tapTile(tester, tile(deepWorkId));
    final changes = DriftChangeRepository(db);
    final changeId = (await changes.loadChanges()).single.syncId;

    await openSwap(tester);
    await tester.tap(find.byKey(ValueKey('repoint-$emailId')));
    await settle(tester);
    expect(find.text('tap again'), findsOneWidget);

    await swipe(tester, 80);
    await tester.tap(find.byKey(const ValueKey('menu-swap')));
    await settle(tester);

    expect(find.text('tap again'), findsNothing);
    await tester.tap(find.byKey(ValueKey('repoint-$emailId')));
    await settle(tester);
    expect(await changes.activityIdsForChange(changeId), [deepWorkId]);

    await disposeApp(tester);
  });

  testWidgets('a nudge writes the new start locally and relays a RetimeRequest', (tester) async {
    final bridge = FakeWearBridge();
    addTearDown(bridge.dispose);
    final db = await pumpWatch(tester, bridge, seed: seedBookmarks);
    await tapTile(tester, tile(deepWorkId));
    final changes = DriftChangeRepository(db);
    final before = (await changes.loadChanges()).single;

    await openStartTime(tester);
    await tester.tap(find.byKey(const ValueKey('nudge--5')));
    await settle(tester);

    final after = (await changes.loadChanges()).single;
    expect(after.syncId, before.syncId);
    expect(after.changedAt, before.changedAt.subtract(const Duration(minutes: 5)));

    // Assert both halves, the way the tile-tap test does for a switch.
    final relayed = bridge.sent.whereType<RetimeRequest>().single;
    expect(relayed.changeSyncId, after.syncId);
    expect(relayed.at, after.changedAt);

    await disposeApp(tester);
  });

  testWidgets('the clock follows the nudge, which is what makes no local preview state safe', (
    tester,
  ) async {
    final bridge = FakeWearBridge();
    addTearDown(bridge.dispose);
    await pumpWatch(tester, bridge, seed: seedBookmarks);
    await tapTile(tester, tile(deepWorkId));

    await openStartTime(tester);
    final before = (tester.widget<Text>(find.textContaining(':').first)).data;

    await tester.tap(find.byKey(const ValueKey('nudge--5')));
    await settle(tester);
    final after = (tester.widget<Text>(find.textContaining(':').first)).data;

    // If the clock were reading a locally-held preview instead of the database,
    // a tap that only writes and relays would leave it alone. It is also why
    // this screen needs no save control.
    expect(after, isNot(before));

    await disposeApp(tester);
  });

  testWidgets('nudges accumulate when tapped faster than the write lands', (tester) async {
    // The case a wrist actually produces: -1 tapped several times in a couple of
    // seconds, because that is what a nudge is for. Each tap reads the running
    // block from the frame it was built in, so unless the intent is carried
    // forward, taps two onward all add their minute to the same stale start,
    // compute the same instant, and five taps land as one.
    //
    // Tapped with no settle between them, which is the deterministic form of
    // what a fast thumb does to a write that has not committed yet. On a device
    // there are frames in between, but nothing guarantees the write, the drift
    // stream and the provider rebuild have all been round-tripped by the next
    // tap — so the timing decides the arithmetic, which is the bug.
    final bridge = FakeWearBridge();
    addTearDown(bridge.dispose);
    final db = await pumpWatch(tester, bridge, seed: seedBookmarks);
    await tapTile(tester, tile(deepWorkId));
    final changes = DriftChangeRepository(db);
    final before = (await changes.loadChanges()).single;

    await openStartTime(tester);

    final nudge = find.byKey(const ValueKey('nudge--1'));
    for (var i = 0; i < 5; i++) {
      await tester.tap(nudge);
    }
    await settle(tester);

    final after = (await changes.loadChanges()).single;
    expect(
      after.changedAt,
      before.changedAt.subtract(const Duration(minutes: 5)),
      reason: 'five taps of -1 must move the start five minutes, not one',
    );

    await disposeApp(tester);
  });

  testWidgets('a re-point needs the confirm gesture', (tester) async {
    // Same arm-then-tap-again gesture as the switch list, and for the same
    // reason: a watch is operated by feel, and a misfire re-pointing a block
    // is neither visible nor easy to undo.
    final bridge = FakeWearBridge();
    addTearDown(bridge.dispose);
    final db = await pumpWatch(tester, bridge, seed: seedBookmarks);
    await tapTile(tester, tile(deepWorkId));
    final changes = DriftChangeRepository(db);
    final changeId = (await changes.loadChanges()).single.syncId;

    await openSwap(tester);
    final repoint = find.byKey(ValueKey('repoint-$emailId'));

    await tester.tap(repoint);
    await settle(tester);

    expect(await changes.activityIdsForChange(changeId), [deepWorkId]);
    expect(bridge.sent.whereType<AssignRequest>(), isEmpty);

    await tester.tap(repoint);
    await settle(tester);

    expect(await changes.activityIdsForChange(changeId), [emailId]);
    final relayed = bridge.sent.whereType<AssignRequest>().single;
    expect(relayed.changeSyncId, changeId);
    expect(relayed.activityId, emailId);

    await disposeApp(tester);
  });

  testWidgets('every screen reaches its own controls without scrolling', (tester) async {
    // What splitting the panel bought. The old single panel put the re-point
    // tiles and the done control so far below the fold that two tests had to
    // drag 400px to reach them — this is the assertion that would have caught
    // it, applied to each screen the split produced.
    final bridge = FakeWearBridge();
    addTearDown(bridge.dispose);
    await pumpWatch(tester, bridge, seed: seedBookmarks);
    await tapTile(tester, tile(deepWorkId));

    const margin = 227 * 0.07;
    void expectInside(Finder finder, String what) {
      final rect = tester.getRect(finder);
      expect(rect.top, greaterThan(margin), reason: '$what clipped by the top curve');
      expect(rect.left, greaterThan(0), reason: '$what clipped by the left curve');
      expect(rect.right, lessThan(227), reason: '$what clipped by the right curve');
      expect(rect.bottom, lessThan(227 - margin), reason: '$what clipped by the bottom curve');
    }

    await openMenu(tester);
    expect(tester.takeException(), isNull);
    expectInside(find.byKey(const ValueKey('menu-edit-start')), 'edit start time');
    expectInside(find.byKey(const ValueKey('menu-swap')), 'swap current action');

    await tester.tap(find.byKey(const ValueKey('menu-edit-start')));
    await settle(tester);
    expect(tester.takeException(), isNull);
    // Six nudge buttons in two rows is the tightest thing this screen has had
    // to fit — the same curve that clipped the clock is where this fails too.
    for (final m in [-15, -5, -1, 1, 5, 15]) {
      expectInside(find.byKey(ValueKey('nudge-$m')), 'nudge $m');
    }

    await swipe(tester, 80);
    await tester.tap(find.byKey(const ValueKey('menu-swap')));
    await settle(tester);
    expect(tester.takeException(), isNull);
    expectInside(find.byKey(const ValueKey('swap-current')), 'the running activity');
    expectInside(find.byKey(ValueKey('repoint-$emailId')), 'the first swap candidate');

    await disposeApp(tester);
  });

  testWidgets('the clock is never inside something that scrolls', (tester) async {
    // It is the reason to glance at a watch. The home screen already guards
    // this; the start-time screen shows the same clock and must too.
    final bridge = FakeWearBridge();
    addTearDown(bridge.dispose);
    await pumpWatch(tester, bridge, seed: seedBookmarks);
    await tapTile(tester, tile(deepWorkId));

    await openStartTime(tester);

    final clock = find.textContaining(':').first;
    for (final scrollable in [find.byType(ListView), find.byType(SingleChildScrollView)]) {
      expect(find.descendant(of: scrollable, matching: clock), findsNothing);
    }

    await disposeApp(tester);
  });
}
