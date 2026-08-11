// Widget-level test of the Reports drill-down: a root category opens into its
// sub-activities, and each row carries its whole subtree's time — which is how
// "how much did I work for Payout" gets answered when Payout is a middle node
// with concrete tasks under it.
//
// History is seeded in *last* week and the report stepped back to it. A fixed
// past week is always fully in the past and never straddles a week boundary, so
// the expected totals do not depend on when the suite runs.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/data/drift_repositories.dart';
import 'package:time_tracker/domain/reporting.dart';
import 'package:time_tracker/phone/screens/reports_screen.dart';
import 'package:time_tracker/theme/tokens.dart';

import 'support/flow_harness.dart';

const _phone = Size(400, 880);

/// Last Sunday at [hour]:[minute] — `DateTime` normalises the negative day.
DateTime _at(int hour, [int minute = 0]) {
  final week = localWeekRange(DateTime.now()).start;
  return DateTime(week.year, week.month, week.day - 1, hour, minute);
}

/// Work > {Payout > {CU-1, CU-2}, Time tracker}, plus a top-level Break.
///
/// One hour each on Payout itself, CU-1, CU-2 and Time tracker, so Work = 4h
/// and Payout = 3h with 1h of that direct.
///
/// Seeded at the very end of last week on purpose. Something is always
/// tracking, so the last change runs until the range ends — start on Sunday
/// evening and that tail is one hour of real work rather than four idle days
/// that would dwarf every bar.
Future<void> _seedLastWeek(AppDatabase db) async {
  final activities = DriftActivityRepository(db);
  final changes = DriftChangeRepository(db);

  final work = await activities.createActivity(name: 'Work', color: '#4F8FEE');
  final payout = await activities.createActivity(
      name: 'Payout', color: '#EE7C4F', parentId: work.syncId);
  final tracker = await activities.createActivity(
      name: 'Time tracker', color: '#4FEE8F', parentId: work.syncId);
  final cu1 = await activities.createActivity(
      name: 'CU-1 Refund webhook', color: '#EE7C4F', parentId: payout.syncId);
  final cu2 = await activities.createActivity(
      name: 'CU-2 Payout report', color: '#EE7C4F', parentId: payout.syncId);
  final brk = await activities.createActivity(name: 'Break', color: '#9A9B95');

  await changes.switchTo(brk.syncId, at: _at(19, 30));
  await changes.switchTo(payout.syncId, at: _at(20));
  await changes.switchTo(cu1.syncId, at: _at(21));
  await changes.switchTo(cu2.syncId, at: _at(22));
  await changes.switchTo(tracker.syncId, at: _at(23)); // runs to the week's end
}

/// Register the app's own mono face.
///
/// These rows are laid out from text widths, and the harness's fallback face is
/// wide enough that a realistic task name overflows one by a pixel or two — an
/// artefact of the stand-in font that says nothing about the screen. Read off
/// disk rather than through `rootBundle`: `flutter test` runs from the package
/// root.
Future<void> _loadMonoFont() async {
  final loader = FontLoader(kMonoFont);
  for (final weight in ['Regular', 'Bold', 'ExtraBold']) {
    final bytes = File('assets/fonts/JetBrainsMono-$weight.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadMonoFont();
  });

  testWidgets('a category drills down into its sub-activities', (tester) async {
    await bootApp(tester, viewport: _phone, seed: _seedLastWeek);
    await openTab(tester, 'REPORTS');
    await tester.tap(inScreen(ReportsScreen, find.text('‹'))); // last week
    await settle(tester);

    // Collapsed: roots only, each carrying its whole subtree's time.
    expect(inScreen(ReportsScreen, find.text('Work')), findsOneWidget);
    expect(inScreen(ReportsScreen, find.text('4h 00m')), findsOneWidget);
    expect(inScreen(ReportsScreen, find.text('Payout')), findsNothing);

    await tester.tap(inScreen(ReportsScreen, find.text('Work')));
    await settle(tester);

    expect(inScreen(ReportsScreen, find.text('Payout')), findsOneWidget);
    expect(inScreen(ReportsScreen, find.text('3h 00m')), findsOneWidget);
    expect(inScreen(ReportsScreen, find.text('Time tracker')), findsOneWidget);
    expect(inScreen(ReportsScreen, find.text('CU-1 Refund webhook')), findsNothing);

    await tester.tap(inScreen(ReportsScreen, find.text('Payout')));
    await settle(tester);

    expect(inScreen(ReportsScreen, find.text('CU-1 Refund webhook')), findsOneWidget);
    expect(inScreen(ReportsScreen, find.text('CU-2 Payout report')), findsOneWidget);
    // The hour booked on Payout itself, or the children would not add up to 3h.
    expect(inScreen(ReportsScreen, find.text('direct')), findsOneWidget);
    // Time tracker, direct, CU-1, CU-2.
    expect(inScreen(ReportsScreen, find.text('1h 00m')), findsNWidgets(4));

    // Collapsing puts it back.
    await tester.tap(inScreen(ReportsScreen, find.text('Work')));
    await settle(tester);
    expect(inScreen(ReportsScreen, find.text('Payout')), findsNothing);

    await disposeApp(tester);
  });

  testWidgets('a leaf category does not offer a drill-down', (tester) async {
    await bootApp(tester, viewport: _phone, seed: _seedLastWeek);
    await openTab(tester, 'REPORTS');
    await tester.tap(inScreen(ReportsScreen, find.text('‹')));
    await settle(tester);

    // Break has no children, so tapping it changes nothing.
    await tester.tap(inScreen(ReportsScreen, find.text('Break')));
    await settle(tester);
    expect(inScreen(ReportsScreen, find.text('Payout')), findsNothing);

    await disposeApp(tester);
  });

}

// A golden of the drilled-open report was tried and removed. It pinned what the
// finders cannot see — indent, bar widths, row order — and earned its keep once,
// showing that scaling each bar against its largest *sibling* made every equal
// child full-width and said nothing, which is why they scale against the parent
// instead. But the week selector renders a date range, so the image changes when
// the calendar does and the test would fail weekly rather than on a regression.
// Reintroducing it needs an injectable clock first.
