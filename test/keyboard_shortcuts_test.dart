// Keyboard shortcuts for the desktop PWA.
//
// Two things here are worth more than the individual bindings.
//
// The *matching* is positional, not logical: on a Slovak layout the key left of
// "2" types "+", so a binding written against a character is unreachable there,
// and no amount of pressing keys on a US keyboard reveals it.
//
// The *typing guard* is what makes bare keys possible at all. Modifiers were
// tried first and had to be abandoned — browsers reserve modifier combinations
// and almost no bare letters — which moved the whole risk onto "nothing fires
// while a field has focus". Get that wrong and "s" cannot be typed into a note.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/data/drift_repositories.dart';
import 'package:time_tracker/domain/unsorted.dart';
import 'package:time_tracker/phone/screens/activities_screen.dart';
import 'package:time_tracker/phone/screens/calendar_screen.dart';
import 'package:time_tracker/phone/screens/now_screen.dart';
import 'package:time_tracker/phone/screens/reports_screen.dart';
import 'package:time_tracker/phone/screens/timeline_screen.dart';
import 'package:time_tracker/phone/shortcuts.dart';

import 'support/flow_harness.dart';

/// Wide enough for the report's week selector to lay out unclipped.
const _desktop = Size(900, 800);

/// Press a key by *position*, spelling out what the layout would produce.
///
/// [logical] defaults to the US legend. Passing something else is how a non-US
/// layout is simulated: the same physical key, a different character.
Future<void> _press(
  WidgetTester tester,
  PhysicalKeyboardKey physical,
  LogicalKeyboardKey usLegend, {
  LogicalKeyboardKey? logical,
  bool shift = false,
}) async {
  final key = logical ?? usLegend;
  // Simulated as web events, which is where these bindings are for. It also
  // sidesteps the raw-keycode tables the desktop simulators need: those map a
  // *logical* key to a platform keycode, so a character no US keyboard produces
  // has no entry and cannot be simulated at all.
  const web = 'web';
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft, platform: web);
  await tester.sendKeyDownEvent(key, physicalKey: physical, platform: web);
  await tester.sendKeyUpEvent(key, physicalKey: physical, platform: web);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft, platform: web);
  await settle(tester);
}

/// `g` then a letter.
Future<void> _go(WidgetTester tester, PhysicalKeyboardKey physical, LogicalKeyboardKey legend) async {
  await _press(tester, PhysicalKeyboardKey.keyG, LogicalKeyboardKey.keyG);
  await _press(tester, physical, legend);
}

/// The Now search field, wherever it currently sits.
///
/// `skipOffstage: false` is required: the tabs are an IndexedStack, so the Now
/// screen stays built but off-stage while another tab is showing.
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
  testWidgets('g then a letter moves between tabs', (tester) async {
    await bootApp(tester, viewport: _desktop, seed: _seed);

    await _go(tester, PhysicalKeyboardKey.keyT, LogicalKeyboardKey.keyT);
    expect(inScreen(TimelineScreen, find.text('Deep work')), findsWidgets);

    await _go(tester, PhysicalKeyboardKey.keyA, LogicalKeyboardKey.keyA);
    expect(inScreen(ActivitiesScreen, find.text('Deep work')), findsWidgets);

    await _go(tester, PhysicalKeyboardKey.keyR, LogicalKeyboardKey.keyR);
    expect(inScreen(ReportsScreen, find.text('PER CATEGORY')), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('a bare letter does nothing without the prefix', (tester) async {
    // "t" alone must not move: the single-key space belongs to actions, and a
    // stray letter changing screens is exactly what the prefix prevents.
    await bootApp(tester, viewport: _desktop, seed: _seed);

    await _press(tester, PhysicalKeyboardKey.keyT, LogicalKeyboardKey.keyT);

    expect(inScreen(TimelineScreen, find.text('Deep work')), findsNothing);

    await disposeApp(tester);
  });

  testWidgets('the prefix lapses rather than staying armed', (tester) async {
    await bootApp(tester, viewport: _desktop, seed: _seed);

    await _press(tester, PhysicalKeyboardKey.keyG, LogicalKeyboardKey.keyG);
    // Shown while armed — a mode nobody can see is a trap.
    expect(find.text('g …'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    expect(find.text('g …'), findsNothing);

    // And the letter that follows is then just a letter.
    await _press(tester, PhysicalKeyboardKey.keyT, LogicalKeyboardKey.keyT);
    expect(inScreen(TimelineScreen, find.text('Deep work')), findsNothing);

    await disposeApp(tester);
  });

  testWidgets('Escape and Ctrl+G cancel a pending prefix', (tester) async {
    // Waiting out the timeout is not a way out — a prefix pressed by accident
    // would leave the next keystroke meaning something unasked for.
    await bootApp(tester, viewport: _desktop, seed: _seed);

    await _press(tester, PhysicalKeyboardKey.keyG, LogicalKeyboardKey.keyG);
    expect(find.text('g …'), findsOneWidget);
    await _press(tester, PhysicalKeyboardKey.escape, LogicalKeyboardKey.escape);
    expect(find.text('g …'), findsNothing);

    // The letter after a cancelled prefix is just a letter.
    await _press(tester, PhysicalKeyboardKey.keyT, LogicalKeyboardKey.keyT);
    expect(inScreen(TimelineScreen, find.text('Deep work')), findsNothing);

    // Ctrl+G too — emacs's cancel, and the one a g-prefix user already knows.
    // It has to be caught ahead of the held-modifier check, which would
    // otherwise dismiss it as somebody else's shortcut.
    await _press(tester, PhysicalKeyboardKey.keyG, LogicalKeyboardKey.keyG);
    expect(find.text('g …'), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft, platform: 'web');
    await _press(tester, PhysicalKeyboardKey.keyG, LogicalKeyboardKey.keyG);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft, platform: 'web');
    await settle(tester);
    expect(find.text('g …'), findsNothing);

    await disposeApp(tester);
  });

  // The reason the whole thing is keyed on PhysicalKeyboardKey. On a Slovak
  // layout the key printed "t" is still physically KeyT, but a binding written
  // against a *character* would need a table per layout.
  testWidgets('a non-US layout hits the same keys', (tester) async {
    await bootApp(tester, viewport: _desktop, seed: _seed);

    await _press(tester, PhysicalKeyboardKey.keyG, LogicalKeyboardKey.keyG);
    await _press(
      tester,
      PhysicalKeyboardKey.keyR,
      LogicalKeyboardKey.keyR,
      logical: LogicalKeyboardKey.quoteSingle, // some other layout's legend
    );

    expect(inScreen(ReportsScreen, find.text('PER CATEGORY')), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('nothing fires while a field has focus', (tester) async {
    // The load-bearing guard. Bare keys are only possible because of it: every
    // binding is a character someone might legitimately be typing.
    final db = await bootApp(tester, viewport: _desktop, seed: _seed);

    await tester.tap(_searchField());
    await settle(tester);
    await tester.enterText(_searchField(), 'st');
    await settle(tester);

    // "s" would start a block, "g" would arm the prefix.
    await _press(tester, PhysicalKeyboardKey.keyS, LogicalKeyboardKey.keyS);
    await _press(tester, PhysicalKeyboardKey.keyG, LogicalKeyboardKey.keyG);

    expect(await db.select(db.activityChanges).get(), hasLength(1),
        reason: 's must not start a block while typing');
    expect(find.text('g …'), findsNothing, reason: 'g must not arm while typing');

    await disposeApp(tester);
  });

  testWidgets('s starts a block and S goes to the field', (tester) async {
    final db = await bootApp(tester, viewport: _desktop, seed: _seed);

    await _press(tester, PhysicalKeyboardKey.keyS, LogicalKeyboardKey.keyS);
    expect(await db.select(db.activityChanges).get(), hasLength(2));
    expect(find.text(kUnsortedName), findsWidgets);

    // Shift makes it a different binding — the one case where case matters.
    await _go(tester, PhysicalKeyboardKey.keyA, LogicalKeyboardKey.keyA);
    await _press(tester, PhysicalKeyboardKey.keyS, LogicalKeyboardKey.keyS, shift: true);

    expect(find.byType(NowScreen), findsOneWidget);
    final field = tester.widget<TextField>(_searchField());
    expect(field.focusNode?.hasFocus, isTrue);

    await disposeApp(tester);
  });

  testWidgets('Escape is the way out of the field', (tester) async {
    // Found by this test failing: with the guard in place and no exit, focusing
    // the search field switched off every binding *including* the ones that
    // would leave it, so the only way out was the mouse.
    await bootApp(tester, viewport: _desktop, seed: _seed);

    await _press(tester, PhysicalKeyboardKey.keyS, LogicalKeyboardKey.keyS, shift: true);
    expect(tester.widget<TextField>(_searchField()).focusNode?.hasFocus, isTrue);

    // Still trapped while focused — that half is the guard working.
    await _go(tester, PhysicalKeyboardKey.keyR, LogicalKeyboardKey.keyR);
    expect(inScreen(ReportsScreen, find.text('PER CATEGORY')), findsNothing);

    await _press(tester, PhysicalKeyboardKey.escape, LogicalKeyboardKey.escape);
    expect(tester.widget<TextField>(_searchField()).focusNode?.hasFocus, isFalse);

    // And the keyboard is ours again.
    await _go(tester, PhysicalKeyboardKey.keyR, LogicalKeyboardKey.keyR);
    expect(inScreen(ReportsScreen, find.text('PER CATEGORY')), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('h and l step the week on Reports and the day on the calendar',
      (tester) async {
    await bootApp(tester, viewport: _desktop, seed: _seed);

    // Inert on Now: a scoped binding must not act on a screen you cannot see.
    await _press(tester, PhysicalKeyboardKey.keyH, LogicalKeyboardKey.keyH);

    await _go(tester, PhysicalKeyboardKey.keyR, LogicalKeyboardKey.keyR);
    expect(inScreen(ReportsScreen, find.text('This week')), findsOneWidget);
    await _press(tester, PhysicalKeyboardKey.keyH, LogicalKeyboardKey.keyH);
    expect(inScreen(ReportsScreen, find.text('This week')), findsNothing);
    await _press(tester, PhysicalKeyboardKey.keyL, LogicalKeyboardKey.keyL);
    expect(inScreen(ReportsScreen, find.text('This week')), findsOneWidget);

    // The same keys, a different unit, decided by which screen is showing.
    await _go(tester, PhysicalKeyboardKey.keyT, LogicalKeyboardKey.keyT);
    await tester.tap(find.text('▦ CALENDAR'));
    await settle(tester);
    expect(inScreen(CalendarScreen, find.text('Today')), findsOneWidget);
    await _press(tester, PhysicalKeyboardKey.keyH, LogicalKeyboardKey.keyH);
    expect(inScreen(CalendarScreen, find.text('Yesterday')), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('h does nothing on the timeline list', (tester) async {
    // The timeline tab is two views behind a toggle, and only the calendar has
    // days to step — so the scope is the view, not the tab.
    await bootApp(tester, viewport: _desktop, seed: _seed);
    await _go(tester, PhysicalKeyboardKey.keyT, LogicalKeyboardKey.keyT);

    await _press(tester, PhysicalKeyboardKey.keyH, LogicalKeyboardKey.keyH);
    await tester.tap(find.text('▦ CALENDAR'));
    await settle(tester);

    // Still today: the press before the toggle must not have moved the day.
    expect(inScreen(CalendarScreen, find.text('Today')), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('a modifier held means the shortcut is not ours', (tester) async {
    // Bare keys only. Cmd+S is Save somewhere; swallowing it would be worse
    // than ignoring it.
    final db = await bootApp(tester, viewport: _desktop, seed: _seed);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft, platform: 'web');
    await _press(tester, PhysicalKeyboardKey.keyS, LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft, platform: 'web');

    expect(await db.select(db.activityChanges).get(), hasLength(1));

    await disposeApp(tester);
  });

  testWidgets('? lists the bindings, and the list is the table', (tester) async {
    await bootApp(tester, viewport: _desktop, seed: _seed);

    await _press(tester, PhysicalKeyboardKey.slash, LogicalKeyboardKey.slash, shift: true);

    expect(find.text('Keyboard'), findsOneWidget);
    // Generated from the same table that installs them, so the two cannot drift.
    for (final binding in shortcutBindings) {
      expect(find.textContaining(binding.what), findsWidgets,
          reason: '${binding.label} is listed');
    }

    await disposeApp(tester);
  });

  testWidgets('the header button opens the same list', (tester) async {
    // The button is web-only and kIsWeb is false here, so what this checks is
    // the dialog it opens. Its presence is the browser suite's job.
    await bootApp(tester, viewport: _desktop, seed: _seed);

    // Not awaited: the future completes when the dialog is *dismissed*, so
    // awaiting it waits forever for a tap this test has not made yet.
    unawaited(showShortcutsHelp(tester.element(find.byType(NowScreen))));
    await settle(tester);

    expect(find.text('Keyboard'), findsOneWidget);
    expect(find.textContaining('Previous week'), findsWidgets);

    await disposeApp(tester);
  });
}
