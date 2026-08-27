// Widget-level test of the per-day section on Reports: a bar per day of the
// week, and tapping one scopes the per-category bars to that day.
//
// History is seeded in *last* week and the report stepped back to it, so the
// expected totals do not depend on when the suite runs. The seed starts on
// Saturday evening: tracking never stops, so an earlier start would bury the day
// it is meant to be about under the days that follow it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/data/drift_repositories.dart';
import 'package:time_tracker/domain/reporting.dart';
import 'package:time_tracker/phone/screens/reports_screen.dart';

import 'support/flow_harness.dart';

/// Tall enough to hold both sections without scrolling: an off-screen row is not
/// built at all in a `ListView`, and would be unfindable rather than merely out
/// of sight.
const _tallPhone = Size(400, 1400);

DateTime get _thisMonday => localWeekRange(DateTime.now()).start;

/// A day of last week — `DateTime` normalises the negative day, and the day
/// arithmetic survives a DST change that `Duration` would shift off midnight.
DateTime _lastWeek(int weekday, [int hour = 0]) {
  final m = _thisMonday;
  return DateTime(m.year, m.month, m.day - 7 + (weekday - DateTime.monday), hour);
}

/// The row label the day section renders, spelled out rather than borrowed from
/// `format.dart`, so a change to it fails here.
String _dayLabel(DateTime day) {
  const names = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
  return '${names[day.weekday - 1]} ${day.day}';
}

/// Saturday 20:00 Work, 22:00 Break, then Work again from Sunday 01:00.
///
/// So Saturday holds 2h Work + 2h Break, and the Break block crosses midnight —
/// the hour after it belongs to Sunday, which the rest of the day's Work fills
/// out to a full 24h (the last change runs to the end of the week).
Future<void> _seedLastWeekend(AppDatabase db) async {
  final activities = DriftActivityRepository(db);
  final changes = DriftChangeRepository(db);

  final work = await activities.createActivity(name: 'Work', color: '#4F8FEE');
  final brk = await activities.createActivity(name: 'Break', color: '#9A9B95');

  await changes.switchTo(work.syncId, at: _lastWeek(DateTime.saturday, 20));
  await changes.switchTo(brk.syncId, at: _lastWeek(DateTime.saturday, 22));
  await changes.switchTo(work.syncId, at: _lastWeek(DateTime.sunday, 1));
}

/// The report, stepped back to the seeded week.
Future<void> _openLastWeek(WidgetTester tester) async {
  await bootApp(tester, viewport: _tallPhone, seed: _seedLastWeekend);
  await openTab(tester, 'REPORTS');
  await tester.tap(inScreen(ReportsScreen, find.text('‹')));
  await settle(tester);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadMonoFont();
  });

  testWidgets('every day of the week gets a row, midnight-split', (tester) async {
    await _openLastWeek(tester);

    final saturday = _lastWeek(DateTime.saturday);
    expect(
      inScreen(ReportsScreen, find.text(_dayLabel(_lastWeek(DateTime.monday)))),
      findsOneWidget,
    );
    expect(inScreen(ReportsScreen, find.text(_dayLabel(saturday))), findsOneWidget);

    // 20:00 to midnight on Saturday; the hour the Break block spends past
    // midnight lands on Sunday, which tracking then fills to the full day.
    expect(inScreen(ReportsScreen, find.text('4h 00m')), findsOneWidget);
    expect(inScreen(ReportsScreen, find.text('24h 00m')), findsOneWidget);
    // Monday to Friday, untracked.
    expect(inScreen(ReportsScreen, find.text('0m')), findsNWidgets(5));

    await disposeApp(tester);
  });

  testWidgets('tapping a day scopes the category bars to it', (tester) async {
    await _openLastWeek(tester);
    final saturday = _lastWeek(DateTime.saturday);

    // The week: 25h of Work against 3h of Break.
    expect(inScreen(ReportsScreen, find.text('25h 00m')), findsOneWidget);

    await tester.tap(inScreen(ReportsScreen, find.text(_dayLabel(saturday))));
    await settle(tester);

    expect(
      inScreen(ReportsScreen, find.text('PER CATEGORY · ${_dayLabel(saturday)}')),
      findsOneWidget,
    );
    // Saturday alone: two hours each, and the day row keeps the week's totals.
    expect(inScreen(ReportsScreen, find.text('2h 00m')), findsNWidgets(2));
    expect(inScreen(ReportsScreen, find.text('4h 00m')), findsOneWidget);
    expect(inScreen(ReportsScreen, find.text('25h 00m')), findsNothing);

    // Tapping the same day again puts the week back.
    await tester.tap(inScreen(ReportsScreen, find.text(_dayLabel(saturday))));
    await settle(tester);
    expect(inScreen(ReportsScreen, find.text('25h 00m')), findsOneWidget);
    expect(inScreen(ReportsScreen, find.text('PER CATEGORY')), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('stepping the week drops the selected day', (tester) async {
    await _openLastWeek(tester);

    await tester.tap(inScreen(ReportsScreen, find.text(_dayLabel(_lastWeek(DateTime.saturday)))));
    await settle(tester);
    await tester.tap(inScreen(ReportsScreen, find.text('›'))); // back to this week
    await settle(tester);

    // A day of last week means nothing in this one, so the scope is the week.
    expect(inScreen(ReportsScreen, find.text('PER CATEGORY')), findsOneWidget);

    await disposeApp(tester);
  });
}
