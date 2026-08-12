// Keyboard shortcuts for the desktop PWA.
//
// The binding worth testing hardest is not any single action but the *matching*:
// these are bound to key positions rather than to the characters a layout
// produces, and nothing about that shows up by pressing keys on a US layout.
// "a Slovak layout hits the same keys" is the test that pins that design; it was
// checked against a logical binding, which it fails.

import 'package:flutter/foundation.dart' show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/data/drift_repositories.dart';
import 'package:time_tracker/phone/screens/activities_screen.dart';
import 'package:time_tracker/phone/screens/now_screen.dart';
import 'package:time_tracker/phone/screens/reports_screen.dart';
import 'package:time_tracker/phone/screens/timeline_screen.dart';

import 'support/flow_harness.dart';

/// Wide enough for the report's week selector to lay out unclipped.
const _desktop = Size(900, 800);

/// Press a key by *position*, spelling out what the layout would produce.
///
/// [logical] defaults to the US legend. Passing something else is how a
/// non-US layout is simulated: the same physical key, a different character.
Future<void> _press(
  WidgetTester tester,
  PhysicalKeyboardKey physical,
  LogicalKeyboardKey usLegend, {
  LogicalKeyboardKey? logical,
  LogicalKeyboardKey modifier = LogicalKeyboardKey.controlLeft,
}) async {
  final key = logical ?? usLegend;
  // Simulated as web events, which is where these bindings are for. It also
  // sidesteps the raw-keycode tables the desktop simulators need: those map a
  // *logical* key to a platform keycode, so a character no US keyboard produces
  // has no entry and cannot be simulated at all.
  const web = 'web';
  await tester.sendKeyDownEvent(modifier, platform: web);
  await tester.sendKeyDownEvent(key, physicalKey: physical, platform: web);
  await tester.sendKeyUpEvent(key, physicalKey: physical, platform: web);
  await tester.sendKeyUpEvent(modifier, platform: web);
  await settle(tester);
}

/// The Now search field, wherever it currently sits.
///
/// `skipOffstage: false` is required: the tabs are an IndexedStack, so the Now
/// screen stays built but off-stage while another tab is showing, and the
/// default finder would not see it.
Finder _searchField() => find.descendant(
  of: find.byType(DottedField, skipOffstage: false),
  matching: find.byType(TextField, skipOffstage: false),
);

Future<void> _seed(AppDatabase db) async {
  final activities = DriftActivityRepository(db);
  final changes = DriftChangeRepository(db);
  final a = await activities.createActivity(name: 'Deep work', color: '#4F8FEE');
  await changes.switchTo(a.syncId);
}

void main() {
  testWidgets('the digits move between tabs', (tester) async {
    await bootApp(tester, viewport: _desktop, seed: _seed);

    // Now is where the app starts, so a move that lands anywhere else proves it.
    expect(inScreen(TimelineScreen, find.byType(ListView)), findsNothing);

    await _press(tester, PhysicalKeyboardKey.digit2, LogicalKeyboardKey.digit2);
    expect(find.byType(TimelineScreen), findsOneWidget);
    expect(inScreen(TimelineScreen, find.text('Deep work')), findsWidgets);

    await _press(tester, PhysicalKeyboardKey.digit4, LogicalKeyboardKey.digit4);
    expect(inScreen(ActivitiesScreen, find.text('Deep work')), findsWidgets);

    await disposeApp(tester);
  });

  // The reason the whole thing is keyed on PhysicalKeyboardKey. On a Slovak
  // layout the key left of "2" produces "+", so a binding written against
  // LogicalKeyboardKey.digit1 is not merely mislabelled there — it can never
  // fire, and no amount of pressing "1" on a US keyboard reveals it.
  testWidgets('a Slovak layout hits the same keys', (tester) async {
    await bootApp(tester, viewport: _desktop, seed: _seed);

    await _press(
      tester,
      PhysicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit3,
      logical: LogicalKeyboardKey.quoteSingle, // what that key types on sk-QWERTZ
    );
    expect(find.byType(ReportsScreen), findsOneWidget);
    expect(inScreen(ReportsScreen, find.text('PER CATEGORY')), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('the brackets step the report week, and only on Reports', (tester) async {
    await bootApp(tester, viewport: _desktop, seed: _seed);

    // On Now the binding is inert — the week must not move behind another screen.
    await _press(tester, PhysicalKeyboardKey.bracketLeft, LogicalKeyboardKey.bracketLeft);
    await _press(tester, PhysicalKeyboardKey.digit3, LogicalKeyboardKey.digit3);
    expect(inScreen(ReportsScreen, find.text('This week')), findsOneWidget);

    await _press(tester, PhysicalKeyboardKey.bracketLeft, LogicalKeyboardKey.bracketLeft);
    expect(inScreen(ReportsScreen, find.text('This week')), findsNothing);

    // Forward again, and then refusing to walk into the future: a second
    // press must leave the report on this week rather than one week ahead.
    await _press(tester, PhysicalKeyboardKey.bracketRight, LogicalKeyboardKey.bracketRight);
    expect(inScreen(ReportsScreen, find.text('This week')), findsOneWidget);
    await _press(tester, PhysicalKeyboardKey.bracketRight, LogicalKeyboardKey.bracketRight);
    expect(inScreen(ReportsScreen, find.text('This week')), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('L jumps to Now and puts the caret in the search field', (tester) async {
    await bootApp(tester, viewport: _desktop, seed: _seed);

    await _press(tester, PhysicalKeyboardKey.digit4, LogicalKeyboardKey.digit4);
    await _press(tester, PhysicalKeyboardKey.keyL, LogicalKeyboardKey.keyL);

    expect(find.byType(NowScreen), findsOneWidget);
    // Focused, not merely visible — the point of the shortcut is being able to
    // type immediately.
    final field = tester.widget<TextField>(_searchField());
    expect(field.focusNode?.hasFocus, isTrue);

    // And the field really takes the text, rather than the shell swallowing it.
    await tester.enterText(find.byType(TextField).last, 'deep');
    await settle(tester);
    expect(find.text('deep'), findsWidgets);

    await disposeApp(tester);
  });

  testWidgets('moving tabs takes focus back off the search field', (tester) async {
    await bootApp(tester, viewport: _desktop, seed: _seed);

    await _press(tester, PhysicalKeyboardKey.keyL, LogicalKeyboardKey.keyL);
    // The field lives in an IndexedStack and stays alive across tab changes, so
    // left focused it would keep eating keystrokes aimed at the screen on top —
    // and the next shortcut would land in a text field instead of the shell.
    await _press(tester, PhysicalKeyboardKey.digit3, LogicalKeyboardKey.digit3);

    final field = tester.widget<TextField>(_searchField());
    expect(field.focusNode?.hasFocus, isFalse);

    // Still listening: a further binding has to work after the handover.
    await _press(tester, PhysicalKeyboardKey.digit2, LogicalKeyboardKey.digit2);
    expect(inScreen(TimelineScreen, find.text('Deep work')), findsWidgets);

    await disposeApp(tester);
  });

  testWidgets('Enter opens a block to be named later', (tester) async {
    final db = await bootApp(tester, viewport: _desktop, seed: _seed);

    await _press(tester, PhysicalKeyboardKey.enter, LogicalKeyboardKey.enter);

    final changes = await db.select(db.activityChanges).get();
    expect(changes, hasLength(2), reason: 'a boundary was opened');
    expect(find.text('unnamed'), findsWidgets);

    await disposeApp(tester);
  });

  testWidgets('slash lists the bindings', (tester) async {
    await bootApp(tester, viewport: _desktop, seed: _seed);

    await _press(tester, PhysicalKeyboardKey.slash, LogicalKeyboardKey.slash);

    expect(find.text('Keyboard'), findsOneWidget);
    expect(find.textContaining('Previous week'), findsOneWidget);
    // The modifier is spelled for the platform running it, not hard-coded.
    expect(find.textContaining('Ctrl + ['), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('on macOS the modifier is Cmd, and Ctrl no longer fires', (tester) async {
    // Reset before the body ends, not in a tearDown: the framework asserts every
    // foundation debug variable is unset while the test is still running, and
    // tearDowns fire after that check.
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    await bootApp(tester, viewport: _desktop, seed: _seed);

    // Ctrl is the wrong modifier here: on macOS it is text-editing's own
    // (Ctrl+A/E/F/B/N/P move the caret), so claiming it would fight the field.
    await _press(tester, PhysicalKeyboardKey.digit2, LogicalKeyboardKey.digit2);
    expect(inScreen(TimelineScreen, find.text('Deep work')), findsNothing);

    await _press(
      tester,
      PhysicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit2,
      modifier: LogicalKeyboardKey.metaLeft,
    );
    expect(inScreen(TimelineScreen, find.text('Deep work')), findsWidgets);

    debugDefaultTargetPlatformOverride = null;
    await disposeApp(tester);
  });
}
