// The Now screen has one region that grows and a strip of chrome that does not.
//
// It used to have the growing part *below* the fixed part: the field carried its
// own matches, so five of them plus the create row wanted more height than a
// phone has left once the keyboard is up. A Column pushes its last child out
// first, and the last child was the field that raised the keyboard — which is
// why every one of these tests asks the same question of the layout, at a
// different size: where is the field?

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
