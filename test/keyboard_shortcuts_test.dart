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

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/data/drift_repositories.dart';
import 'package:time_tracker/data/manual_sync.dart';
import 'package:time_tracker/data/providers.dart';
import 'package:time_tracker/data/sync_service.dart';
import 'package:time_tracker/data/sync_store.dart';
import 'package:time_tracker/data/sync_transport.dart';
import 'package:time_tracker/domain/sync_protocol.dart';
import 'package:time_tracker/domain/unsorted.dart';
import 'package:time_tracker/phone/phone_app.dart';
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

/// The primary button `_FirstRunEmpty` offers when the database has no
/// activities yet — the one case where the focus ring and the fill it sits on
/// were once the same colour, so it is the control the ring test targets.
const _newActivity = '+ NEW ACTIVITY';

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

/// A key held with the platform's own command modifier — the one exception to
/// this file's bare-keys rule.
///
/// Ctrl by default, because `flutter test` reports Android and the binding
/// follows the platform rather than the keyboard. [meta] takes the Apple branch
/// instead, which needs [debugDefaultTargetPlatformOverride] to be set by the
/// caller or the two disagree.
Future<void> _pressPrimary(
  WidgetTester tester,
  PhysicalKeyboardKey physical,
  LogicalKeyboardKey legend, {
  bool meta = false,
}) async {
  const web = 'web';
  final modifier = meta ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(modifier, platform: web);
  await tester.sendKeyDownEvent(legend, physicalKey: physical, platform: web);
  await tester.sendKeyUpEvent(legend, physicalKey: physical, platform: web);
  await tester.sendKeyUpEvent(modifier, platform: web);
  await settle(tester);
}

/// The picker's own field, which is what proves it is open — its hint is not a
/// string anything else in the app uses.
Finder _picker() => find.text('what do you want to do?');

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

/// A root with a tracked child, so the Reports category row it produces has
/// something to drill into — a leaf row takes no `onTap` and so is never a
/// focus stop, which would make it useless for the Tab test below.
Future<void> _seedDrillable(AppDatabase db) async {
  final activities = DriftActivityRepository(db);
  final changes = DriftChangeRepository(db);
  final work = await activities.createActivity(name: 'Work', color: '#4F8FEE');
  final payout = await activities.createActivity(
    name: 'Payout',
    color: '#EE7C4F',
    parentId: work.syncId,
  );
  final now = DateTime.now();
  await changes.switchTo(work.syncId, at: now.subtract(const Duration(hours: 2)));
  await changes.switchTo(payout.syncId, at: now.subtract(const Duration(hours: 1)));
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

/// Refuses everything it is pushed, so one round trip produces a status string
/// without a server behind it.
class _RejectingTransport implements SyncTransport {
  @override
  Future<void> claimAccount() async {}

  @override
  Future<SyncResponse> exchange(SyncRequest request) async => SyncResponse(
    cursor: '1',
    rejected: [
      for (final a in request.activities) a.syncId,
      for (final c in request.changes) c.syncId,
    ],
  );
}

/// [_seed] refused by [_RejectingTransport]: one activity and one change pushed,
/// both superseded.
const _refused = '↑0 ↓0 · 2 superseded';

/// Boots with a sync server configured but no account — the shape `r` has to be
/// inert in. Pass [service] for the authenticated shape, where it works.
///
/// [bootApp] cannot serve here: it overrides only the database, so `SYNC_URL` is
/// whatever the build had, which under `flutter test` is empty.
Future<AppDatabase> _bootWithSync(
  WidgetTester tester, {
  required Size viewport,
  SyncService Function(AppDatabase db)? service,
  Future<void> Function(AppDatabase db)? seed,
}) async {
  tester.view.physicalSize = viewport;
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
        syncConfigProvider.overrideWithValue(const SyncConfig(baseUrl: 'https://sync.example')),
        if (service != null) syncServiceProvider.overrideWithValue(service(db)),
      ],
      child: const PhoneApp(),
    ),
  );
  await settle(tester);
  return db;
}

SyncService _rejectingService(AppDatabase db) =>
    SyncService(store: SyncStore(db), transport: _RejectingTransport(), backend: 'test');

/// Boots with an ancestor holding whatever the shortcut layer declined.
///
/// Key events walk up the focus chain until something reports them handled, so a
/// node above the app sees exactly the keys the bindings passed on.
Future<List<LogicalKeyboardKey>> _bootWatchingDeclinedKeys(
  WidgetTester tester, {
  SyncService Function(AppDatabase db)? service,
}) async {
  tester.view.physicalSize = _desktop;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final declined = <LogicalKeyboardKey>[];
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  await _seed(db);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        syncConfigProvider.overrideWithValue(const SyncConfig(baseUrl: 'https://sync.example')),
        if (service != null) syncServiceProvider.overrideWithValue(service(db)),
      ],
      child: Focus(
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent) declined.add(event.logicalKey);
          return KeyEventResult.ignored;
        },
        child: const PhoneApp(),
      ),
    ),
  );
  await settle(tester);
  return declined;
}

/// What the last manual sync came to, or null while none has run.
///
/// Asked of the state rather than of the screen: in both inert shapes the status
/// line is not rendered at all, so an empty screen would pass whether the key
/// did nothing or did everything.
String? _syncStatus(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(PhoneApp)),
).read(manualSyncProvider).status;

/// A ref for the availability predicates, which are asked the same question the
/// key handler asks.
WidgetRef _ref(WidgetTester tester) => tester.element(find.byType(AppShortcuts)) as WidgetRef;

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

  group('the command picker', () {
    testWidgets('opens on the one binding that holds a modifier', (tester) async {
      await bootApp(tester, viewport: _desktop, seed: _seed);

      await _pressPrimary(tester, PhysicalKeyboardKey.keyK, LogicalKeyboardKey.keyK);

      expect(_picker(), findsOneWidget);

      await disposeApp(tester);
    });

    testWidgets('Cmd rather than Ctrl where the platform says Cmd', (tester) async {
      // The modifier follows the platform, not the keyboard: binding both
      // everywhere would swallow Ctrl+K on a Mac, where every text field treats
      // it as "delete to end of line".
      // Cleared inside the body, not in a tearDown: the binding asserts every
      // foundation debug variable is back to its default before the test
      // returns, which is earlier than a tearDown runs.
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await bootApp(tester, viewport: _desktop, seed: _seed);

        await _pressPrimary(tester, PhysicalKeyboardKey.keyK, LogicalKeyboardKey.keyK, meta: true);
        expect(_picker(), findsOneWidget);

        await disposeApp(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('opens while a field has focus, unlike everything else', (tester) async {
      // Deliberately ahead of the typing guard. The picker is most useful from
      // inside a field: you are already typing, and this is where you go when
      // what you want is not what the field does.
      await bootApp(tester, viewport: _desktop, seed: _seed);
      await tester.tap(_searchField());
      await settle(tester);
      await tester.enterText(_searchField(), 'st');
      await settle(tester);

      await _pressPrimary(tester, PhysicalKeyboardKey.keyK, LogicalKeyboardKey.keyK);

      expect(_picker(), findsOneWidget);

      await disposeApp(tester);
    });

    testWidgets('a named command runs, through the same path its key would', (tester) async {
      await bootApp(tester, viewport: _desktop, seed: _seed);
      await _pressPrimary(tester, PhysicalKeyboardKey.keyK, LogicalKeyboardKey.keyK);

      await tester.enterText(find.byType(TextField).last, 'reports');
      await settle(tester);
      await _press(tester, PhysicalKeyboardKey.enter, LogicalKeyboardKey.enter);

      expect(_picker(), findsNothing);
      expect(inScreen(ReportsScreen, find.text('PER CATEGORY')), findsOneWidget);

      await disposeApp(tester);
    });

    testWidgets('naming an activity starts it', (tester) async {
      // The half a command list alone would not cover. "Start deep work" is the
      // thing people most often want, and it is not a command — it is a name.
      final db = await bootApp(tester, viewport: _desktop, seed: _seedPair);
      expect(await db.select(db.activityChanges).get(), hasLength(1));

      await _pressPrimary(tester, PhysicalKeyboardKey.keyK, LogicalKeyboardKey.keyK);
      await tester.enterText(find.byType(TextField).last, _other);
      await settle(tester);
      await _press(tester, PhysicalKeyboardKey.enter, LogicalKeyboardKey.enter);

      expect(_picker(), findsNothing);
      final changes = await db.select(db.activityChanges).get();
      expect(changes, hasLength(2), reason: 'a boundary was opened');

      await disposeApp(tester);
    });

    testWidgets('the keyboard is not deaf after the picker closes', (tester) async {
      // A modal route takes focus out of the shell's subtree by design, so every
      // bare key stops arriving until it is handed back. Nothing else here would
      // catch it: the picker would keep working and everything else would quietly
      // stop.
      await bootApp(tester, viewport: _desktop, seed: _seed);
      await _pressPrimary(tester, PhysicalKeyboardKey.keyK, LogicalKeyboardKey.keyK);
      await _press(tester, PhysicalKeyboardKey.escape, LogicalKeyboardKey.escape);
      expect(_picker(), findsNothing);

      await _go(tester, PhysicalKeyboardKey.keyR, LogicalKeyboardKey.keyR);

      expect(inScreen(ReportsScreen, find.text('PER CATEGORY')), findsOneWidget);

      await disposeApp(tester);
    });

    testWidgets('a command this build cannot run is not offered', (tester) async {
      // Same contract the help list follows: there is no SYNC_URL under
      // `flutter test`, so sync is absent rather than listed and inert.
      await bootApp(tester, viewport: _desktop, seed: _seed);
      await _pressPrimary(tester, PhysicalKeyboardKey.keyK, LogicalKeyboardKey.keyK);

      await tester.enterText(find.byType(TextField).last, 'sync');
      await settle(tester);

      expect(find.text('Sync now'), findsNothing);
      expect(find.text('Sync account'), findsNothing);
      expect(find.text('nothing matches'), findsOneWidget);

      await disposeApp(tester);
    });
  });

  testWidgets('? lists the bindings, and the list is the table', (tester) async {
    await bootApp(tester, viewport: _desktop, seed: _seed);

    await _press(tester, PhysicalKeyboardKey.slash, LogicalKeyboardKey.slash, shift: true);

    expect(find.text('Keyboard'), findsOneWidget);
    // Generated from the same table that installs them, so the two cannot drift.
    // Bindings this build cannot run are skipped on both sides — the list is
    // what the keyboard does here, not what the table could hold.
    final ref = _ref(tester);
    for (final binding in shortcutBindings) {
      if (binding.available?.call(ref) == false) continue;
      expect(find.textContaining(binding.what), findsWidgets, reason: '${binding.label} is listed');
    }

    await disposeApp(tester);
  });

  testWidgets('the list drops a key this build does not have', (tester) async {
    // No SYNC_URL under `flutter test`, so there is no sync to offer — and a
    // list advertising a key that does nothing is worse than a shorter list.
    await bootApp(tester, viewport: _desktop, seed: _seed);

    await _press(tester, PhysicalKeyboardKey.slash, LogicalKeyboardKey.slash, shift: true);
    expect(find.textContaining('Sync now'), findsNothing);

    await disposeApp(tester);
  });

  testWidgets('the list carries the sync key once there is one', (tester) async {
    await _bootWithSync(tester, viewport: _desktop, seed: _seed, service: _rejectingService);

    await _press(tester, PhysicalKeyboardKey.slash, LogicalKeyboardKey.slash, shift: true);
    expect(find.textContaining('Sync now'), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('the header button opens the same list', (tester) async {
    // The button is web-only and kIsWeb is false here, so what this checks is
    // the dialog it opens. Its presence is the browser suite's job.
    await bootApp(tester, viewport: _desktop, seed: _seed);

    // Not awaited: the future completes when the dialog is *dismissed*, so
    // awaiting it waits forever for a tap this test has not made yet.
    unawaited(showShortcutsHelp(tester.element(find.byType(NowScreen)), _ref(tester)));
    await settle(tester);

    expect(find.text('Keyboard'), findsOneWidget);
    expect(find.textContaining('Previous period'), findsWidgets);

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

  testWidgets('Tab reaches a category row on Reports, and Enter expands it', (tester) async {
    // The behaviour the whole `_ReportBar` -> `NeoPressable` conversion exists
    // for: a category row is a real control, not a `GestureDetector` that
    // Tab walks straight past.
    await bootApp(tester, viewport: _desktop, seed: _seedDrillable);
    await _go(tester, PhysicalKeyboardKey.keyR, LogicalKeyboardKey.keyR);

    expect(inScreen(ReportsScreen, find.text('Payout')), findsNothing);
    expect(await _tabTo(tester, 'Work'), isTrue, reason: 'Tab never reached the category row');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter, platform: 'web');
    await settle(tester);

    expect(inScreen(ReportsScreen, find.text('Payout')), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('focus draws a brand ring, even on a brand-filled button', (tester) async {
    // The primary button is the one case where the ring and the fill it sits
    // on were the same colour — a plain button passing this would not have
    // caught that regression.
    await bootApp(tester, viewport: _desktop);

    Finder pressableShadow() => find.descendant(
      of: find.ancestor(of: find.text(_newActivity), matching: find.byType(NeoPressable)),
      matching: find.byType(AnimatedContainer),
    );
    List<BoxShadow> shadows() =>
        (tester.widget<AnimatedContainer>(pressableShadow()).decoration as BoxDecoration)
            .boxShadow ??
        const [];
    final brand = neo(tester.element(find.byType(NowScreen))).brand;
    // Spread, not merely offset, is what distinguishes the fix from the bug it
    // replaces: a colour-swapped hard shadow would also carry a brand-coloured
    // entry, but with no spread it draws no ring at all.
    bool hasBrandRing() => shadows().any((s) => s.color == brand && s.spreadRadius > 0);

    expect(hasBrandRing(), isFalse, reason: 'unfocused button carries no brand ring');

    expect(await _tabTo(tester, _newActivity), isTrue);
    expect(hasBrandRing(), isTrue, reason: 'focused button carries a brand ring');

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

  testWidgets('r syncs, and says what came of it', (tester) async {
    // The outcome has to survive the press: it used to live in the button's own
    // State, which a key handler has no way to reach.
    await _bootWithSync(tester, viewport: _desktop, seed: _seed, service: _rejectingService);

    await _press(tester, PhysicalKeyboardKey.keyR, LogicalKeyboardKey.keyR);

    expect(_syncStatus(tester), _refused);

    // And it is still there to be read once the controls are opened. This is the
    // half the move to a menu put at risk: the outcome of a sync you asked for
    // by key must not depend on a surface having been open at the time.
    await tester.tap(find.text('⚙ MENU'));
    await settle(tester);
    expect(find.text(_refused), findsOneWidget, reason: 'the menu shows what the key did');

    await disposeApp(tester);
  });

  testWidgets('r is inert in a build with no server', (tester) async {
    // Scoped by configuration, not by screen: there is nothing to sync *with*
    // here, so the key is not merely inapplicable — it is absent.
    await bootApp(tester, viewport: _desktop, seed: _seed);

    await _press(tester, PhysicalKeyboardKey.keyR, LogicalKeyboardKey.keyR);

    expect(_syncStatus(tester), isNull);

    await disposeApp(tester);
  });

  testWidgets('r is inert with a server but no account', (tester) async {
    // Sync is opt-in. Until this device has joined an account the button is an
    // invitation to set one up, and the key has nothing to run.
    await _bootWithSync(tester, viewport: _desktop, seed: _seed);

    await _press(tester, PhysicalKeyboardKey.keyR, LogicalKeyboardKey.keyR);

    expect(_syncStatus(tester), isNull);
    expect(find.text('SET UP SYNC'), findsNothing, reason: 'nor did it open the setup sheet');

    await disposeApp(tester);
  });

  testWidgets('r does not sync while a field has focus', (tester) async {
    // The guard covers the new key like every other: "r" is a letter someone is
    // entitled to type into a search box.
    await _bootWithSync(tester, viewport: _desktop, seed: _seed, service: _rejectingService);

    await tester.tap(_searchField());
    await settle(tester);
    await tester.enterText(_searchField(), 'r');
    await settle(tester);

    await _press(tester, PhysicalKeyboardKey.keyR, LogicalKeyboardKey.keyR);

    expect(_syncStatus(tester), isNull);

    await disposeApp(tester);
  });

  testWidgets('g r still reaches Reports, and does not sync on the way', (tester) async {
    // Bare and prefixed rows share the physical key. They are disjoint because
    // the match requires a binding's prefix to be the armed one — this is that
    // claim, made where both rows exist.
    await _bootWithSync(tester, viewport: _desktop, seed: _seed, service: _rejectingService);

    await _go(tester, PhysicalKeyboardKey.keyR, LogicalKeyboardKey.keyR);

    expect(inScreen(ReportsScreen, find.text('PER CATEGORY')), findsOneWidget);
    expect(_syncStatus(tester), isNull);

    await disposeApp(tester);
  });

  testWidgets('an unavailable key is declined rather than swallowed', (tester) async {
    // The handler-side availability check has no other visible effect, because
    // ManualSync also refuses a null service — so without this the check could be
    // deleted and every other test would still pass. What it decides is whether
    // the key stays available to anything above the shortcut layer.
    final declined = await _bootWatchingDeclinedKeys(tester);

    await _press(tester, PhysicalKeyboardKey.keyR, LogicalKeyboardKey.keyR);

    expect(
      declined,
      contains(LogicalKeyboardKey.keyR),
      reason: 'a build with no sync claimed the key anyway',
    );

    await disposeApp(tester);
  });

  testWidgets('an available key is consumed', (tester) async {
    final declined = await _bootWatchingDeclinedKeys(tester, service: _rejectingService);

    await _press(tester, PhysicalKeyboardKey.keyR, LogicalKeyboardKey.keyR);

    expect(
      declined,
      isNot(contains(LogicalKeyboardKey.keyR)),
      reason: 'the binding ran but let the key carry on past it',
    );

    await disposeApp(tester);
  });
}
