// The Now screen has one region that grows and a strip of chrome that does not.
//
// It used to have the growing part *below* the fixed part: the field carried its
// own matches, so five of them plus the create row wanted more height than a
// phone has left once the keyboard is up. A Column pushes its last child out
// first, and the last child was the field that raised the keyboard — which is
// why every one of these tests asks the same question of the layout, at a
// different size: where is the field?
//
// The answer now depends on the width. Below the sidebar breakpoint the band
// keeps the bottom edge, where the thumb is; at or above it the band takes the
// top, where a short window is not about to clip it. Either way the field is the
// row on the pinned edge, so nothing the user types can move it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/data/drift_repositories.dart';
import 'package:time_tracker/phone/screens/now_screen.dart';

import 'support/flow_harness.dart';

/// A phone, and a keyboard tall enough that the body is the inset rather than
/// the tab bar.
const _phone = Size(360, 780);
const _keyboard = 380.0;

/// More matches than the list shows, so the count is the list's decision and not
/// the data's.
Future<void> _sixMatching(AppDatabase db) async {
  final activities = DriftActivityRepository(db);
  for (var i = 1; i <= 6; i++) {
    await activities.createActivity(name: 'work log $i', color: '#4F8FEE');
  }
  final running = await activities.createActivity(name: 'Deep focus', color: '#63C89B');
  await activities.setBookmarked(running.syncId, true);
  await DriftChangeRepository(db).switchTo(running.syncId);
}

Future<void> _oneRunning(AppDatabase db) async {
  final activities = DriftActivityRepository(db);
  final a = await activities.createActivity(name: 'Deep focus', color: '#63C89B');
  await DriftChangeRepository(db).switchTo(a.syncId);
}

Finder get _field => inScreen(NowScreen, find.byType(DottedField));

/// The band's own border: the decorated Container closest around the field.
Border _bandBorder(WidgetTester tester) =>
    tester
            .widgetList<Container>(find.ancestor(of: _field, matching: find.byType(Container)))
            .map((c) => c.decoration)
            .whereType<BoxDecoration>()
            .firstWhere((d) => d.border != null)
            .border
        as Border;

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(inScreen(NowScreen, find.byType(TextField)), text);
  await tester.pump();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadMonoFont();
  });

  testWidgets('a keyboard over a screenful of matches does not push the field off', (tester) async {
    await bootApp(tester, viewport: _phone, keyboard: _keyboard, seed: _sixMatching);
    await _type(tester, 'work');

    expect(tester.takeException(), isNull);
    // The Scaffold takes max(inset, tab bar) out of the body, not their sum, so
    // the keyboard line is the window less the inset.
    expect(tester.getRect(_field).bottom, lessThanOrEqualTo(_phone.height - _keyboard));
    expect(inScreen(NowScreen, find.textContaining('+ create & switch')), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('the undo offer for a same-activity switch gives the field back', (tester) async {
    // Narrow enough for the tab bar, tall like a desktop window. The offer is a
    // fixed snack bar, which the Scaffold lays over the bottom of the body —
    // exactly where the phone band keeps the field.
    await bootApp(tester, viewport: const Size(600, 900), seed: _sixMatching);
    await _type(tester, 'Deep');
    await tester.tap(inScreen(NowScreen, find.text('Deep focus')));
    await settle(tester);
    expect(find.text('new block · same activity'), findsOneWidget);

    await tester.pump(const Duration(seconds: 7));
    await settle(tester);

    expect(find.text('new block · same activity'), findsNothing);
    expect(_field.hitTestable(), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('typing swaps the bookmarks for what it matched', (tester) async {
    // The shape, asserted directly: the matches and the hero are two states of
    // one region rather than two children stacked in a Column. This is the test
    // that breaks if someone puts a growing list back under the field.
    await bootApp(tester, viewport: _phone, seed: _sixMatching);

    expect(inScreen(NowScreen, find.text('TRACKING')), findsOneWidget);

    await _type(tester, 'work');

    expect(inScreen(NowScreen, find.text('TRACKING')), findsNothing);
    expect(inScreen(NowScreen, find.text('work log 1')), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('a short window keeps the field and scrolls the start bar', (tester) async {
    // Nothing typed: the chrome alone is taller than the body here, which is
    // what a resized desktop window reaches without any keyboard at all.
    await bootApp(tester, viewport: const Size(360, 300), keyboard: 160, seed: _oneRunning);

    expect(tester.takeException(), isNull);
    expect(tester.getRect(_field).bottom, lessThanOrEqualTo(300 - 160));

    await disposeApp(tester);
  });

  testWidgets('a landscape window overflows on shape alone', (tester) async {
    // Wide enough for the sidebar, short enough to run out of height — and no
    // keyboard involved, which is the point: the defect was the Column, not the
    // inset. It also pins the wide shell, where _ReadableWidth's Center would
    // swallow a fix that shrink-wrapped the screen.
    await bootApp(tester, viewport: const Size(780, 360), seed: _sixMatching);
    await _type(tester, 'work');

    expect(tester.takeException(), isNull);
    expect(tester.getRect(_field).bottom, lessThanOrEqualTo(360));

    await disposeApp(tester);
  });

  testWidgets('a wide window puts the band above the region', (tester) async {
    // The band goes to the top exactly where the sidebar appears, so one
    // constant answers both questions and they cannot drift apart.
    await bootApp(tester, viewport: const Size(900, 700), seed: _oneRunning);

    expect(
      tester.getRect(_field).bottom,
      lessThan(tester.getRect(inScreen(NowScreen, find.text('TRACKING'))).top),
    );

    await disposeApp(tester);
  });

  testWidgets('a phone keeps the band below the region, in thumb reach', (tester) async {
    await bootApp(tester, viewport: _phone, seed: _oneRunning);

    expect(
      tester.getRect(_field).top,
      greaterThan(tester.getRect(inScreen(NowScreen, find.text('TRACKING'))).bottom),
    );

    await disposeApp(tester);
  });

  // On the phone the band's other three sides are the screen's own edges, so
  // one rule is the whole border. On the wide shell the band floats inside the
  // content cap — every edge against bare bg — so it takes the full outline
  // every boxed slab has, or the fill ends mid-air.
  testWidgets('the band is a boxed slab on a wide window', (tester) async {
    await bootApp(tester, viewport: const Size(900, 700), seed: _oneRunning);

    final border = _bandBorder(tester);
    for (final side in [border.top, border.bottom, border.left, border.right]) {
      expect(side.width, 3);
    }

    await disposeApp(tester);
  });

  testWidgets('the phone band keeps its single rule against the body', (tester) async {
    await bootApp(tester, viewport: _phone, seed: _oneRunning);

    final border = _bandBorder(tester);
    expect(border.top.width, 3);
    expect(border.left, BorderSide.none);
    expect(border.right, BorderSide.none);
    expect(border.bottom, BorderSide.none);

    await disposeApp(tester);
  });

  // The field sits on the pinned edge and the start bar on the far side of it,
  // so dropping the bar takes height off the end that is free to move. Put the
  // two rows the other way round at either width and the first keystroke yanks
  // the field out from under the finger.
  for (final (name, viewport) in const [('a wide window', Size(900, 700)), ('a phone', _phone)]) {
    testWidgets('hiding the start bar never moves the field on $name', (tester) async {
      await bootApp(tester, viewport: viewport, seed: _sixMatching);
      final before = tester.getRect(_field);

      await _type(tester, 'work');

      expect(tester.getRect(_field), before);

      await disposeApp(tester);
    });
  }

  testWidgets('a couple of matches stay against the field, not adrift', (tester) async {
    // One match is far less than fills the region. The cluster has to hang from
    // the field's edge rather than sit wherever the region starts, or the phone
    // reads as though the results belong to something else on the screen.
    await bootApp(tester, viewport: _phone, seed: _sixMatching);
    await _type(tester, 'work log 1');

    final create = inScreen(NowScreen, find.textContaining('+ create & switch'));
    expect(tester.getRect(_field).top - tester.getRect(create).bottom, lessThan(60));

    await disposeApp(tester);
  });

  testWidgets('a region too short for the create row scrolls instead of overflowing', (
    tester,
  ) async {
    // With a query typed the band is just the field, so the region takes what is
    // left of a very short window — less than one row. Everything here is inside
    // one scroll view precisely so that case scrolls rather than throws.
    await bootApp(tester, viewport: const Size(360, 200), seed: _sixMatching);
    await _type(tester, 'work');

    expect(tester.takeException(), isNull);

    await disposeApp(tester);
  });

  // The create row is the row that acts on what you typed, so it takes the edge
  // the scroll view is anchored at: the last thing a shrinking window can reach,
  // rather than the first. That is a claim about child order, so assert the
  // order — a window that happens to be tall enough proves nothing.
  testWidgets('the create row takes the anchored edge on a wide window', (tester) async {
    await bootApp(tester, viewport: const Size(780, 360), seed: _sixMatching);
    await _type(tester, 'work');

    final create = tester.getRect(inScreen(NowScreen, find.textContaining('+ create & switch')));
    final firstMatch = tester.getRect(inScreen(NowScreen, find.text('work log 1')));
    expect(create.top, lessThan(firstMatch.top));

    await disposeApp(tester);
  });

  testWidgets('the create row takes the anchored edge on a phone', (tester) async {
    await bootApp(tester, viewport: _phone, seed: _sixMatching);
    await _type(tester, 'work');

    final create = tester.getRect(inScreen(NowScreen, find.textContaining('+ create & switch')));
    final lastMatch = tester.getRect(inScreen(NowScreen, find.text('work log 5')));
    expect(create.top, greaterThan(lastMatch.top));

    await disposeApp(tester);
  });

  testWidgets('the matched list is capped, so the create row is never scrolled away', (
    tester,
  ) async {
    // Six seeded, five shown, and the create row below them: a list long enough
    // to scroll is a list that hides the one action that is not a match.
    await bootApp(tester, viewport: _phone, seed: _sixMatching);
    await _type(tester, 'work');

    expect(inScreen(NowScreen, find.textContaining('work log ')), findsNWidgets(5));

    await disposeApp(tester);
  });
}
