// The timeline list splits blocks at midnight: sleep from 23:00 to 7:10 shows
// as an hour under yesterday and 7h 10m under today, matching the attribution
// the daily report has always made by clipping. The block itself stays one row
// in the data — both cards open the same sheet and act on it whole.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/data/drift_repositories.dart';
import 'package:time_tracker/format.dart';
import 'package:time_tracker/phone/screens/timeline_screen.dart';

import 'support/flow_harness.dart';

const _phone = Size(360, 780);

/// Sleep started yesterday 23:00, work took over at 7:10 today.
Future<void> _sleepAcrossMidnight(AppDatabase db) async {
  final activities = DriftActivityRepository(db);
  final changes = DriftChangeRepository(db);
  final now = DateTime.now();

  final sleep = await activities.createActivity(name: 'Sleep', color: '#4F8FEE');
  final work = await activities.createActivity(name: 'Work', color: '#63C89B');
  await changes.switchTo(sleep.syncId, at: DateTime(now.year, now.month, now.day - 1, 23));
  await changes.switchTo(work.syncId, at: DateTime(now.year, now.month, now.day, 7, 10));
}

String _sleepSinceMidnightToday() {
  final now = DateTime.now();
  final midnight = DateTime(now.year, now.month, now.day);
  final wakeUp = DateTime(now.year, now.month, now.day, 7, 10);
  return formatSpan(wakeUp.difference(midnight));
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadMonoFont();
  });

  testWidgets('a block crossing midnight shows once under each day', (tester) async {
    await bootApp(tester, viewport: _phone, seed: _sleepAcrossMidnight);
    await openTab(tester, 'TIMELINE');

    // One card per day the block touches, each with its day's share.
    expect(inScreen(TimelineScreen, find.text('Sleep')), findsNWidgets(2));
    expect(inScreen(TimelineScreen, find.text('23:00 – 00:00')), findsOneWidget);
    expect(inScreen(TimelineScreen, find.text('00:00 – 07:10')), findsOneWidget);
    expect(inScreen(TimelineScreen, find.text('1h 00m')), findsOneWidget);
    expect(inScreen(TimelineScreen, find.text(_sleepSinceMidnightToday())), findsOneWidget);

    // Both day groups exist; the open block sits under today.
    expect(inScreen(TimelineScreen, find.text('TODAY')), findsOneWidget);
    expect(inScreen(TimelineScreen, find.text('YESTERDAY')), findsOneWidget);
    expect(inScreen(TimelineScreen, find.text('● open')), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('a slice opens the sheet for the whole block', (tester) async {
    await bootApp(tester, viewport: _phone, seed: _sleepAcrossMidnight);
    await openTab(tester, 'TIMELINE');

    // The yesterday card — an hour-long display slice of the real block.
    await tester.tap(inScreen(TimelineScreen, find.text('23:00 – 00:00')));
    await settle(tester);

    // The sheet is the block's, not the slice's: same actions as ever.
    expect(find.text('BLOCK'), findsOneWidget);
    expect(find.text('EDIT START TIME'), findsOneWidget);

    await disposeApp(tester);
  });
}
