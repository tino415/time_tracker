// The shell has two shapes, and which one you get is a question about the
// window rather than about the platform.
//
// Asserted positionally — where the navigation sits relative to the content —
// rather than by widget type. The shapes are private widgets, and "the tabs are
// under your thumb" or "beside the content" is the actual claim either way.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/data/drift_repositories.dart';
import 'package:time_tracker/data/providers.dart';
import 'package:time_tracker/data/sync_service.dart';
import 'package:time_tracker/phone/breakpoints.dart';
import 'package:time_tracker/phone/phone_app.dart';
import 'package:time_tracker/phone/screens/now_screen.dart';
import 'package:time_tracker/phone/screens/reports_screen.dart';
import 'package:time_tracker/phone/screens/timeline_screen.dart';
import 'package:time_tracker/phone/widgets/neo.dart';

import 'support/flow_harness.dart';

const _phone = Size(400, 880);

/// A sidebar, but not room for two panes.
const _desktop = Size(900, 900);

/// A sidebar with plenty of room to spare beyond [_desktop].
const _wide = Size(1280, 900);

/// On the Now screen and always present once anything is tracked — a fixed point
/// to measure the navigation against.
const _startNow = '▶ START NOW · NAME IT LATER';

Future<void> _seed(AppDatabase db) async {
  final activities = DriftActivityRepository(db);
  final a = await activities.createActivity(name: 'Deep work', color: '#4F8FEE');
  await DriftChangeRepository(db).switchTo(a.syncId);
}

/// Four bookmarks, so how many fit on a row is visible in where the third one
/// lands.
Future<void> _seedBookmarks(AppDatabase db) async {
  final activities = DriftActivityRepository(db);
  for (final name in ['One', 'Two', 'Three', 'Four']) {
    final a = await activities.createActivity(name: name, color: '#4F8FEE');
    await activities.setBookmarked(a.syncId, true);
  }
}

Offset _at(WidgetTester tester, Finder finder) => tester.getCenter(finder);

/// Boots with a sync server configured but no account yet — enough to prove
/// the control is reachable and opens the setup sheet, without a real backend.
Future<void> _bootWithSync(WidgetTester tester, {required Size viewport}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        syncConfigProvider.overrideWithValue(const SyncConfig(baseUrl: 'https://sync.example')),
      ],
      child: const PhoneApp(),
    ),
  );
  await settle(tester);
}

/// Where the focused control sits, horizontally. Traversal order is a claim
/// about the layout, so it is asked of the layout.
double? _focusedX() {
  final box = FocusManager.instance.primaryFocus?.context?.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  return box.localToGlobal(box.size.center(Offset.zero)).dx;
}

/// One lap of the traversal ring, as the x of each stop. Ends when a node comes
/// round again, so the ring is walked exactly once.
Future<List<double>> _ring(WidgetTester tester) async {
  final seen = <FocusNode>{};
  final xs = <double>[];
  for (var i = 0; i < 60; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab, platform: 'web');
    await tester.pump();
    final node = FocusManager.instance.primaryFocus;
    if (node == null || !seen.add(node)) break;
    final x = _focusedX();
    if (x != null) xs.add(x);
  }
  return xs;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadMonoFont();
  });

  testWidgets('a phone-width window keeps the tabs under the thumb', (tester) async {
    await bootApp(tester, viewport: _phone, seed: _seed);

    final body = _at(tester, inScreen(NowScreen, find.text(_startNow)));
    expect(_at(tester, find.text('REPORTS')).dy, greaterThan(body.dy));
    // The wordmark is a strip across the top, so it sits above everything.
    expect(_at(tester, find.text('[track]')).dy, lessThan(body.dy));

    await disposeApp(tester);
  });

  testWidgets('a wide window moves the navigation beside the content', (tester) async {
    await bootApp(tester, viewport: _desktop, seed: _seed);

    final body = _at(tester, inScreen(NowScreen, find.text(_startNow)));
    expect(_at(tester, find.text('REPORTS')).dx, lessThan(body.dx));
    // The header folds into the sidebar rather than keeping its own strip, so
    // the wordmark moves left of the content instead of above it.
    expect(_at(tester, find.text('[track]')).dx, lessThan(body.dx));
    expect(_at(tester, find.text('◑ THEME')).dx, lessThan(body.dx));

    await disposeApp(tester);
  });

  testWidgets('Tab exhausts the sidebar before entering the content', (tester) async {
    // Reading order sorts by rectangle, and a full-height sidebar shares its
    // vertical bands with the first rows of the content — so without help, Tab
    // can zig-zag between the navigation and the screen.
    await bootApp(tester, viewport: _desktop, seed: _seed);

    final xs = await _ring(tester);
    final lastInSidebar = xs.lastIndexWhere((x) => x < sidebarWidth);
    final firstInContent = xs.indexWhere((x) => x >= sidebarWidth);

    expect(lastInSidebar, isNonNegative, reason: 'no sidebar stop at all');
    expect(firstInContent, isNonNegative, reason: 'focus never reached the content');
    expect(firstInContent, greaterThan(lastInSidebar));

    await disposeApp(tester);
  });

  testWidgets('the sidebar switches screens', (tester) async {
    await bootApp(tester, viewport: _desktop, seed: _seed);

    await tester.tap(find.text('ACTIVITIES'));
    await settle(tester);

    expect(find.text('+ NEW ACTIVITY'), findsOneWidget);
    expect(inScreen(NowScreen, find.text(_startNow)), findsNothing);

    await disposeApp(tester);
  });

  testWidgets('at the widest viewport, selecting Timeline shows Timeline and not Now', (
    tester,
  ) async {
    await bootApp(tester, viewport: _wide, seed: _seed);

    expect(inScreen(NowScreen, find.text(_startNow)), findsOneWidget);
    expect(inScreen(TimelineScreen, find.text('≣ LIST')), findsNothing);

    await tester.tap(find.text('TIMELINE'));
    await settle(tester);

    expect(inScreen(TimelineScreen, find.text('≣ LIST')), findsOneWidget);
    expect(inScreen(NowScreen, find.text(_startNow)), findsNothing);

    await disposeApp(tester);
  });

  testWidgets('sync is reachable from the chrome on a tab that is not Reports', (tester) async {
    // Default tab is Now — the app-shell chrome is the point: reachable
    // regardless of which screen is showing, not scoped to one of them.
    await _bootWithSync(tester, viewport: _desktop);

    expect(inScreen(ReportsScreen, find.text('↧ EXPORT CSV · ALL HISTORY')), findsNothing);
    expect(find.text('SET UP SYNC'), findsNothing);

    await tester.tap(find.text('⟳ SYNC'));
    await settle(tester);

    expect(find.text('SET UP SYNC'), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('the phone header keeps sync on the wordmark row', (tester) async {
    // The controls live in a Wrap, so a header with one item too many for the
    // width does not overflow and does not throw — it quietly takes a second
    // row, on the screen with the least height to spare. Nothing else would
    // catch that, so it is asserted as geometry.
    //
    // This is the un-authenticated shape: server configured, no account, so one
    // button. The fullest header — sync, its gear and a status string — needs a
    // live SyncService and is not covered here.
    await _bootWithSync(tester, viewport: _phone);

    final wordmark = tester.getCenter(find.text('[track]'));
    final sync = tester.getCenter(find.text('⟳ SYNC'));

    expect(
      sync.dy,
      moreOrLessEquals(wordmark.dy, epsilon: 4),
      reason: 'the chrome wrapped onto a second row',
    );

    await disposeApp(tester);
  });

  testWidgets('a single column stops widening long before the window does', (tester) async {
    await bootApp(tester, viewport: const Size(2560, 1200), seed: _seed);
    await tester.tap(find.text('REPORTS'));
    await settle(tester);

    final width = tester.getSize(find.byType(ReportsScreen)).width;
    expect(width, contentMaxWidth);
    // An absolute bound alone would still pass if the cap were raised to
    // something silly.
    expect(width, lessThan(2560 * 0.5));

    await disposeApp(tester);
  });

  testWidgets('a sheet stays a sheet on a wide window', (tester) async {
    // Not our doing — Material bounds a modal sheet and centres it, so nothing
    // here sets a width. This is the test that says so, and that would notice a
    // sheet given constraints of its own that undid it.
    await bootApp(tester, viewport: const Size(1600, 1000), seed: _seed);
    await tester.tap(inScreen(NowScreen, find.text('⋯ EDIT BLOCK')));
    await settle(tester);

    // The widest control the sheet contains: the `BottomSheet` widget itself
    // spans the window, and the bound is applied inside it.
    final widest = tester.getRect(
      find.descendant(of: find.byType(BottomSheet), matching: find.byType(NeoButton)).first,
    );
    expect(widest.width, lessThan(1600 * 0.5));
    expect(widest.center.dx, 800, reason: 'a sheet pinned to one edge reads wrong however narrow');

    await disposeApp(tester);
  });

  testWidgets('a phone keeps the bookmark grid two tiles wide', (tester) async {
    await bootApp(tester, viewport: _phone, seed: _seedBookmarks);

    expect(
      tester.getCenter(find.text('Three')).dy,
      greaterThan(tester.getCenter(find.text('One')).dy),
    );

    await disposeApp(tester);
  });

  testWidgets('a wide pane fits more bookmarks per row', (tester) async {
    // The tiles reflow rather than stretching: two very wide tiles say no more
    // than two narrow ones, and the fixed tile height stays fixed either way.
    await bootApp(tester, viewport: const Size(1600, 1000), seed: _seedBookmarks);

    expect(tester.getCenter(find.text('Three')).dy, tester.getCenter(find.text('One')).dy);

    await disposeApp(tester);
  });
}
