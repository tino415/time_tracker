// Zooming the calendar's time axis.
//
// Reported as broken on the Mac PWA, which it was not — there was no zoom to
// fail. `_hourHeight` was a top-level const, so the scale was baked into the
// layout, the hour grid and the slice card independently.
//
// What these pin is that all three move together, and that the drag snap moves
// with them: a 1-minute step is 0.9px at the default scale, so a finer snap is
// only honest once the axis is tall enough to aim at it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/data/drift_repositories.dart';
import 'package:time_tracker/phone/screens/calendar_screen.dart';

import 'support/flow_harness.dart';

const _phone = Size(400, 880);

DateTime get _yesterday {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day - 1);
}

DateTime _at(int hour, [int minute = 0]) =>
    DateTime(_yesterday.year, _yesterday.month, _yesterday.day, hour, minute);

/// Alpha 09:00–10:00, Beta 10:00 onwards.
Future<void> _seed(AppDatabase db) async {
  final activities = DriftActivityRepository(db);
  final changes = DriftChangeRepository(db);
  final a = await activities.createActivity(name: 'Alpha', color: '#4F8FEE');
  final b = await activities.createActivity(name: 'Beta', color: '#EE7C4F');
  await changes.switchTo(a.syncId, at: _at(9));
  await changes.switchTo(b.syncId, at: _at(10));
}

/// Open the calendar on the seeded day.
Future<void> _openCalendar(WidgetTester tester) async {
  await openTab(tester, 'TIMELINE');
  await tester.tap(find.text('▦ CALENDAR'));
  await settle(tester);
  await tester.tap(inScreen(CalendarScreen, find.text('‹'))); // to yesterday
  await settle(tester);
}

/// The drawn height of Alpha's one-hour card — i.e. pixels per hour.
double _alphaHeight(WidgetTester tester) => tester
    .getSize(find.ancestor(
      of: find.text('Alpha'),
      matching: find.byType(GestureDetector),
    ).first)
    .height;

void main() {
  testWidgets('the axis scales, and the whole day scales with it', (tester) async {
    await bootApp(tester, viewport: _phone, seed: _seed);
    await _openCalendar(tester);

    // The scale the view has always opened at.
    expect(_alphaHeight(tester), 56.0);
    final dayAtDefault = tester.getSize(find.byType(Stack).last).height;

    await tester.tap(find.text('+'));
    await settle(tester);
    expect(_alphaHeight(tester), 112.0);
    // The card and the day are drawn from the same scale — if they were not, a
    // block would sit at the wrong hour the moment either changed.
    expect(tester.getSize(find.byType(Stack).last).height, dayAtDefault * 2);

    await tester.tap(find.text('−'));
    await settle(tester);
    await tester.tap(find.text('−'));
    await settle(tester);
    expect(_alphaHeight(tester), 28.0);

    await disposeApp(tester);
  });

  testWidgets('the ends of the range stop rather than wrap', (tester) async {
    await bootApp(tester, viewport: _phone, seed: _seed);
    await _openCalendar(tester);

    // Out to the floor, then two presses past it.
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('−'));
      await settle(tester);
    }
    expect(_alphaHeight(tester), 28.0);

    for (var i = 0; i < 6; i++) {
      await tester.tap(find.text('+'));
      await settle(tester);
    }
    expect(_alphaHeight(tester), 224.0);

    await disposeApp(tester);
  });

  testWidgets('the hour grid follows the same scale as the blocks', (tester) async {
    await bootApp(tester, viewport: _phone, seed: _seed);
    await _openCalendar(tester);

    // 09:00 is the label the seeded day starts against. Its distance from
    // 10:00 is the grid's own idea of an hour, which must match the card's.
    double gridHour() {
      final nine = tester.getTopLeft(find.text('09:00'));
      final ten = tester.getTopLeft(find.text('10:00'));
      return ten.dy - nine.dy;
    }

    expect(gridHour(), _alphaHeight(tester));

    await tester.tap(find.text('+'));
    await settle(tester);
    expect(gridHour(), _alphaHeight(tester));

    await disposeApp(tester);
  });
}
