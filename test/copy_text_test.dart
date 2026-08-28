// Getting text back out of the app: a block's name and note, and an activity's
// name and external id, reach the clipboard.
//
// Selection is per input now, not settled either way for the whole app. Touch
// has no drag to spare — the timeline, calendar and catalogue rows are already
// tap and long-press targets, and the calendar's are drag-to-retime too — so
// there the copy button stays the only way to get text out. A mouse has no
// gestures to spend on a tap-only surface, so there `SelectionArea` turns on
// alongside the button (`pointer_signal.dart`, `hasPointerProvider`). The
// calendar is the one exception even with a mouse: it still spends drags on
// retiming and long-press on splitting, so it is deliberately left out — see
// `timeline_screen.dart`.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/data/drift_repositories.dart';
import 'package:time_tracker/data/pointer_signal.dart';
import 'package:time_tracker/data/providers.dart';
import 'package:time_tracker/phone/phone_app.dart';
import 'package:time_tracker/phone/screens/activities_screen.dart';
import 'package:time_tracker/phone/screens/calendar_screen.dart';
import 'package:time_tracker/phone/screens/now_screen.dart';
import 'package:time_tracker/phone/screens/timeline_screen.dart';

import 'support/flow_harness.dart';

const _phone = Size(400, 880);

/// The clipboard is a platform channel, so the harness has to stand in for it.
/// Returns a getter for whatever was last copied.
String? Function() _captureClipboard(WidgetTester tester) {
  String? copied;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
    call,
  ) async {
    if (call.method == 'Clipboard.setData') {
      copied = (call.arguments as Map)['text'] as String?;
    }
    return null;
  });
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return () => copied;
}

Future<void> _seed(AppDatabase db) async {
  final activities = DriftActivityRepository(db);
  final changes = DriftChangeRepository(db);
  final a = await activities.createActivity(
    name: 'CU-1042 Rotate the signing key',
    color: '#4F8FEE',
    externalId: 'CU-1042',
  );
  final change = await changes.switchTo(a.syncId);
  await changes.setComment(change.syncId, 'blocked on the vendor sandbox');
}

/// `bootApp` (`support/flow_harness.dart`) has no lever for `hasPointerProvider`
/// — every other suite wants the touch-only default — so the pointer-signal
/// cases boot the app themselves, adding that one override.
Future<AppDatabase> _bootWithPointer(
  WidgetTester tester, {
  required bool hasPointer,
  Future<void> Function(AppDatabase db)? seed,
}) async {
  tester.view.physicalSize = _phone;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  if (seed != null) await seed(db);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        hasPointerProvider.overrideWithValue(hasPointer),
      ],
      child: const PhoneApp(),
    ),
  );
  await settle(tester);
  return db;
}

void main() {
  testWidgets('a block\'s name and note copy from the timeline', (tester) async {
    final clipboard = _captureClipboard(tester);
    await bootApp(tester, viewport: _phone, seed: _seed);

    await openTab(tester, 'TIMELINE');
    await tester.tap(inScreen(TimelineScreen, find.text('CU-1042 Rotate the signing key')));
    await settle(tester);

    await tester.tap(find.text('⧉ COPY NAME'));
    await settle(tester);
    expect(clipboard(), 'CU-1042 Rotate the signing key');

    // The note is a separate action, and only offered when there is one.
    await tester.tap(inScreen(TimelineScreen, find.text('CU-1042 Rotate the signing key')));
    await settle(tester);
    await tester.tap(find.text('⧉ COPY NOTE'));
    await settle(tester);
    expect(clipboard(), 'blocked on the vendor sandbox');

    await disposeApp(tester);
  });

  testWidgets('an activity\'s name and external id copy from its row', (tester) async {
    final clipboard = _captureClipboard(tester);
    await bootApp(tester, viewport: _phone, seed: _seed);

    await openTab(tester, 'ACTIVITIES');
    await tester.longPress(inScreen(ActivitiesScreen, find.text('CU-1042 Rotate the signing key')));
    await settle(tester);

    await tester.tap(find.text('⧉ COPY CU-1042'));
    await settle(tester);
    // The id alone, not the whole name — that is the point of a separate action.
    expect(clipboard(), 'CU-1042');

    await disposeApp(tester);
  });

  testWidgets('without a mouse, nothing in the app is selectable', (tester) async {
    await bootApp(tester, viewport: _phone, seed: _seed);

    // The tab bar is an IndexedStack (see flow_harness.dart), so Now, Timeline,
    // Reports and Activities are all built at once here — one check covers
    // every screen `hasPointerProvider`'s inert default is meant to protect.
    expect(find.byType(SelectionArea), findsNothing);

    await disposeApp(tester);
  });

  testWidgets('a mouse makes the Now hero and the timeline list selectable, '
      'and copy still works', (tester) async {
    final clipboard = _captureClipboard(tester);
    await _bootWithPointer(tester, hasPointer: true, seed: _seed);

    // Now opens by default: the hero's name and note both sit inside a
    // selection region.
    expect(
      find.ancestor(
        of: inScreen(NowScreen, find.text('CU-1042 Rotate the signing key')),
        matching: find.byType(SelectionArea),
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: inScreen(NowScreen, find.text('blocked on the vendor sandbox')),
        matching: find.byType(SelectionArea),
      ),
      findsOneWidget,
    );

    await openTab(tester, 'TIMELINE');
    expect(
      find.ancestor(
        of: inScreen(TimelineScreen, find.text('CU-1042 Rotate the signing key')),
        matching: find.byType(SelectionArea),
      ),
      findsOneWidget,
    );

    // Selectable does not mean the copy button stopped working — it is a
    // second way to get the text out, not a replacement.
    await tester.tap(inScreen(TimelineScreen, find.text('CU-1042 Rotate the signing key')));
    await settle(tester);
    await tester.tap(find.text('⧉ COPY NAME'));
    await settle(tester);
    expect(clipboard(), 'CU-1042 Rotate the signing key');

    await disposeApp(tester);
  });

  testWidgets('a mouse still leaves the calendar unselectable', (tester) async {
    await _bootWithPointer(tester, hasPointer: true, seed: _seed);

    await openTab(tester, 'TIMELINE');
    await tester.tap(find.text('▦ CALENDAR'));
    await settle(tester);
    expect(find.byType(CalendarScreen), findsOneWidget);

    // The assertion that stops someone "tidying up" by hoisting the wrapper
    // from `_TimelineList` up to `TimelineScreen`: that would give the
    // calendar a selection drag on top of the drag it already spends on
    // retiming.
    expect(
      find.ancestor(of: find.byType(CalendarScreen), matching: find.byType(SelectionArea)),
      findsNothing,
    );

    await disposeApp(tester);
  });

  testWidgets('a mouse does not swallow the catalogue\'s long-press row menu', (tester) async {
    await _bootWithPointer(tester, hasPointer: true, seed: _seed);

    await openTab(tester, 'ACTIVITIES');
    expect(
      find.ancestor(
        of: inScreen(ActivitiesScreen, find.text('CU-1042 Rotate the signing key')),
        matching: find.byType(SelectionArea),
      ),
      findsOneWidget,
    );

    await tester.longPress(inScreen(ActivitiesScreen, find.text('CU-1042 Rotate the signing key')));
    await settle(tester);
    expect(find.text('+ ADD SUB-ACTIVITY'), findsOneWidget);

    await disposeApp(tester);
  });
}
