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

import 'support/flow_harness.dart';

const _phone = Size(400, 880);
const _desktop = Size(1200, 900);

/// On the Now screen and always present once anything is tracked — a fixed point
/// to measure the navigation against.
const _startNow = '▶ START NOW · NAME IT LATER';

Future<void> _seed(AppDatabase db) async {
  final activities = DriftActivityRepository(db);
  final a = await activities.createActivity(name: 'Deep work', color: '#4F8FEE');
  await DriftChangeRepository(db).switchTo(a.syncId);
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
}
