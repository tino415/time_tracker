// On-device end-to-end run of the phone MVP flow. Same screens and helpers as
// test/phone_flow_test.dart, but on a real engine: real rasterisation, the
// device's own screen size, and a real sqlite3 library rather than the host's.
//
// Run with `just e2e` (phone emulator) or `just e2e-watch`.
//
// The database is still an in-memory override, so a run never touches whatever
// the device has stored and repeated runs start from a clean slate.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:time_tracker/phone/screens/activities_screen.dart';
import 'package:time_tracker/phone/screens/now_screen.dart';
import 'package:time_tracker/phone/screens/reports_screen.dart';
import 'package:time_tracker/phone/screens/timeline_screen.dart';

import '../test/support/flow_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('create an activity, track it, tag the block, see it reported', (tester) async {
    await bootApp(tester);

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
    await tester.tap(find.text('+ TAG ANOTHER ACTIVITY'));
    await settle(tester);
    await tester.tap(find.text('Email').last);
    await settle(tester);

    expect(inScreen(TimelineScreen, find.text('Deep work  +  Email')), findsOneWidget);
    expect(inScreen(TimelineScreen, find.textContaining('forgot to switch')), findsOneWidget);

    // ---- Reports: the week rolls the block up ------------------------------
    await openTab(tester, 'REPORTS');
    expect(inScreen(ReportsScreen, find.text('TRACKED THIS WEEK')), findsOneWidget);
    expect(inScreen(ReportsScreen, find.text('This week')), findsOneWidget);
    // Both tagged activities are top-level, so both get an even-split bar.
    expect(inScreen(ReportsScreen, find.text('Deep work')), findsOneWidget);
    expect(inScreen(ReportsScreen, find.text('Email')), findsOneWidget);

    await disposeApp(tester);
  });
}
