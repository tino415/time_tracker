// Splitting a block from the timeline *list*.
//
// This route did not exist: split was offered only when the caller passed a
// position, which meant the calendar alone. The calendar draws a minute as
// 0.93px, so for a day of three- and five-minute blocks the action was behind a
// gesture that could not be made — documented as available, in practice
// unreachable. The point of these tests is the list route and the typed time.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/data/drift_repositories.dart';
import 'package:time_tracker/phone/screens/timeline_screen.dart';

import 'support/flow_harness.dart';

const _phone = Size(400, 880);

DateTime get _yesterday {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day - 1);
}

DateTime _at(int hour, [int minute = 0]) =>
    DateTime(_yesterday.year, _yesterday.month, _yesterday.day, hour, minute);

/// Alpha 09:00–10:00, then Beta open from 10:00.
Future<void> _seed(AppDatabase db) async {
  final activities = DriftActivityRepository(db);
  final changes = DriftChangeRepository(db);
  final a = await activities.createActivity(name: 'Alpha', color: '#4F8FEE');
  final b = await activities.createActivity(name: 'Beta', color: '#EE7C4F');
  await changes.switchTo(a.syncId, at: _at(9));
  await changes.switchTo(b.syncId, at: _at(10));
}

/// A short day: five minutes, then three. Both are legal to split and both are
/// under five pixels tall on the calendar.
Future<void> _seedShort(AppDatabase db) async {
  final activities = DriftActivityRepository(db);
  final changes = DriftChangeRepository(db);
  final a = await activities.createActivity(name: 'Alpha', color: '#4F8FEE');
  final b = await activities.createActivity(name: 'Beta', color: '#EE7C4F');
  await changes.switchTo(a.syncId, at: _at(9));
  await changes.switchTo(b.syncId, at: _at(9, 5));
}

Future<List<DateTime>> _boundaries(AppDatabase db) async {
  final rows = await DriftChangeRepository(db).loadChanges();
  return rows.reversed.map((c) => c.changedAt).toList();
}

void main() {
  testWidgets('splits from the timeline list at a typed time', (tester) async {
    final db = await bootApp(tester, viewport: _phone, seed: _seed);

    await openTab(tester, 'TIMELINE');
    await tester.tap(inScreen(TimelineScreen, find.text('Alpha')));
    await settle(tester);

    await tester.tap(find.text('✂ SPLIT AT…'));
    await settle(tester);

    // The midpoint is only the opening guess — 09:30 for a 09:00–10:00 block.
    expect(find.text('09:30'), findsOneWidget);

    // Typed, not dragged. This is the whole reason the sheet exists: the
    // calendar snaps boundary drags to five minutes, which is longer than some
    // of these blocks.
    await tester.enterText(find.byType(TextField).last, '09:12');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(find.text('09:12'), findsOneWidget);

    await tester.tap(find.text('SPLIT HERE'));
    await settle(tester);

    // Then what the second half was.
    await tester.tap(find.text('Beta').last);
    await settle(tester);

    expect(await _boundaries(db), [_at(9), _at(9, 12), _at(10)]);

    await disposeApp(tester);
  });

  testWidgets('offers the split on a five-minute block', (tester) async {
    // 4.7px tall on the calendar, and its boundary cannot be nudged there at
    // all — the drag snap is five minutes. The list is the only way in.
    final db = await bootApp(tester, viewport: _phone, seed: _seedShort);

    await openTab(tester, 'TIMELINE');
    await tester.tap(inScreen(TimelineScreen, find.text('Alpha')));
    await settle(tester);

    expect(find.text('✂ SPLIT AT…'), findsOneWidget);
    await tester.tap(find.text('✂ SPLIT AT…'));
    await settle(tester);

    // Minute resolution, so a five-minute block still has somewhere to cut.
    expect(find.text('09:02'), findsOneWidget);
    await tester.tap(find.text('SPLIT HERE'));
    await settle(tester);
    await tester.tap(find.text('Beta').last);
    await settle(tester);

    expect(await _boundaries(db), [_at(9), _at(9, 2), _at(9, 5)]);

    await disposeApp(tester);
  });

  testWidgets('refuses a block with no room for two halves', (tester) async {
    await bootApp(
      tester,
      viewport: _phone,
      seed: (db) async {
        final activities = DriftActivityRepository(db);
        final changes = DriftChangeRepository(db);
        final a = await activities.createActivity(name: 'Alpha', color: '#4F8FEE');
        final b = await activities.createActivity(name: 'Beta', color: '#EE7C4F');
        await changes.switchTo(a.syncId, at: _at(9));
        // 90 seconds: splitting would leave a half shorter than the minute the
        // controller insists on, so the action must not be offered at all rather
        // than being offered and silently doing nothing.
        await changes.switchTo(b.syncId, at: _at(9).add(const Duration(seconds: 90)));
      },
    );

    await openTab(tester, 'TIMELINE');
    await tester.tap(inScreen(TimelineScreen, find.text('Alpha')));
    await settle(tester);

    expect(find.text('✂ SPLIT AT…'), findsNothing);

    await disposeApp(tester);
  });
}
