// The shell has two shapes, and which one you get is a question about the
// window rather than about the platform.
//
// Asserted positionally — where the navigation sits relative to the content —
// rather than by widget type. The shapes are private widgets, and "the tabs are
// under your thumb" or "beside the content" is the actual claim either way.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/data/drift_repositories.dart';
import 'package:time_tracker/phone/breakpoints.dart';
import 'package:time_tracker/phone/screens/now_screen.dart';
import 'package:time_tracker/phone/screens/reports_screen.dart';
import 'package:time_tracker/phone/screens/timeline_screen.dart';
import 'package:time_tracker/phone/widgets/neo.dart';

import 'support/flow_harness.dart';

const _phone = Size(400, 880);

/// A sidebar, but not room for two panes.
const _desktop = Size(900, 900);

/// Wide enough to pair Now with the timeline.
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

NeoChip _chip(String label) => find
    .byWidgetPredicate((w) => w is NeoChip && w.text == label)
    .evaluate()
    .single
    .widget as NeoChip;

/// Tap a navigation destination by name.
///
/// Scoped by position rather than by text: once the panes are labelled, the
/// sidebar's "TIMELINE" and the pane's chip read the same, and only one of them
/// is a control.
Future<void> _tapDestination(WidgetTester tester, String label) async {
  final target = find.text(label).evaluate().firstWhere((e) {
    final box = e.renderObject! as RenderBox;
    return box.localToGlobal(Offset.zero).dx < sidebarWidth;
  });
  await tester.tap(find.byElementPredicate((e) => identical(e, target)));
  await settle(tester);
}

Offset _at(WidgetTester tester, Finder finder) => tester.getCenter(finder);

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

  testWidgets('a window with room for two shows Now beside the timeline', (tester) async {
    await bootApp(tester, viewport: _wide, seed: _seed);

    final now = tester.getTopLeft(find.byType(NowScreen));
    final timeline = tester.getTopLeft(find.byType(TimelineScreen));
    expect(timeline.dx, greaterThan(now.dx), reason: 'the timeline is not beside Now');
    expect(timeline.dy, now.dy, reason: 'the panes do not start at the same height');

    await disposeApp(tester);
  });

  testWidgets('a window without the room does not pair them', (tester) async {
    // 900 has the sidebar but not two panes: the panes would each be narrower
    // than the phone these screens were laid out for.
    await bootApp(tester, viewport: const Size(900, 900), seed: _seed);

    expect(inScreen(NowScreen, find.text(_startNow)), findsOneWidget);
    expect(find.text('≣ LIST'), findsNothing);

    await disposeApp(tester);
  });

  testWidgets('choosing between the paired screens marks one of them', (tester) async {
    // Both are on show, so a destination click changes nothing in the body. The
    // chip is what answers it — and what says which screen a scoped key means.
    await bootApp(tester, viewport: _wide, seed: _seed);

    expect(_chip('Now').brand, isTrue);
    expect(_chip('Timeline').brand, isFalse);

    await _tapDestination(tester, 'TIMELINE');

    expect(_chip('Now').brand, isFalse);
    expect(_chip('Timeline').brand, isTrue);

    await disposeApp(tester);
  });

  testWidgets('a single column stops widening long before the window does',
      (tester) async {
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

    expect(tester.getCenter(find.text('Three')).dy,
        greaterThan(tester.getCenter(find.text('One')).dy));

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
