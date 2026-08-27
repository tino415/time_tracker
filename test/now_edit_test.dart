// Widget-level tests of the edits the Now screen makes to the block it is
// showing: retiming its start, and changing / tagging / untagging its
// activities.
//
// The point of every assertion here is that these are edits to *one* block, not
// switches: the change count must stay at one, because a new boundary would
// split the running block and charge the correction to a new stretch of time.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/data/drift_repositories.dart';
import 'package:time_tracker/format.dart';
import 'package:time_tracker/phone/screens/activities_screen.dart';
import 'package:time_tracker/phone/screens/now_screen.dart';

import 'support/flow_harness.dart';

const _phone = Size(400, 880);

/// One activity, tracking since [start]. Seeded relative to the real clock
/// rather than at a fixed hour: the boundary may never land in the future, and
/// "two hours ago" is in the past whenever the suite runs.
Future<void> _seedRunning(AppDatabase db, DateTime start) async {
  final activities = DriftActivityRepository(db);
  final a = await activities.createActivity(name: 'Deep work', color: '#4F8FEE');
  await DriftChangeRepository(db).switchTo(a.syncId, at: start);
}

Future<List<ActivityChange>> _changes(AppDatabase db) => DriftChangeRepository(db).loadChanges();

/// Create a second activity from the Activities tab, without switching to it,
/// and come back to Now.
Future<void> _addSpareActivity(WidgetTester tester, String name) async {
  await openTab(tester, 'ACTIVITIES');
  await tester.tap(inScreen(ActivitiesScreen, find.text('+ NEW ACTIVITY')));
  await settle(tester);
  await fillEditor(tester, name, confirm: 'CREATE');
  await openTab(tester, 'NOW');
}

void main() {
  testWidgets('nudging the start from the hero retimes the block in place', (tester) async {
    final start = DateTime.now().subtract(const Duration(hours: 2));
    final db = await bootApp(tester, viewport: _phone, seed: (db) => _seedRunning(db, start));

    final before = (await _changes(db)).single.changedAt;
    expect(inScreen(NowScreen, find.text('since ${formatTimeOfDay(before)}')), findsOneWidget);

    await tester.tap(inScreen(NowScreen, find.textContaining('since ')));
    await settle(tester);
    await tester.tap(find.text('-15'));
    await settle(tester);
    await tester.tap(find.text('SAVE'));
    await settle(tester);

    final after = (await _changes(db)).single.changedAt;
    expect(before.difference(after), const Duration(minutes: 15));
    expect(inScreen(NowScreen, find.text('since ${formatTimeOfDay(after)}')), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('a typed time sets the start absolutely', (tester) async {
    final start = DateTime.now().subtract(const Duration(hours: 4));
    final db = await bootApp(tester, viewport: _phone, seed: (db) => _seedRunning(db, start));

    // Two hours before the block opened is comfortably in the past, so the
    // clamp cannot interfere with what is being asserted.
    final target = start.subtract(const Duration(hours: 2));

    await tester.tap(inScreen(NowScreen, find.textContaining('since ')));
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, formatTimeOfDay(target));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    await tester.tap(find.text('SAVE'));
    await settle(tester);

    final after = (await _changes(db)).single.changedAt;
    expect(formatTimeOfDay(after), formatTimeOfDay(target));
    expect(await _changes(db), hasLength(1));

    await disposeApp(tester);
  });

  testWidgets('the start cannot be nudged past the present', (tester) async {
    final start = DateTime.now().subtract(const Duration(minutes: 3));
    final db = await bootApp(tester, viewport: _phone, seed: (db) => _seedRunning(db, start));

    final before = (await _changes(db)).single.changedAt;

    await tester.tap(inScreen(NowScreen, find.textContaining('since ')));
    await settle(tester);
    // Three quarters of an hour into the future, in +15 steps.
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('+15'));
      await settle(tester);
    }
    await tester.tap(find.text('SAVE'));
    await settle(tester);

    final after = (await _changes(db)).single.changedAt;
    expect(after.isAfter(DateTime.now()), isFalse, reason: 'a block may not start in the future');
    expect(
      after.isBefore(before),
      isFalse,
      reason: 'the clamp holds the boundary at the ceiling, it does not rewind it',
    );

    await disposeApp(tester);
  });

  testWidgets('changing the activity re-points the block instead of switching', (tester) async {
    final start = DateTime.now().subtract(const Duration(hours: 1));
    final db = await bootApp(tester, viewport: _phone, seed: (db) => _seedRunning(db, start));
    await _addSpareActivity(tester, 'Email');

    final before = (await _changes(db)).single.changedAt;

    await tester.tap(inScreen(NowScreen, find.text('⋯ EDIT BLOCK')));
    await settle(tester);
    // The row's own swap, not a "change activity" verb that then asks which —
    // on a single-activity block those are the same operation, and the row is
    // the one that does not have to ask.
    await tester.tap(find.text('SWAP'));
    await settle(tester);
    await tester.tap(find.text('Email').last); // the picker row
    await settle(tester);

    expect(inScreen(NowScreen, find.text('Email')), findsWidgets);
    expect(inScreen(NowScreen, find.text('Deep work')), findsNothing);

    final changes = await _changes(db);
    expect(changes, hasLength(1), reason: 'a correction is not a new boundary');
    expect(changes.single.changedAt, before, reason: 'the block keeps its start');

    await disposeApp(tester);
  });

  testWidgets('an activity can be tagged onto and untagged from the running block', (tester) async {
    final start = DateTime.now().subtract(const Duration(hours: 1));
    final db = await bootApp(tester, viewport: _phone, seed: (db) => _seedRunning(db, start));
    await _addSpareActivity(tester, 'Email');

    await tester.tap(inScreen(NowScreen, find.text('⋯ EDIT BLOCK')));
    await settle(tester);
    await tester.tap(find.text('+ ANOTHER ACTIVITY'));
    await settle(tester);
    await tester.tap(find.text('Email').last);
    await settle(tester);

    expect(inScreen(NowScreen, find.text('2 activities · even-split')), findsOneWidget);

    await tester.tap(inScreen(NowScreen, find.text('⋯ EDIT BLOCK')));
    await settle(tester);
    // The × on Email's own row. No "remove which one?" step: the question the
    // old flow asked had already been answered by choosing this row.
    await tester.tap(
      find.descendant(
        of: find.ancestor(of: find.text('Email'), matching: find.byType(Row)).first,
        matching: find.text('×'),
      ),
    );
    await settle(tester);

    expect(inScreen(NowScreen, find.text('2 activities · even-split')), findsNothing);
    expect(inScreen(NowScreen, find.text('Deep work')), findsWidgets);
    expect(await _changes(db), hasLength(1));

    await disposeApp(tester);
  });

  testWidgets('an unnamed block keeps its naming action alongside the block menu', (tester) async {
    await bootApp(
      tester,
      viewport: _phone,
      seed: (db) async {
        await _seedRunning(db, DateTime.now().subtract(const Duration(minutes: 30)));
      },
    );

    // Start an unnamed block over the top of the seeded one.
    await tester.tap(inScreen(NowScreen, find.text('▶ START NOW · NAME IT LATER')));
    await settle(tester);

    expect(inScreen(NowScreen, find.text('▸ WHAT IS THIS?')), findsOneWidget);
    // The full menu is still one tap away, so tag/untag/retime are reachable
    // for a block that has not been named yet.
    expect(inScreen(NowScreen, find.text('⋯')), findsOneWidget);

    await disposeApp(tester);
  });
}
