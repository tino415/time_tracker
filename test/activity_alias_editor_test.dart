import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/data/drift_repositories.dart';
import 'package:time_tracker/phone/screens/now_screen.dart';

import 'support/flow_harness.dart';

const _phone = Size(400, 880);

final _aliasField = find.widgetWithText(TextField, 'add an alias');

Future<void> _addAlias(WidgetTester tester, String alias) async {
  await tester.enterText(_aliasField, alias);
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('add-alias')));
  await tester.pump();
}

void main() {
  testWidgets('aliases are added with the + button, keep their commas, and are saved', (
    tester,
  ) async {
    final db = await bootApp(tester, viewport: _phone);

    await tester.tap(inScreen(NowScreen, find.text('+ NEW ACTIVITY')));
    await settle(tester);
    await tester.enterText(editorNameField, 'Učenie sa');
    await _addAlias(tester, 'Learning');
    await _addAlias(tester, 'deep, focused');

    expect(find.text('Learning'), findsOneWidget);
    expect(find.text('deep, focused'), findsOneWidget);
    expect(tester.widget<TextField>(_aliasField).controller!.text, isEmpty);

    await tester.tap(find.text('CREATE & SWITCH'));
    await settle(tester);

    final saved = (await DriftActivityRepository(db).loadActivities()).single;
    expect(saved.aliases, ['Learning', 'deep, focused']);

    await disposeApp(tester);
  });

  testWidgets('an alias still typed when saving is kept, and a chip can be removed', (
    tester,
  ) async {
    final db = await bootApp(tester, viewport: _phone);

    await tester.tap(inScreen(NowScreen, find.text('+ NEW ACTIVITY')));
    await settle(tester);
    await tester.enterText(editorNameField, 'Učenie sa');
    await _addAlias(tester, 'Learning');
    await _addAlias(tester, 'Study');
    await tester.tap(find.byKey(const ValueKey('remove-alias-Study')));
    await tester.pump();
    await tester.enterText(_aliasField, 'Vzdelávanie');
    await tester.pump();

    await tester.tap(find.text('CREATE & SWITCH'));
    await settle(tester);

    final saved = (await DriftActivityRepository(db).loadActivities()).single;
    expect(saved.aliases, ['Learning', 'Vzdelávanie']);

    await disposeApp(tester);
  });
}
