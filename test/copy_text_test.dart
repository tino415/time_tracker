// Getting text back out of the app: a block's name and note, and an activity's
// name and external id, reach the clipboard.
//
// Copy is an explicit action rather than selectable text, because the surfaces
// carrying this text are already gesture targets — timeline cards take taps and
// long-presses, calendar blocks take drags. So what these tests drive is the
// route through the action sheets, which is the whole affordance.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/data/drift_repositories.dart';
import 'package:time_tracker/phone/screens/activities_screen.dart';
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
}
