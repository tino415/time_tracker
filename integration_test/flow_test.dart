// On-device end-to-end run of the phone MVP flow, ending with the Now hero's
// own edits (retime the open block, re-point it). Same screens and helpers as
// test/phone_flow_test.dart, but on a real engine: real rasterisation, the
// device's own screen size, and a real sqlite3 library rather than the host's.
//
// Run with `just e2e` (phone emulator) or `just e2e-watch`.
//
// The database is still an in-memory override, so a run never touches whatever
// the device has stored and repeated runs start from a clean slate.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:time_tracker/data/drift_repositories.dart';
import 'package:time_tracker/format.dart';
import 'package:time_tracker/phone/screens/activities_screen.dart';
import 'package:time_tracker/phone/screens/calendar_screen.dart';
import 'package:time_tracker/phone/screens/now_screen.dart';
import 'package:time_tracker/phone/screens/reports_screen.dart';
import 'package:time_tracker/phone/screens/timeline_screen.dart';

import '../test/support/flow_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('create an activity, track it, tag the block, report and chart it', (tester) async {
    final db = await bootApp(tester);

    // ---- Now: empty state -> create & switch -------------------------------
    expect(inScreen(NowScreen, find.text('nothing tracked yet')), findsOneWidget);

    await tester.tap(inScreen(NowScreen, find.text('+ NEW ACTIVITY')));
    await settle(tester);
    await fillEditor(tester, 'Deep work', confirm: 'CREATE & SWITCH');

    expect(inScreen(NowScreen, find.text('TRACKING')), findsOneWidget);
    expect(inScreen(NowScreen, find.text('Deep work')), findsWidgets);

    // ---- Activities: a second activity, without switching ------------------
    await openTab(tester, 'ACTIVITIES');
    await tester.tap(inScreen(ActivitiesScreen, find.text('+ NEW ACTIVITY')));
    await settle(tester);
    await fillEditor(tester, 'Email', confirm: 'CREATE');
    expect(inScreen(ActivitiesScreen, find.text('Email')), findsWidgets);

    // ---- Timeline: the open block, then tag it -----------------------------
    await openTab(tester, 'TIMELINE');
    expect(inScreen(TimelineScreen, find.text('TODAY')), findsOneWidget);
    expect(inScreen(TimelineScreen, find.text('● open')), findsOneWidget);

    await tester.tap(inScreen(TimelineScreen, find.text('Deep work')));
    await settle(tester);
    await tester.tap(find.text('+ ANOTHER ACTIVITY'));
    await settle(tester);
    await tester.tap(find.text('Email').last);
    await settle(tester);

    expect(inScreen(TimelineScreen, find.text('Deep work  +  Email')), findsOneWidget);
    expect(inScreen(TimelineScreen, find.textContaining('forgot to switch')), findsOneWidget);

    // ---- Reports: the week rolls the block up ------------------------------
    await openTab(tester, 'REPORTS');
    expect(inScreen(ReportsScreen, find.text('PER CATEGORY')), findsOneWidget);
    expect(inScreen(ReportsScreen, find.text('This week')), findsOneWidget);
    // Both tagged activities are top-level, so both get an even-split bar.
    expect(inScreen(ReportsScreen, find.text('Deep work')), findsOneWidget);
    expect(inScreen(ReportsScreen, find.text('Email')), findsOneWidget);

    // ---- Calendar: the same block on the day axis --------------------------
    await openTab(tester, 'TIMELINE');
    await tester.tap(find.text('▦ CALENDAR'));
    await settle(tester);
    expect(find.byType(CalendarScreen), findsOneWidget);
    expect(inScreen(CalendarScreen, find.text('Today')), findsOneWidget);
    // The block is only seconds old here, so its card is a sliver — it still has
    // to render.
    expect(inScreen(CalendarScreen, find.text('Deep work  +  Email')), findsOneWidget);

    // ---- Now: retime the running block, then re-point it -------------------
    // The two verbs the hero adds on top of the list views. A third activity,
    // because "change activity" excludes whatever the block already tracks.
    await openTab(tester, 'ACTIVITIES');
    await tester.tap(inScreen(ActivitiesScreen, find.text('+ NEW ACTIVITY')));
    await settle(tester);
    await fillEditor(tester, 'Review', confirm: 'CREATE');
    await openTab(tester, 'NOW');

    final before = (await DriftChangeRepository(db).loadChanges()).single.changedAt;

    await tester.tap(inScreen(NowScreen, find.textContaining('since ')));
    await settle(tester);
    await tester.tap(find.text('-15'));
    await settle(tester);
    await tester.tap(find.text('SAVE'));
    await settle(tester);

    final after = (await DriftChangeRepository(db).loadChanges()).single.changedAt;
    expect(before.difference(after), const Duration(minutes: 15));
    expect(inScreen(NowScreen, find.text('since ${formatTimeOfDay(after)}')), findsOneWidget);

    await tester.tap(inScreen(NowScreen, find.text('⋯ EDIT BLOCK')));
    await settle(tester);
    // The row's own swap — and this block was tagged with Email above, so there
    // are two rows and two of them. Taking the first and then reading the
    // picker's title is what makes the choice a stated one: the title names the
    // row it came from, so a change in that order fails here loudly rather than
    // silently swapping the other activity.
    await tester.tap(find.text('SWAP').first);
    await settle(tester);
    expect(find.textContaining('REPLACE DEEP WORK WITH'), findsOneWidget);

    await tester.tap(find.text('Review').last);
    await settle(tester);

    // Re-pointed rather than added to: Review stands where Deep work did, and
    // Email is untouched beside it.
    expect(inScreen(NowScreen, find.textContaining('Review')), findsWidgets);
    expect(inScreen(NowScreen, find.textContaining('Deep work')), findsNothing);
    expect(inScreen(NowScreen, find.textContaining('Email')), findsWidgets);
    expect(
      (await DriftChangeRepository(db).loadChanges()),
      hasLength(1),
      reason: 'a correction re-points the block; it must not open a boundary',
    );

    await disposeApp(tester);
  });
}
