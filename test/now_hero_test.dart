// The Now hero's breadcrumb row, at widths where it used to overflow.
//
// The hero is the one place a full activity path is rendered on a single line
// next to fixed-width chrome, so it is the one place a deep tree pushes past a
// border. An overflow throws in the harness, which makes "render it narrow with
// a deep path" the whole assertion — but only with the real mono face loaded,
// since the harness fallback has different metrics.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/data/drift_repositories.dart';
import 'package:time_tracker/phone/screens/now_screen.dart';

import 'support/flow_harness.dart';

/// Narrower than any phone this ships to — the point is to leave the breadcrumb
/// no room at all, so a chip that cannot shrink is guaranteed to overflow.
const _narrow = Size(320, 720);

/// A five-level path, tracking the leaf: the shape that overflowed.
Future<void> _seedDeepPath(AppDatabase db) async {
  final activities = DriftActivityRepository(db);
  final changes = DriftChangeRepository(db);

  String? parent;
  for (final name in ['Work', 'Infrastructure', 'Deployment pipeline', 'Staging', 'CU-1042 Rotate the signing key']) {
    final a = await activities.createActivity(
      name: name,
      color: '#4F8FEE',
      parentId: parent,
    );
    parent = a.syncId;
  }
  await changes.switchTo(parent!);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadMonoFont();
  });

  testWidgets('a deep activity path does not overflow the hero', (tester) async {
    await bootApp(tester, viewport: _narrow, seed: _seedDeepPath);

    // The hero is showing this block. The leaf is not checked on the breadcrumb
    // — it is the headline below, which is where the truncated chip hands the
    // question off.
    expect(inScreen(NowScreen, find.text('TRACKING')), findsOneWidget);
    expect(inScreen(NowScreen, find.text('CU-1042 Rotate the signing key')), findsWidgets);

    await disposeApp(tester);
  });

  testWidgets('a top-level activity still shows its whole name', (tester) async {
    await bootApp(
      tester,
      viewport: _narrow,
      seed: (db) async {
        final a = await DriftActivityRepository(db)
            .createActivity(name: 'Break', color: '#9A9B95');
        await DriftChangeRepository(db).switchTo(a.syncId);
      },
    );

    // A short path must not be truncated just because the chip can now shrink.
    expect(inScreen(NowScreen, find.text('Break')), findsWidgets);

    await disposeApp(tester);
  });

}

// A golden of this hero was tried and removed. Where the breadcrumb gets cut is
// a visual property no finder can see — but the hero also renders "since HH:MM"
// off the wall clock, so the image changes every minute and the test fails on a
// schedule rather than on a regression. It earned its keep once, catching a
// head-truncation attempt that rendered "…Work / Infrastructure" — an ellipsis
// beside text that had not been cut — and that finding is recorded where the
// code makes the choice. Reintroducing it needs an injectable clock first.
