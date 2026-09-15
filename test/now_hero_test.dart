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
import 'package:time_tracker/format.dart';
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
  for (final name in [
    'Work',
    'Infrastructure',
    'Deployment pipeline',
    'Staging',
    'CU-1042 Rotate the signing key',
  ]) {
    final a = await activities.createActivity(name: name, color: '#4F8FEE', parentId: parent);
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
        final a = await DriftActivityRepository(db).createActivity(name: 'Break', color: '#9A9B95');
        await DriftChangeRepository(db).switchTo(a.syncId);
      },
    );

    // A short path must not be truncated just because the chip can now shrink.
    expect(inScreen(NowScreen, find.text('Break')), findsWidgets);

    await disposeApp(tester);
  });

  testWidgets('the day-left number does not cost the clock its size', (tester) async {
    // Two numbers now share the clock row, on the narrowest screen this ships
    // to. The elapsed clock is the reason anyone looks at this card, so the
    // second one has to fit in what it leaves rather than take from it.
    //
    // Assert the painted width, not the style: the clock sits in a FittedBox,
    // whose scale never touches the TextStyle, so reading `fontSize` back would
    // report 40 however small the glyphs actually are. An upper bound is no use
    // either — a FittedBox child cannot exceed its box by construction. Only a
    // lower bound can fail, and it fails exactly when a growing neighbour
    // squeezes the clock.
    await bootApp(tester, viewport: _narrow, seed: _seedDeepPath);

    expect(inScreen(NowScreen, find.text('to midnight')), findsOneWidget);

    // 0:00:00 is seven characters of 40pt mono at a 0.6em advance, so an
    // unscaled clock paints about 168dp wide.
    final clock = inScreen(NowScreen, find.textContaining(RegExp(r'^\d+:\d\d:\d\d$')));
    expect(tester.getRect(clock).width, greaterThan(160));

    await disposeApp(tester);
  });

  testWidgets('a weekend-old block counts today, and the since-row carries the day', (
    tester,
  ) async {
    // The clock answers "how long today": a block started 30 hours ago must
    // not print 30:xx:xx. What still says the block is older than it counts is
    // the since-row, which grows a weekday once the start is not today.
    final start = DateTime.now().subtract(const Duration(hours: 30));
    await bootApp(
      tester,
      viewport: _narrow,
      seed: (db) async {
        final a = await DriftActivityRepository(db).createActivity(name: 'Sleep', color: '#9A9B95');
        await DriftChangeRepository(db).switchTo(a.syncId, at: start);
      },
    );

    final clock = inScreen(NowScreen, find.textContaining(RegExp(r'^\d+:\d\d:\d\d$')));
    final hours = int.parse((tester.widget<Text>(clock).data!).split(':').first);
    expect(hours, lessThan(24));

    expect(
      inScreen(NowScreen, find.text('since ${formatTimestamp(start, DateTime.now())}')),
      findsOneWidget,
    );

    await disposeApp(tester);
  });

  testWidgets('a hero with nothing running still says what is left of today', (tester) async {
    // The not-tracking branch has no clock of its own, so it needed its own
    // ticker. The question does not depend on anything running, and this is
    // exactly the moment it is worth asking.
    //
    // An activity that was never started, rather than an empty database: with no
    // activities at all the screen is the first-run pane and there is no hero.
    await bootApp(
      tester,
      viewport: _narrow,
      seed: (db) async {
        await DriftActivityRepository(db).createActivity(name: 'Break', color: '#9A9B95');
      },
    );

    // NeoChip uppercases its label.
    expect(inScreen(NowScreen, find.text('NOT TRACKING')), findsOneWidget);
    expect(inScreen(NowScreen, find.text('to midnight')), findsOneWidget);

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
