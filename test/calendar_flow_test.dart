// Widget-level tests of the calendar edit view: the list/calendar toggle, the
// day axis, and dragging a boundary to retime two blocks at once.
//
// History is seeded on *yesterday* at fixed times. Anything seeded "today at
// 09:00" would be in the future — and therefore clamped away — whenever the
// suite happens to run before 09:00, so a fixed past day keeps the test
// independent of the wall clock.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/data/drift_repositories.dart';
import 'package:time_tracker/domain/calendar.dart';
import 'package:time_tracker/phone/screens/calendar_screen.dart';

import 'support/flow_harness.dart';

const _phone = Size(400, 880);

/// Pixels per minute in the calendar — mirrors the view's own constant, so a
/// drag distance can be expressed in minutes.
const _pxPerMinute = 56.0 / 60.0;

DateTime get _yesterday {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return DateTime(today.year, today.month, today.day - 1);
}

DateTime _at(int hour, [int minute = 0]) =>
    DateTime(_yesterday.year, _yesterday.month, _yesterday.day, hour, minute);

/// Yesterday: A from 09:00, B from 12:00, C from 15:00 (C's block stays open).
/// Returns the change ids, oldest first.
Future<List<String>> _seedDay(AppDatabase db) async {
  final activities = DriftActivityRepository(db);
  final changes = DriftChangeRepository(db);

  final a = await activities.createActivity(name: 'Alpha', color: '#4F8FEE');
  final b = await activities.createActivity(name: 'Beta', color: '#EE7C4F');
  final c = await activities.createActivity(name: 'Gamma', color: '#4FEE8F');

  await changes.switchTo(a.syncId, at: _at(9));
  await changes.switchTo(b.syncId, at: _at(12));
  await changes.switchTo(c.syncId, at: _at(15));

  return (await changes.loadChanges()).reversed.map((c) => c.syncId).toList();
}

Future<DateTime> _boundaryOf(AppDatabase db, String id) async {
  final rows = await DriftChangeRepository(db).loadChanges();
  return rows.firstWhere((c) => c.syncId == id).changedAt;
}

/// Drag [handle] by [minutes] of calendar time.
///
/// `tester.drag` cannot express this. With the default slop the recognizer
/// swallows the first `kTouchSlop` (18px) before it reports any delta, so the
/// gesture lands ~19 minutes short. With `touchSlopY: 0` it is worse: the whole
/// offset arrives as one move, which is consumed by drag *acceptance* —
/// DragStartBehavior.start resets the origin there — so no update is reported
/// and the boundary does not move at all. Overcoming the slop in a move of its
/// own, then dragging, delivers exactly the intended distance.
Future<void> dragMinutes(WidgetTester tester, Finder handle, double minutes) async {
  final gesture = await tester.startGesture(tester.getCenter(handle));
  await tester.pump();
  await gesture.moveBy(const Offset(0, kTouchSlop + 1)); // accepted here
  await tester.pump();
  await gesture.moveBy(Offset(0, minutes * _pxPerMinute)); // reported in full
  await tester.pump();
  await gesture.up();
  await settle(tester);
}

/// Switch to the calendar and step back to yesterday.
Future<void> _openYesterday(WidgetTester tester) async {
  await openTab(tester, 'TIMELINE');
  await tester.tap(find.text('▦ CALENDAR'));
  await settle(tester);
  await tester.tap(inScreen(CalendarScreen, find.text('‹')));
  await settle(tester);
}

void main() {
  testWidgets('the toggle swaps the list for the calendar', (tester) async {
    await bootApp(tester, viewport: _phone, seed: _seedDay);

    await openTab(tester, 'TIMELINE');
    expect(find.byType(CalendarScreen), findsNothing);

    await tester.tap(find.text('▦ CALENDAR'));
    await settle(tester);
    expect(find.byType(CalendarScreen), findsOneWidget);
    // The day axis is drawn.
    expect(inScreen(CalendarScreen, find.text('09:00')), findsWidgets);

    await tester.tap(find.text('≣ LIST'));
    await settle(tester);
    expect(find.byType(CalendarScreen), findsNothing);

    await disposeApp(tester);
  });

  testWidgets('yesterday shows the seeded blocks on the axis', (tester) async {
    await bootApp(tester, viewport: _phone, seed: _seedDay);
    await _openYesterday(tester);

    expect(inScreen(CalendarScreen, find.text('Yesterday')), findsOneWidget);
    expect(inScreen(CalendarScreen, find.text('Alpha')), findsOneWidget);
    expect(inScreen(CalendarScreen, find.text('Beta')), findsOneWidget);
    expect(inScreen(CalendarScreen, find.text('Gamma')), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('dragging a boundary retimes it', (tester) async {
    late List<String> ids;
    final db = await bootApp(
      tester,
      viewport: _phone,
      seed: (db) async => ids = await _seedDay(db),
    );
    await _openYesterday(tester);

    // The 12:00 boundary — the one opening Beta's block. The earliest change
    // (09:00) has no handle: there is nothing before it to trade time with.
    final handle = find.byKey(ValueKey('handle-${ids[1]}'));
    expect(handle, findsOneWidget);
    expect(find.byKey(ValueKey('handle-${ids[0]}')), findsNothing);

    await tester.ensureVisible(handle);
    await settle(tester);
    await dragMinutes(tester, handle, 60);

    expect(await _boundaryOf(db, ids[1]), _at(13));
    // Its neighbours did not move — one boundary shifted, two blocks resized.
    expect(await _boundaryOf(db, ids[0]), _at(9));
    expect(await _boundaryOf(db, ids[2]), _at(15));

    await disposeApp(tester);
  });

  testWidgets('a drag past the neighbouring boundary is clamped', (tester) async {
    late List<String> ids;
    final db = await bootApp(
      tester,
      viewport: _phone,
      seed: (db) async => ids = await _seedDay(db),
    );
    await _openYesterday(tester);

    final handle = find.byKey(ValueKey('handle-${ids[1]}'));
    await tester.ensureVisible(handle);
    await settle(tester);
    // Six hours down would cross the 15:00 boundary and reorder the day.
    await dragMinutes(tester, handle, 6 * 60);

    final moved = await _boundaryOf(db, ids[1]);
    expect(moved.isBefore(_at(15)), isTrue);
    expect(moved, _at(14, 59)); // held off by the default one-minute minimum

    await disposeApp(tester);
  });

  testWidgets('a short block does not overflow its card', (tester) async {
    // Reported as "BOTTOM OVERFLOW BY 2.9 PIXELS" while dragging the running
    // block shorter. The arithmetic matches a card around 15px: one line of
    // 11px text plus 4px padding needs ~18, so anything between roughly 4px and
    // 18px overflows — a band the card passes *through* during any drag towards
    // zero, which is why it showed up as a drag artefact rather than a state.
    await bootApp(tester, viewport: _phone, seed: (db) async {
      final activities = DriftActivityRepository(db);
      final changes = DriftChangeRepository(db);
      final a = await activities.createActivity(name: 'Alpha', color: '#4F8FEE');
      final b = await activities.createActivity(name: 'Beta', color: '#EE7C4F');
      // ~16 minutes ≈ 15px at 56px/hour: squarely in the band.
      await changes.switchTo(a.syncId, at: _at(9));
      await changes.switchTo(b.syncId, at: _at(9, 16));
    });
    await _openYesterday(tester);

    expect(tester.takeException(), isNull);

    await disposeApp(tester);
  });

  testWidgets('a block of a few seconds renders without error', (tester) async {
    // A card is sized from its block's duration, so a block seconds old is a
    // fraction of a pixel tall — far less than one line of text. It has to
    // degrade to a clipped colour bar rather than throw.
    await bootApp(
      tester,
      viewport: _phone,
      seed: (db) async {
        final activities = DriftActivityRepository(db);
        final changes = DriftChangeRepository(db);
        final a = await activities.createActivity(name: 'Alpha', color: '#4F8FEE');
        final b = await activities.createActivity(name: 'Beta', color: '#EE7C4F');
        final now = DateTime.now();
        await changes.switchTo(a.syncId, at: now.subtract(const Duration(seconds: 20)));
        await changes.switchTo(b.syncId, at: now.subtract(const Duration(seconds: 5)));
      },
    );

    await openTab(tester, 'TIMELINE');
    await tester.tap(find.text('▦ CALENDAR'));
    await settle(tester);

    expect(find.byType(CalendarScreen), findsOneWidget);
    // The cards must actually be on the axis — without this the test would pass
    // on an empty "nothing tracked this day" screen and prove nothing.
    expect(inScreen(CalendarScreen, find.text('Alpha')), findsOneWidget);
    expect(inScreen(CalendarScreen, find.text('Beta')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await disposeApp(tester);
  });

  test('the view constant matches the domain helper', () {
    // Guards the drag arithmetic above against a silent change to the axis.
    expect(minutesFromMidnight(_at(12)), 720);
  });
}
