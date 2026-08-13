// The note dialog's width must not follow its text.
//
// This needs measuring at two text lengths, which is why the bug survived a
// suite that otherwise drives this dialog: every assertion about *behaviour*
// passed the whole time. The dialog saved the right note; it just grew a
// character at a time while you typed, instead of wrapping, until it hit the
// screen edge.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/data/drift_repositories.dart';
import 'package:time_tracker/phone/screens/timeline_screen.dart';

import 'support/flow_harness.dart';

const _phone = Size(400, 880);

Future<void> _seed(AppDatabase db) async {
  final activities = DriftActivityRepository(db);
  final changes = DriftChangeRepository(db);
  final a = await activities.createActivity(name: 'Alpha', color: '#4F8FEE');
  await changes.switchTo(a.syncId);
}

void main() {
  testWidgets('the note field keeps its width as the note grows', (tester) async {
    await bootApp(tester, viewport: _phone, seed: _seed);

    await openTab(tester, 'TIMELINE');
    await tester.tap(inScreen(TimelineScreen, find.text('Alpha')));
    await settle(tester);
    await tester.tap(find.text('✎ ADD A NOTE'));
    await settle(tester);

    final field = find.byType(TextField).last;
    final empty = tester.getSize(field).width;

    await tester.enterText(field, 'x');
    await settle(tester);
    final short = tester.getSize(field).width;

    // Past the point where the text alone would be wider than the dialog, so a
    // width that tracks the text has nowhere left to hide.
    await tester.enterText(field, 'x' * 120);
    await settle(tester);
    final long = tester.getSize(field).width;

    expect(short, empty, reason: 'one character must not resize the dialog');
    expect(long, empty, reason: 'a long note wraps instead of widening');

    await disposeApp(tester);
  });
}
