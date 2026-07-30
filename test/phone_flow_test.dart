// Widget-level smoke test of the phone MVP flow against an in-memory database:
// first run -> create an activity -> it tracks -> the timeline shows the block
// -> tagging a second activity onto it marks it as the forgot-to-switch case.
//
// Harness note: the tab bar is an IndexedStack, whose off-screen children stay
// built, so screen finders are scoped with [inScreen] to avoid matching a hidden
// tab's identical label (both Now and Activities offer "+ NEW ACTIVITY").

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/data/providers.dart';
import 'package:time_tracker/phone/phone_app.dart';
import 'package:time_tracker/phone/screens/activities_screen.dart';
import 'package:time_tracker/phone/screens/now_screen.dart';
import 'package:time_tracker/phone/screens/timeline_screen.dart';

/// A bounded stand-in for `pumpAndSettle`, which would never return here: the
/// Now hero animates forever (live dot + second ticker). Route and sheet
/// transitions need *successive* frames — one big `pump(1s)` only starts them —
/// and they ignore pointers until finished, so taps before this are inert.
Future<void> settle(WidgetTester tester, {int frames = 24}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Finder inScreen(Type screen, Finder matching) =>
    find.descendant(of: find.byType(screen), matching: matching);

Future<AppDatabase> pumpApp(WidgetTester tester) async {
  // A phone-shaped viewport — the default 800x600 test surface is landscape and
  // would push the bottom sheets' actions off-screen.
  tester.view.physicalSize = const Size(400, 880);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const PhoneApp(),
    ),
  );
  await settle(tester); // route transition + first stream emissions
  return db;
}

/// Fills the activity-editor sheet (the last text field in the tree is the one
/// in the freshly pushed sheet) and confirms it.
Future<void> fillEditor(WidgetTester tester, String name, {required String confirm}) async {
  await tester.enterText(find.byType(TextField).last, name);
  await tester.pump();
  await tester.tap(find.text(confirm));
  await settle(tester);
}

Future<void> openTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await settle(tester);
}

void main() {
  testWidgets('first run offers activity creation and starts tracking it', (tester) async {
    await pumpApp(tester);

    expect(inScreen(NowScreen, find.text('nothing tracked yet')), findsOneWidget);

    await tester.tap(inScreen(NowScreen, find.text('+ NEW ACTIVITY')));
    await settle(tester);
    await fillEditor(tester, 'Deep work', confirm: 'CREATE & SWITCH');

    // The hero now shows the running activity.
    expect(inScreen(NowScreen, find.text('TRACKING')), findsOneWidget);
    expect(inScreen(NowScreen, find.text('Deep work')), findsWidgets);
  });

  testWidgets('the running block appears on the timeline and can be tagged', (tester) async {
    await pumpApp(tester);

    await tester.tap(inScreen(NowScreen, find.text('+ NEW ACTIVITY')));
    await settle(tester);
    await fillEditor(tester, 'Deep work', confirm: 'CREATE & SWITCH');

    // A second activity, created from the Activities tab (no switch).
    await openTab(tester, 'ACTIVITIES');
    await tester.tap(inScreen(ActivitiesScreen, find.text('+ NEW ACTIVITY')));
    await settle(tester);
    await fillEditor(tester, 'Email', confirm: 'CREATE');

    await openTab(tester, 'TIMELINE');
    expect(inScreen(TimelineScreen, find.text('Today')), findsOneWidget);
    expect(inScreen(TimelineScreen, find.text('● open')), findsOneWidget);

    // Tag the open block with the second activity (the forgot-to-switch case).
    await tester.tap(inScreen(TimelineScreen, find.text('Deep work')));
    await settle(tester);
    await tester.tap(find.text('+ TAG ANOTHER ACTIVITY'));
    await settle(tester);
    await tester.tap(find.text('Email').last); // the picker row
    await settle(tester);

    expect(inScreen(TimelineScreen, find.text('Deep work  +  Email')), findsOneWidget);
    expect(inScreen(TimelineScreen, find.textContaining('forgot to switch')), findsOneWidget);
  });

  testWidgets('re-tapping the running activity does not split the block', (tester) async {
    final db = await pumpApp(tester);

    await tester.tap(inScreen(NowScreen, find.text('+ NEW ACTIVITY')));
    await settle(tester);
    // Bookmark it so it lands in the quick-switch grid.
    await tester.enterText(find.byType(TextField).last, 'Deep work');
    await tester.pump();
    await tester.tap(find.textContaining('bookmark (quick-switch'));
    await tester.pump();
    await tester.tap(find.text('CREATE & SWITCH'));
    await settle(tester);

    // Tap the grid tile for what is already running (the grid is last on screen).
    await tester.tap(inScreen(NowScreen, find.text('Deep work')).last);
    await settle(tester);

    expect((await db.select(db.activityChanges).get()).length, 1);
  });
}
