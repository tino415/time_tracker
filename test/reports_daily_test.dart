// Widget-level test of Reports' month/week/day toggle: only one period is on screen
// at a time, the day selector steps and refuses the future the same way the
// week selector always has, and switching modes carries the period being
// looked at across rather than resetting to today/this week.
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

/// Tall enough to hold the selector, the toggle and the category section
/// without scrolling: an off-screen row is not built at all in a `ListView`,
/// and would be unfindable rather than merely out of sight.
const _tallPhone = Size(400, 1400);

DateTime get _thisMonday => localWeekRange(DateTime.now()).start;

/// A day of last week — `DateTime` normalises the negative day, and the day
/// arithmetic survives a DST change that `Duration` would shift off midnight.
DateTime _lastWeek(int weekday, [int hour = 0]) {
  final m = _thisMonday;
  return DateTime(m.year, m.month, m.day - 7 + (weekday - DateTime.monday), hour);
}

/// The label the day selector renders, spelled out rather than borrowed from
/// `reports_screen.dart`, so a change to it fails here. Mirrors what the
/// calendar and timeline already call "Today"/"Yesterday".
String _dayLabel(DateTime day, [DateTime? at]) {
  final now = at ?? DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  const names = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
  return '${names[day.weekday - 1]} ${day.day}';
}

/// The label the week selector renders for the week containing [day].
String _weekLabel(DateTime day) {
  final week = localWeekRange(day);
  if (week.start == _thisMonday) return 'This week';
  final end = DateTime(week.start.year, week.start.month, week.start.day + 6);
  return '${week.start.day}/${week.start.month} – ${end.day}/${end.month}';
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

/// Work's week total under [_seedLastWeekend]: 25h, or 24h and 26h when last
/// Sunday was a DST change and lasted 23h or 25h.
String get _lastWeekWork {
  final saturday = _lastWeek(DateTime.saturday, 22).difference(_lastWeek(DateTime.saturday, 20));
  final sunday = _thisMonday.difference(_lastWeek(DateTime.sunday, 1));
  return '${(saturday + sunday).inHours}h 00m';
}

/// The report, stepped back to the seeded week.
Future<void> _openLastWeek(WidgetTester tester) async {
  await bootApp(tester, viewport: _tallPhone, seed: _seedLastWeekend);
  await openTab(tester, 'REPORTS');
  await tester.tap(inScreen(ReportsScreen, find.text('‹')));
  await settle(tester);
}

Future<void> _toggleToDay(WidgetTester tester) async {
  await tester.tap(inScreen(ReportsScreen, find.text('▤ DAY')));
  await settle(tester);
}

Future<void> _toggleToWeek(WidgetTester tester) async {
  await tester.tap(inScreen(ReportsScreen, find.text('▦ WEEK')));
  await settle(tester);
}

Future<void> _toggleToMonth(WidgetTester tester) async {
  await tester.tap(inScreen(ReportsScreen, find.text('▣ MONTH')));
  await settle(tester);
}

/// The label the month selector renders for the month containing [day].
String _monthLabel(DateTime day) {
  const names = [
    'January', 'February', 'March', 'April', 'May', 'June', //
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  final now = DateTime.now();
  if (day.year == now.year && day.month == now.month) return 'This month';
  return '${names[day.month - 1]} ${day.year}';
}

bool _holdsToday(({DateTime start, DateTime end}) range) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return !today.isBefore(range.start) && today.isBefore(range.end);
}

Future<void> _stepDayForward(WidgetTester tester, int times) async {
  for (var i = 0; i < times; i++) {
    await tester.tap(inScreen(ReportsScreen, find.text('›')));
    await settle(tester);
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadMonoFont();
  });

  testWidgets('the toggle switches between week and day mode', (tester) async {
    await bootApp(tester, viewport: _tallPhone);
    await openTab(tester, 'REPORTS');

    expect(inScreen(ReportsScreen, find.text('This week')), findsOneWidget);

    await _toggleToDay(tester);
    expect(inScreen(ReportsScreen, find.text('This week')), findsNothing);
    expect(inScreen(ReportsScreen, find.text('Today')), findsOneWidget);

    await _toggleToWeek(tester);
    expect(inScreen(ReportsScreen, find.text('Today')), findsNothing);
    expect(inScreen(ReportsScreen, find.text('This week')), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('day mode carries what is left of today, week mode does not', (tester) async {
    await bootApp(tester, viewport: _tallPhone);
    await openTab(tester, 'REPORTS');

    // The week has its own version of this question and nobody has asked it.
    expect(inScreen(ReportsScreen, find.text('left until midnight')), findsNothing);

    await _toggleToDay(tester);
    expect(inScreen(ReportsScreen, find.text('left until midnight')), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('a day with nothing tracked still says what is left of it', (tester) async {
    // The categories render in an if/else against an empty range, and the row
    // sits outside it deliberately: a day you have tracked nothing on is
    // precisely the day the question is worth answering.
    await bootApp(tester, viewport: _tallPhone);
    await openTab(tester, 'REPORTS');
    await _toggleToDay(tester);

    expect(inScreen(ReportsScreen, find.textContaining('nothing tracked')), findsOneWidget);
    expect(inScreen(ReportsScreen, find.text('left until midnight')), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('day mode starts on today and refuses to step into the future', (tester) async {
    await bootApp(tester, viewport: _tallPhone);
    await openTab(tester, 'REPORTS');
    await _toggleToDay(tester);

    expect(inScreen(ReportsScreen, find.text('Today')), findsOneWidget);

    // No day is later than today.
    await tester.tap(inScreen(ReportsScreen, find.text('›')));
    await settle(tester);
    expect(inScreen(ReportsScreen, find.text('Today')), findsOneWidget);

    await tester.tap(inScreen(ReportsScreen, find.text('‹')));
    await settle(tester);
    expect(inScreen(ReportsScreen, find.text('Yesterday')), findsOneWidget);

    await tester.tap(inScreen(ReportsScreen, find.text('›')));
    await settle(tester);
    expect(inScreen(ReportsScreen, find.text('Today')), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('day mode re-scopes the categories to a single day', (tester) async {
    await _openLastWeek(tester);
    // The week: all of its Work against 3h of Break.
    expect(inScreen(ReportsScreen, find.text(_lastWeekWork)), findsOneWidget);

    await _toggleToDay(tester);
    // Landed on last week's Monday — the week being viewed, carried across —
    // which the seed left untracked.
    final monday = _lastWeek(DateTime.monday);
    expect(inScreen(ReportsScreen, find.text(_dayLabel(monday))), findsOneWidget);
    expect(
      inScreen(ReportsScreen, find.text('nothing tracked on ${_dayLabel(monday)}')),
      findsOneWidget,
    );

    await _stepDayForward(tester, 5); // Monday + 5 = Saturday
    final saturday = _lastWeek(DateTime.saturday);
    expect(inScreen(ReportsScreen, find.text(_dayLabel(saturday))), findsOneWidget);
    // Saturday alone: two hours each of Work and Break.
    expect(inScreen(ReportsScreen, find.text('2h 00m')), findsNWidgets(2));
    expect(inScreen(ReportsScreen, find.text(_lastWeekWork)), findsNothing);

    await disposeApp(tester);
  });

  testWidgets('context carries across the toggle in both directions', (tester) async {
    await _openLastWeek(tester); // week mode, last week

    await _toggleToDay(tester);
    // week -> day: lands on the viewed week's first day, since last week does
    // not hold today.
    final monday = _lastWeek(DateTime.monday);
    expect(inScreen(ReportsScreen, find.text(_dayLabel(monday))), findsOneWidget);

    await _toggleToWeek(tester);
    // day -> week: shows the week the selected day belongs to — last week
    // again, not a jump back to "this week".
    expect(inScreen(ReportsScreen, find.text('This week')), findsNothing);
    expect(inScreen(ReportsScreen, find.text(_weekLabel(monday))), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('month mode starts on this month and refuses to step into the future', (
    tester,
  ) async {
    await bootApp(tester, viewport: _tallPhone);
    await openTab(tester, 'REPORTS');
    await _toggleToMonth(tester);

    expect(inScreen(ReportsScreen, find.text('This month')), findsOneWidget);
    expect(inScreen(ReportsScreen, find.text('left until midnight')), findsNothing);

    await tester.tap(inScreen(ReportsScreen, find.text('›')));
    await settle(tester);
    expect(inScreen(ReportsScreen, find.text('This month')), findsOneWidget);

    await tester.tap(inScreen(ReportsScreen, find.text('‹')));
    await settle(tester);
    final now = DateTime.now();
    expect(
      inScreen(ReportsScreen, find.text(_monthLabel(DateTime(now.year, now.month - 1)))),
      findsOneWidget,
    );

    await tester.tap(inScreen(ReportsScreen, find.text('›')));
    await settle(tester);
    expect(inScreen(ReportsScreen, find.text('This month')), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('a past week opens the month of its Monday', (tester) async {
    await _openLastWeek(tester);

    await _toggleToMonth(tester);
    final monday = _lastWeek(DateTime.monday);
    expect(inScreen(ReportsScreen, find.text(_monthLabel(monday))), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('leaving month mode lands on today, or on the month\'s first week and day', (
    tester,
  ) async {
    await _openLastWeek(tester);
    await _toggleToMonth(tester);
    final month = localMonthRange(_lastWeek(DateTime.monday));
    final holdsToday = _holdsToday(month);

    await _toggleToWeek(tester);
    expect(
      inScreen(ReportsScreen, find.text(holdsToday ? 'This week' : _weekLabel(month.start))),
      findsOneWidget,
    );

    await _toggleToMonth(tester);
    await _toggleToDay(tester);
    expect(
      inScreen(ReportsScreen, find.text(holdsToday ? 'Today' : _dayLabel(month.start))),
      findsOneWidget,
    );

    await _toggleToMonth(tester);
    expect(inScreen(ReportsScreen, find.text(_monthLabel(month.start))), findsOneWidget);

    await disposeApp(tester);
  });
}
