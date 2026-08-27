// "Track this again" — resuming from the timeline.
//
// Resuming used to mean reading a block off the timeline, going to Now, and
// finding the same thing again in the grid or the search field, with the thing
// you wanted already on screen under your thumb.
//
// The property worth guarding is that this is *not* an edit. Every other gesture
// on a timeline row changes the row under the finger; this one leaves history
// alone and writes at the present.

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

/// Alpha 09:00–10:00, Beta open from 10:00.
Future<void> _seed(AppDatabase db) async {
  final activities = DriftActivityRepository(db);
  final changes = DriftChangeRepository(db);
  final a = await activities.createActivity(name: 'Alpha', color: '#4F8FEE');
  final b = await activities.createActivity(name: 'Beta', color: '#EE7C4F');
  await changes.switchTo(a.syncId, at: _at(9));
  await changes.switchTo(b.syncId, at: _at(10));
}

/// Boundaries, oldest first.
Future<List<DateTime>> _boundaries(AppDatabase db) async {
  final rows = await DriftChangeRepository(db).loadChanges();
  return rows.reversed.map((c) => c.changedAt).toList();
}

Future<List<String>> _currentActivityNames(AppDatabase db) async {
  final changes = DriftChangeRepository(db);
  final current = await changes.currentChange();
  final ids = await changes.activityIdsForChange(current!.syncId);
  final all = await DriftActivityRepository(db).loadActivities();
  return [for (final id in ids) all.firstWhere((a) => a.syncId == id).name]..sort();
}

void main() {
  testWidgets('the row button starts the old activity now', (tester) async {
    // The glyph carries no text a screen reader — or the browser suite — can
    // use, so the label is the affordance's only name. Enabling semantics here
    // asserts it exists rather than trusting it.
    final semantics = tester.ensureSemantics();
    final db = await bootApp(tester, viewport: _phone, seed: _seed);

    await openTab(tester, 'TIMELINE');
    // Alpha's row — the finished block, not the open one.
    // Exactly the label, with nothing else folded in — the glyph is excluded
    // from semantics so the node does not read "track again ▶".
    expect(find.bySemanticsLabel('track again'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('track again'));
    await settle(tester);
    semantics.dispose();

    expect(await _currentActivityNames(db), ['Alpha']);

    // History is untouched: the two old boundaries are still where they were,
    // and the new one is a third. Resuming yesterday must not extend yesterday.
    final boundaries = await _boundaries(db);
    expect(boundaries.take(2), [_at(9), _at(10)]);
    expect(boundaries, hasLength(3));
    expect(boundaries.last.isAfter(_at(10)), isTrue);

    await disposeApp(tester);
  });

  testWidgets('the open block offers no resume', (tester) async {
    // Nothing to resume — it is already running. The slot is absent rather than
    // disabled, so the row does not carry a control that never does anything.
    final semantics = tester.ensureSemantics();
    await bootApp(tester, viewport: _phone, seed: _seed);
    await openTab(tester, 'TIMELINE');

    // Two blocks, one of them open — so exactly one row offers a resume.
    expect(inScreen(TimelineScreen, find.text('Beta')), findsWidgets);
    expect(find.bySemanticsLabel('track again'), findsOneWidget);

    semantics.dispose();
    await disposeApp(tester);
  });

  testWidgets('the sheet offers it too, and resumes a whole tagged set', (tester) async {
    final db = await bootApp(tester, viewport: _phone, seed: _seed);

    await openTab(tester, 'TIMELINE');
    // Tag Alpha's block with Beta — the "forgot to switch" case.
    await tester.tap(inScreen(TimelineScreen, find.text('Alpha')));
    await settle(tester);
    await tester.tap(find.text('+ ANOTHER ACTIVITY'));
    await settle(tester);
    await tester.tap(find.text('Beta').last);
    await settle(tester);

    await tester.tap(inScreen(TimelineScreen, find.text('Alpha  +  Beta')));
    await settle(tester);
    await tester.tap(find.text('▶ TRACK THIS AGAIN'));
    await settle(tester);

    // The whole set, not a question about which half. The pair is one thing
    // that happened; untagging afterwards is the escape hatch.
    expect(await _currentActivityNames(db), ['Alpha', 'Beta']);

    await disposeApp(tester);
  });
}
