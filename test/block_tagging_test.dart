// Tagging acts on the activity rows, not through a verb menu.
//
// The old sheet offered change / tag / untag, and each opened a *second* sheet
// asking which activity it applied to — a question already answered in the
// user's head, about a list they could not see while answering. Every row now
// carries its own swap and remove, so the question is not asked.
//
// The behaviour worth pinning hardest is the last row's remove: it does not
// refuse, the block becomes unnamed. That is what the catch-all is for.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/data/drift_repositories.dart';
import 'package:time_tracker/domain/unsorted.dart';
import 'package:time_tracker/phone/screens/timeline_screen.dart';

import 'support/flow_harness.dart';

const _phone = Size(400, 880);

Future<void> _seed(AppDatabase db) async {
  final activities = DriftActivityRepository(db);
  final changes = DriftChangeRepository(db);
  final a = await activities.createActivity(name: 'Alpha', color: '#4F8FEE');
  await activities.createActivity(name: 'Beta', color: '#EE7C4F');
  await changes.switchTo(a.syncId, at: DateTime.now().subtract(const Duration(hours: 1)));
}

Future<List<String>> _currentSet(AppDatabase db) async {
  final changes = DriftChangeRepository(db);
  final current = await changes.currentChange();
  final ids = await changes.activityIdsForChange(current!.syncId);
  final all = await DriftActivityRepository(db).loadActivities();
  return [for (final id in ids) all.firstWhere((a) => a.syncId == id).name]..sort();
}

/// The × on the row naming [activity].
///
/// Every Row ancestor of that name is considered, not just the nearest: the
/// timeline card behind the sheet carries the same name and comes first in tree
/// order. Only the sheet's row has a × inside it, so the descendant search picks
/// it out without depending on which Row happens to be found first.
Finder _removeOn(String activity) => find.descendant(
  of: find.ancestor(of: find.text(activity), matching: find.byType(Row)),
  matching: find.text('×'),
);

Future<void> _openBlockSheet(WidgetTester tester) async {
  await openTab(tester, 'TIMELINE');
  await tester.tap(_card('Alpha'));
  await settle(tester);
}

/// The timeline card naming [label]. Run just after midnight, the seeded block
/// began yesterday and the timeline draws it on both days, so there are two.
Finder _card(String label) => inScreen(TimelineScreen, find.text(label)).first;

void main() {
  testWidgets('removing the only activity leaves an unnamed block', (tester) async {
    final db = await bootApp(tester, viewport: _phone, seed: _seed);
    await _openBlockSheet(tester);

    await tester.tap(_removeOn('Alpha'));
    await settle(tester);

    // Not refused, and not an empty set: the catch-all is what a block whose
    // activity is not decided points at. "Something is always tracking" still
    // holds, because Unnamed is something.
    expect(await _currentSet(db), [kUnsortedName]);
    // And no new boundary — saying "it was not that" is a correction, not a
    // switch.
    expect(await DriftChangeRepository(db).loadChanges(), hasLength(1));

    await disposeApp(tester);
  });

  testWidgets('an unnamed block can be named again from the same sheet', (tester) async {
    // The round trip: remove the last tag, then answer it. If this did not work
    // the previous test would have described a trap rather than a feature.
    final db = await bootApp(tester, viewport: _phone, seed: _seed);
    await _openBlockSheet(tester);
    await tester.tap(_removeOn('Alpha'));
    await settle(tester);

    await tester.tap(_card(kUnsortedName));
    await settle(tester);
    await tester.tap(find.text('▸ WHAT WAS THIS?'));
    await settle(tester);
    await tester.tap(find.text('Beta').last);
    await settle(tester);

    // Replaced, not joined: "Unnamed + Beta" would read as forgot-to-switch and
    // halve the attribution.
    expect(await _currentSet(db), ['Beta']);

    await disposeApp(tester);
  });

  testWidgets('a row swaps itself without asking which', (tester) async {
    final db = await bootApp(tester, viewport: _phone, seed: _seed);
    await _openBlockSheet(tester);

    await tester.tap(find.text('SWAP'));
    await settle(tester);
    await tester.tap(find.text('Beta').last);
    await settle(tester);

    expect(await _currentSet(db), ['Beta']);
    expect(await DriftChangeRepository(db).loadChanges(), hasLength(1));

    await disposeApp(tester);
  });

  testWidgets('one row of a tagged pair is removed without a picker', (tester) async {
    final db = await bootApp(tester, viewport: _phone, seed: _seed);
    await _openBlockSheet(tester);
    await tester.tap(find.text('+ ANOTHER ACTIVITY'));
    await settle(tester);
    await tester.tap(find.text('Beta').last);
    await settle(tester);
    expect(await _currentSet(db), ['Alpha', 'Beta']);

    await tester.tap(_card('Alpha  +  Beta'));
    await settle(tester);
    await tester.tap(_removeOn('Alpha'));
    await settle(tester);

    // Alpha went because Alpha's row was tapped. The old flow would have opened
    // a picker here to ask the question the tap already answered.
    expect(await _currentSet(db), ['Beta']);

    await disposeApp(tester);
  });

  testWidgets('the add row cannot offer what is already on the block', (tester) async {
    final db = await bootApp(tester, viewport: _phone, seed: _seed);
    await _openBlockSheet(tester);

    await tester.tap(find.text('+ ANOTHER ACTIVITY'));
    await settle(tester);

    // Alpha is on the block, so tagging it again would be a no-op offered as a
    // choice. Beta is the only real option.
    //
    // Alpha is not gone: the block sheet has closed but the timeline cards
    // behind still name it. What matters is that the picker contributes none.
    final timelineAlphas = inScreen(TimelineScreen, find.text('Alpha')).evaluate().length;
    expect(find.text('Beta'), findsWidgets);
    expect(find.text('Alpha'), findsNWidgets(timelineAlphas));
    // Making one on the spot is offered here too — the old picker could not,
    // so tagging something new meant leaving for the activity list first.
    expect(find.text('+ NEW ACTIVITY'), findsOneWidget);

    await tester.tap(find.text('Beta').last);
    await settle(tester);
    expect(await _currentSet(db), ['Alpha', 'Beta']);

    await disposeApp(tester);
  });
}
