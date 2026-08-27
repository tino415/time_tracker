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
import 'package:time_tracker/phone/breakpoints.dart';
import 'package:time_tracker/phone/shortcuts.dart';
import 'package:time_tracker/phone/widgets/neo.dart';

import 'support/flow_harness.dart';

/// Wide enough for the report's week selector to lay out unclipped — and, past
/// [sidebarBreakpoint], the shape these bindings are named for: the shell here is
/// the desktop one, navigation down the side.
const _desktop = Size(900, 800);

/// A control that is always on the Now screen and does something checkable —
/// the target the focus tests tab towards. `NeoButton` uppercases its label.
const _startNow = '▶ START NOW · NAME IT LATER';

/// The activity seeded beside "Deep work", for the cases that need something to
/// change *to*. Not bookmarked, so it stays off the Now screen until a sheet
/// offers it.
const _other = 'Reading';

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
Future<void> _go(
  WidgetTester tester,
  PhysicalKeyboardKey physical,
  LogicalKeyboardKey legend,
) async {
  await _press(tester, PhysicalKeyboardKey.keyG, LogicalKeyboardKey.keyG);
  await _press(tester, physical, legend);
}

/// `e` then a letter.
Future<void> _edit(
  WidgetTester tester,
  PhysicalKeyboardKey physical,
  LogicalKeyboardKey legend,
) async {
  await _press(tester, PhysicalKeyboardKey.keyE, LogicalKeyboardKey.keyE);
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

Future<void> _tab(WidgetTester tester, {bool shift = false}) async {
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft, platform: 'web');
  await tester.sendKeyEvent(LogicalKeyboardKey.tab, platform: 'web');
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft, platform: 'web');
  await tester.pump();
}

/// Whether the control that currently holds focus is the one reading [label].
///
/// The focused node must sit *inside* that control. Asking the other way round —
/// does the focused element contain the label — answers true for any ancestor,
/// and [AppShortcuts] is an ancestor of the entire app.
bool _focusedReads(String label) {
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused == null) return false;
  return find
      .descendant(
        of: find.ancestor(of: find.text(label), matching: find.byType(NeoPressable)),
        matching: find.byElementPredicate((e) => identical(e, focused)),
      )
      .evaluate()
      .isNotEmpty;
}

/// Tab until [label] holds focus. Bounded, so a tree with no stop on it fails
/// the test rather than hanging it.
Future<bool> _tabTo(WidgetTester tester, String label) async {
  for (var i = 0; i < 40; i++) {
    await _tab(tester);
    if (_focusedReads(label)) return true;
  }
  return false;
}

/// Which screen the focused control belongs to, or null for the shell's own
/// chrome. The tabs are an [IndexedStack], so the screens you are not looking at
/// are still built — and a Tab stop on one of those is worse than no stop.
Type? _focusedScreen() {
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused == null) return null;
  const screens = {NowScreen, TimelineScreen, ReportsScreen, ActivitiesScreen};
  Type? found;
  focused.visitAncestorElements((e) {
    if (!screens.contains(e.widget.runtimeType)) return true;
    found = e.widget.runtimeType;
    return false;
  });
  return found;
}

Future<void> _seed(AppDatabase db) async {
  final activities = DriftActivityRepository(db);
  final changes = DriftChangeRepository(db);
  final a = await activities.createActivity(name: 'Deep work', color: '#4F8FEE');
  await changes.switchTo(a.syncId);
}

/// [_seed] plus a second activity to change to.
///
/// A separate function rather than another row in [_seed]: several tests below
/// assert on finders that a second name in the catalogue would make ambiguous,
/// and only the `e a` case needs an alternative to pick.
Future<void> _seedPair(AppDatabase db) async {
  await _seed(db);
  await DriftActivityRepository(db).createActivity(name: _other, color: '#E4572E');
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

  testWidgets('e a re-points the running block, opening no boundary', (tester) async {
    // The row count is the whole distinction. Re-pointing and switching leave
    // the hero reading exactly the same thing, and only the boundary tells them
    // apart: a correction says the last hour was mislabelled, a switch says the
    // last hour was right and something new starts now.
    final db = await bootApp(tester, viewport: _desktop, seed: _seedPair);
    final before = await db.select(db.activityChanges).get();

    await _edit(tester, PhysicalKeyboardKey.keyA, LogicalKeyboardKey.keyA);
    // "What was this?" is the unnamed block's question; this one has an answer
    // already and is being corrected.
    expect(find.text('CHANGE TO'), findsOneWidget);

    // The sheet is the last thing pushed; the other tabs keep their own rows
    // built but off-stage.
    await tester.tap(find.text(_other).last);
    await settle(tester);

    expect(inScreen(NowScreen, find.text(_other)), findsWidgets);
    expect(
      await db.select(db.activityChanges).get(),
      hasLength(before.length),
      reason: 'a correction must not write a boundary',
    );

    await disposeApp(tester);
  });

  testWidgets('e n writes the note on the running block', (tester) async {
    // The note is the thing you reach for without looking away from what you
    // are doing, and every other way to it starts by finding the hero.
    await bootApp(tester, viewport: _desktop, seed: _seed);

    await _edit(tester, PhysicalKeyboardKey.keyN, LogicalKeyboardKey.keyN);
    expect(find.text('NOTE'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'chasing the sync bug');
    await tester.pump();
    await tester.tap(find.text('SAVE'));
    await settle(tester);

    expect(inScreen(NowScreen, find.text('chasing the sync bug')), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('e alone is inert, and visible while it waits', (tester) async {
    // The same contract `g` has, asserted separately rather than assumed: a
    // second prefix is where machinery written for one shows that it was.
    await bootApp(tester, viewport: _desktop, seed: _seedPair);

    await _press(tester, PhysicalKeyboardKey.keyE, LogicalKeyboardKey.keyE);
    expect(find.text('e …'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    expect(find.text('e …'), findsNothing);

    // And the letter that follows is then just a letter.
    await _press(tester, PhysicalKeyboardKey.keyA, LogicalKeyboardKey.keyA);
    expect(find.text('CHANGE TO'), findsNothing);

    await _press(tester, PhysicalKeyboardKey.keyE, LogicalKeyboardKey.keyE);
    expect(find.text('e …'), findsOneWidget);
    await _press(tester, PhysicalKeyboardKey.escape, LogicalKeyboardKey.escape);
    expect(find.text('e …'), findsNothing);
    await _press(tester, PhysicalKeyboardKey.keyA, LogicalKeyboardKey.keyA);
    expect(find.text('CHANGE TO'), findsNothing);

    await disposeApp(tester);
  });

  testWidgets('a and n do nothing without the prefix', (tester) async {
    // Both letters rewrite something already recorded, which is the case the
    // prefix exists for — a stray key must not reach either.
    await bootApp(tester, viewport: _desktop, seed: _seedPair);

    await _press(tester, PhysicalKeyboardKey.keyA, LogicalKeyboardKey.keyA);
    await _press(tester, PhysicalKeyboardKey.keyN, LogicalKeyboardKey.keyN);

    expect(find.text('CHANGE TO'), findsNothing);
    expect(find.text('NOTE'), findsNothing);

    await disposeApp(tester);
  });

  testWidgets('the keyboard comes back after a shortcut opens a route', (tester) async {
    // The bindings only hear keys while the shell's own node is in the focus
    // chain, and a dialog is a sibling route that takes focus out of it. Flutter
    // should hand it back on pop — but if it does not, the app goes deaf after
    // every shortcut that opens something, and nothing else here would catch it.
    await bootApp(tester, viewport: _desktop, seed: _seed);

    await _edit(tester, PhysicalKeyboardKey.keyN, LogicalKeyboardKey.keyN);
    expect(find.text('NOTE'), findsOneWidget);

    await _press(tester, PhysicalKeyboardKey.escape, LogicalKeyboardKey.escape);
    expect(find.text('NOTE'), findsNothing);

    await _go(tester, PhysicalKeyboardKey.keyR, LogicalKeyboardKey.keyR);
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

    // "s" would start a block, "g" and "e" would arm a prefix.
    await _press(tester, PhysicalKeyboardKey.keyS, LogicalKeyboardKey.keyS);
    await _press(tester, PhysicalKeyboardKey.keyG, LogicalKeyboardKey.keyG);
    await _press(tester, PhysicalKeyboardKey.keyE, LogicalKeyboardKey.keyE);

    expect(
      await db.select(db.activityChanges).get(),
      hasLength(1),
      reason: 's must not start a block while typing',
    );
    expect(find.text('g …'), findsNothing, reason: 'g must not arm while typing');
    expect(find.text('e …'), findsNothing, reason: 'e must not arm while typing');

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

  testWidgets('h and l step the week on Reports and the day on the calendar', (tester) async {
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
      expect(find.textContaining(binding.what), findsWidgets, reason: '${binding.label} is listed');
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

  // Tab is not a binding of ours — it is the one key the framework already
  // handles, and it did nothing because the app gave it nowhere to go. Every
  // control was a GestureDetector, which cannot hold focus, so the only stops in
  // the whole tree were the text fields.
  testWidgets('Tab reaches a button, Shift+Tab leaves it', (tester) async {
    await bootApp(tester, viewport: _desktop, seed: _seed);

    expect(await _tabTo(tester, _startNow), isTrue, reason: 'Tab never reached the start button');

    await _tab(tester, shift: true);
    expect(_focusedReads(_startNow), isFalse);

    await _tab(tester);
    expect(_focusedReads(_startNow), isTrue);

    await disposeApp(tester);
  });

  testWidgets('Enter presses the focused button', (tester) async {
    // Reaching a control is only half of it: a focus ring over something that
    // cannot be pressed from the keyboard is decoration.
    final db = await bootApp(tester, viewport: _desktop, seed: _seed);

    expect(await _tabTo(tester, _startNow), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter, platform: 'web');
    await settle(tester);

    expect(await db.select(db.activityChanges).get(), hasLength(2));

    await disposeApp(tester);
  });

  testWidgets('Tab on a screen with no field does not go deaf', (tester) async {
    // Traversal and the bindings share one node: the shell's handler only hears
    // keys while it is in the focus chain. Moving focus off it with Tab must not
    // cost the keyboard, whichever screen is showing — this held before the
    // controls became focusable too, and the point is that adding stops to the
    // ring did not change it.
    await bootApp(tester, viewport: _desktop, seed: _seed);
    await _go(tester, PhysicalKeyboardKey.keyR, LogicalKeyboardKey.keyR);

    await _tab(tester);

    await _go(tester, PhysicalKeyboardKey.keyN, LogicalKeyboardKey.keyN);
    expect(inScreen(NowScreen, find.text(_startNow)), findsOneWidget);
    expect(inScreen(ReportsScreen, find.text('PER CATEGORY')), findsNothing);

    await disposeApp(tester);
  });

  testWidgets('Tab does not stop on a screen you cannot see', (tester) async {
    // The tabs stay built behind the one on show. If their controls are in the
    // traversal ring, Tab walks through dozens of invisible buttons — which is a
    // worse failure than the one this fixed.
    await bootApp(tester, viewport: _desktop, seed: _seed);

    final visited = <Type?>{};
    for (var i = 0; i < 40; i++) {
      await _tab(tester);
      visited.add(_focusedScreen());
    }

    expect(visited.difference({null, NowScreen}), isEmpty, reason: 'focus left the visible screen');

    await disposeApp(tester);
  });

  testWidgets('a focused button does not silence the bare keys', (tester) async {
    // The typing guard asks whether an EditableText has focus. A button is not
    // one, so holding focus on it must leave the bindings alone — otherwise
    // tabbing anywhere would switch the keyboard off.
    await bootApp(tester, viewport: _desktop, seed: _seed);

    expect(await _tabTo(tester, _startNow), isTrue);
    await _go(tester, PhysicalKeyboardKey.keyR, LogicalKeyboardKey.keyR);

    expect(inScreen(ReportsScreen, find.text('PER CATEGORY')), findsOneWidget);

    await disposeApp(tester);
  });
}
