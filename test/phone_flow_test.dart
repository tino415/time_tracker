// Widget-level smoke test of the phone MVP flow against an in-memory database:
// first run -> create an activity -> it tracks -> the timeline shows the block
// -> tagging a second activity onto it marks it as the forgot-to-switch case.
//
// The same flow runs on a real device in integration_test/flow_test.dart; the
// shared helpers live in test/support/flow_harness.dart.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/phone/screens/activities_screen.dart';
import 'package:time_tracker/phone/screens/now_screen.dart';
import 'package:time_tracker/phone/screens/timeline_screen.dart';

import 'support/flow_harness.dart';

// The default 800x600 test surface is landscape and would push the bottom
// sheets' actions off-screen.
const _phone = Size(400, 880);

void main() {
  testWidgets('first run offers activity creation and starts tracking it', (tester) async {
    await bootApp(tester, viewport: _phone);

    expect(inScreen(NowScreen, find.text('nothing tracked yet')), findsOneWidget);

    await tester.tap(inScreen(NowScreen, find.text('+ NEW ACTIVITY')));
    await settle(tester);
    await fillEditor(tester, 'Deep work', confirm: 'CREATE & SWITCH');

    // The hero now shows the running activity.
    expect(inScreen(NowScreen, find.text('TRACKING')), findsOneWidget);
    expect(inScreen(NowScreen, find.text('Deep work')), findsWidgets);

    await disposeApp(tester);
  });

  testWidgets('the running block appears on the timeline and can be tagged', (tester) async {
    await bootApp(tester, viewport: _phone);

    await tester.tap(inScreen(NowScreen, find.text('+ NEW ACTIVITY')));
    await settle(tester);
    await fillEditor(tester, 'Deep work', confirm: 'CREATE & SWITCH');

    // A second activity, created from the Activities tab (no switch).
    await openTab(tester, 'ACTIVITIES');
    await tester.tap(inScreen(ActivitiesScreen, find.text('+ NEW ACTIVITY')));
    await settle(tester);
    await fillEditor(tester, 'Email', confirm: 'CREATE');

    await openTab(tester, 'TIMELINE');
    // NeoChip uppercases its label, so the day header renders as "TODAY".
    expect(inScreen(TimelineScreen, find.text('TODAY')), findsOneWidget);
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

    await disposeApp(tester);
  });

  testWidgets('re-tapping the running activity does not split the block', (tester) async {
    final db = await bootApp(tester, viewport: _phone);

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

    await disposeApp(tester);
  });
}
