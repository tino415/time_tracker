// Widget-level smoke test of the phone MVP flow against an in-memory database:
// first run -> create an activity -> it tracks -> the timeline shows the block
// -> tagging a second activity onto it marks it as the forgot-to-switch case.
//
// The same flow runs on a real device in integration_test/flow_test.dart; the
// shared helpers live in test/support/flow_harness.dart.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/phone/screens/activities_screen.dart';
import 'package:time_tracker/phone/screens/now_screen.dart';
import 'package:time_tracker/phone/screens/timeline_screen.dart';

import 'support/flow_harness.dart';

// The default 800x600 test surface is landscape and would push the bottom
// sheets' actions off-screen.
const _phone = Size(400, 880);

void main() {
  testWidgets('first run offers activity creation and starts tracking it', (tester) async {
    await bootApp(tester, viewport: _phone);

    expect(inScreen(NowScreen, find.text('nothing tracked yet')), findsOneWidget);

    await tester.tap(inScreen(NowScreen, find.text('+ NEW ACTIVITY')));
    await settle(tester);
    await fillEditor(tester, 'Deep work', confirm: 'CREATE & SWITCH');

    // The hero now shows the running activity.
    expect(inScreen(NowScreen, find.text('TRACKING')), findsOneWidget);
    expect(inScreen(NowScreen, find.text('Deep work')), findsWidgets);

    await disposeApp(tester);
  });

  testWidgets('the running block appears on the timeline and can be tagged', (tester) async {
    await bootApp(tester, viewport: _phone);

    await tester.tap(inScreen(NowScreen, find.text('+ NEW ACTIVITY')));
    await settle(tester);
    await fillEditor(tester, 'Deep work', confirm: 'CREATE & SWITCH');

    // A second activity, created from the Activities tab (no switch).
    await openTab(tester, 'ACTIVITIES');
    await tester.tap(inScreen(ActivitiesScreen, find.text('+ NEW ACTIVITY')));
    await settle(tester);
    await fillEditor(tester, 'Email', confirm: 'CREATE');

    await openTab(tester, 'TIMELINE');
    // NeoChip uppercases its label, so the day header renders as "TODAY".
    expect(inScreen(TimelineScreen, find.text('TODAY')), findsOneWidget);
    expect(inScreen(TimelineScreen, find.text('● open')), findsOneWidget);

    // Tag the open block with the second activity (the forgot-to-switch case).
    await tester.tap(inScreen(TimelineScreen, find.text('Deep work')));
    await settle(tester);
    await tester.tap(find.text('+ ANOTHER ACTIVITY'));
    await settle(tester);
    await tester.tap(find.text('Email').last); // the picker row
    await settle(tester);

    expect(inScreen(TimelineScreen, find.text('Deep work  +  Email')), findsOneWidget);
    expect(inScreen(TimelineScreen, find.textContaining('forgot to switch')), findsOneWidget);

    await disposeApp(tester);
  });

  // The inverse of what this once asserted. Re-tapping used to be a no-op; it
  // now splits, because a note lives on the block and splitting is how the
  // second stretch of the same work gets its own. The accidental double-tap is
  // answered by the undo below rather than by refusing the tap.
  testWidgets('re-tapping the running activity splits the block, and offers to undo', (
    tester,
  ) async {
    final db = await bootApp(tester, viewport: _phone);

    await tester.tap(inScreen(NowScreen, find.text('+ NEW ACTIVITY')));
    await settle(tester);
    // Bookmark it so it lands in the quick-switch grid.
    await tester.enterText(editorNameField, 'Deep work');
    await tester.pump();
    await tester.tap(find.textContaining('bookmark (quick-switch'));
    await tester.pump();
    await tester.tap(find.text('CREATE & SWITCH'));
    await settle(tester);

    // Tap the grid tile for what is already running (the grid is last on screen).
    await tester.tap(inScreen(NowScreen, find.text('Deep work')).last);
    await settle(tester);

    expect(await _liveChanges(db), 2);

    // Not silent: the split is announced, which is what makes it safe to allow.
    expect(find.text('new block · same activity'), findsOneWidget);

    await tester.tap(find.text('UNDO'));
    await settle(tester);
    expect(await _liveChanges(db), 1);

    await disposeApp(tester);
  });

  testWidgets('switching to a different activity says nothing', (tester) async {
    // The undo is for the ambiguous case only. A real switch is self-evident —
    // the hero changes — so a prompt there would be noise on the common action.
    final db = await bootApp(tester, viewport: _phone);

    await tester.tap(inScreen(NowScreen, find.text('+ NEW ACTIVITY')));
    await settle(tester);
    await tester.enterText(editorNameField, 'Deep work');
    await tester.pump();
    await tester.tap(find.text('CREATE & SWITCH'));
    await settle(tester);

    // The second one from the Activities tab: once anything exists, the Now
    // screen shows the hero instead of the first-run "+ NEW ACTIVITY".
    await openTab(tester, 'ACTIVITIES');
    await tester.tap(inScreen(ActivitiesScreen, find.text('+ NEW ACTIVITY')));
    await settle(tester);
    await tester.enterText(editorNameField, 'Email');
    await tester.pump();
    await tester.tap(find.textContaining('bookmark (quick-switch'));
    await tester.pump();
    await tester.tap(find.text('CREATE'));
    await settle(tester);

    await openTab(tester, 'NOW');
    await tester.tap(inScreen(NowScreen, find.text('Email')).last);
    await settle(tester);

    expect(await _liveChanges(db), 2);
    expect(find.text('new block · same activity'), findsNothing);

    await disposeApp(tester);
  });
}

/// Boundaries that still exist.
///
/// `deleteChange` is a *soft* delete — it stamps `deletedAt` so the row can
/// still be pushed as a tombstone — so a raw count of the table includes blocks
/// that have been merged away, and would report an undo as having done nothing.
Future<int> _liveChanges(AppDatabase db) async {
  final rows = await db.select(db.activityChanges).get();
  return rows.where((c) => c.deletedAt == null).length;
}
