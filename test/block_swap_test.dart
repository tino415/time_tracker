// Trading labels with the block before, from the block sheet.
//
// The action's one real risk is being read as a reorder — names moving and the
// durations following them — so every test here checks the times as well as the
// names, and the button's own label is part of the contract.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/data/drift_repositories.dart';
import 'package:time_tracker/format.dart';
import 'package:time_tracker/phone/screens/timeline_screen.dart';

import 'support/flow_harness.dart';

const _phone = Size(400, 880);

/// Relative to now, like every other widget test here. Pinning absolute clock
/// times puts the boundaries in the future whenever the suite runs before them,
/// and an open block starting in the future has a negative duration.
final _earlier = DateTime.now().subtract(const Duration(hours: 2));
final _later = DateTime.now().subtract(const Duration(hours: 1));

/// Two blocks labelled the wrong way round: Deep work sits on the slot Email
/// ran in, and Email on Deep work's, which is what a switch made a moment late
/// leaves behind.
Future<void> _seed(AppDatabase db) async {
  final activities = DriftActivityRepository(db);
  final changes = DriftChangeRepository(db);

  final deep = await activities.createActivity(name: 'Deep work', color: '#4F8FEE');
  final email = await activities.createActivity(name: 'Email', color: '#EE7C4F');
  await changes.switchTo(deep.syncId, at: _earlier);
  await changes.switchTo(email.syncId, at: _later);
}

Future<List<String>> _namesOldestFirst(AppDatabase db) async {
  final changes = DriftChangeRepository(db);
  final activities = await DriftActivityRepository(db).loadActivities();
  final rows = (await changes.loadChanges()).reversed;
  final out = <String>[];
  for (final c in rows) {
    final ids = await changes.activityIdsForChange(c.syncId);
    out.add([for (final id in ids) activities.firstWhere((a) => a.syncId == id).name].join(' + '));
  }
  return out;
}

Future<List<DateTime>> _boundariesOldestFirst(AppDatabase db) async => [
  for (final c in (await DriftChangeRepository(db).loadChanges()).reversed) c.changedAt,
];

/// Open the sheet for the later block, the one that has a predecessor.
Future<void> _openLaterBlock(WidgetTester tester) async {
  await openTab(tester, 'TIMELINE');
  await tester.tap(inScreen(TimelineScreen, find.text('Email')));
  await settle(tester);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadMonoFont();
  });

  testWidgets('the row names the block it would trade with', (tester) async {
    await bootApp(tester, viewport: _phone, seed: _seed);
    await _openLaterBlock(tester);

    // Naming the neighbour is what makes the action checkable before tapping.
    // NeoButton uppercases its label. Asserted in parts rather than as one
    // string: two hours back can cross midnight, and the label then carries a
    // date as well, which is correct rather than a failure.
    final label = tester.widget<Text>(find.textContaining('TRADE LABELS WITH')).data!;
    expect(label, contains(formatTimeOfDay(_earlier)));
    expect(label, contains('DEEP WORK'));

    await disposeApp(tester);
  });

  testWidgets('trading moves the names and leaves the times', (tester) async {
    final db = await bootApp(tester, viewport: _phone, seed: _seed);
    final before = await _boundariesOldestFirst(db);
    await _openLaterBlock(tester);

    await tester.tap(find.textContaining('TRADE LABELS WITH'));
    await settle(tester);

    expect(await _namesOldestFirst(db), ['Email', 'Deep work']);
    expect(await _boundariesOldestFirst(db), before);

    await disposeApp(tester);
  });

  testWidgets('undo is the same action again', (tester) async {
    final db = await bootApp(tester, viewport: _phone, seed: _seed);
    await _openLaterBlock(tester);

    await tester.tap(find.textContaining('TRADE LABELS WITH'));
    await settle(tester);
    expect(find.text('labels swapped · times unchanged'), findsOneWidget);

    await tester.tap(find.text('UNDO'));
    await settle(tester);

    expect(await _namesOldestFirst(db), ['Deep work', 'Email']);

    await disposeApp(tester);
  });

  testWidgets('two blocks carrying the same label announce nothing', (tester) async {
    // A block split to give the second stretch its own note has the same
    // activity on both sides. Nothing is written, so there must be no snackbar
    // offering to undo an edit that did not happen.
    await bootApp(
      tester,
      viewport: _phone,
      seed: (db) async {
        final activities = DriftActivityRepository(db);
        final changes = DriftChangeRepository(db);
        final a = await activities.createActivity(name: 'Deep work', color: '#4F8FEE');
        await changes.switchTo(a.syncId, at: _earlier);
        await changes.switchTo(a.syncId, at: _later);
      },
    );
    await openTab(tester, 'TIMELINE');
    await tester.tap(inScreen(TimelineScreen, find.text('Deep work')).first);
    await settle(tester);

    await tester.tap(find.textContaining('TRADE LABELS WITH'));
    await settle(tester);

    expect(find.text('labels swapped · times unchanged'), findsNothing);

    await disposeApp(tester);
  });

  testWidgets('the earliest block is not offered the trade', (tester) async {
    await bootApp(tester, viewport: _phone, seed: _seed);
    await openTab(tester, 'TIMELINE');
    await tester.tap(inScreen(TimelineScreen, find.text('Deep work')));
    await settle(tester);

    // Nothing before it to trade with, and unlike merge this is decided from the
    // block list rather than from a flag the caller passes.
    expect(find.textContaining('TRADE LABELS WITH'), findsNothing);

    await disposeApp(tester);
  });
}
