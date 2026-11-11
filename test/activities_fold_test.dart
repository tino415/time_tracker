// The Activities tab shows top-level activities and unfolds a parent's
// children on a tap of its chevron, without taking over the row's own tap.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/data/drift_repositories.dart';
import 'package:time_tracker/phone/screens/activities_screen.dart';

import 'support/flow_harness.dart';

const _phone = Size(400, 880);

Future<void> _seedTree(AppDatabase db) async {
  final activities = DriftActivityRepository(db);
  final work = await activities.createActivity(name: 'Work', color: '#4F8FEE');
  await activities.createActivity(name: 'Client', color: '#4F8FEE', parentId: work.syncId);
  await activities.createActivity(name: 'Admin', color: '#4F8FEE', parentId: work.syncId);
  await activities.createActivity(name: 'Home', color: '#4F8FEE');
}

Finder _onTab(String text) => inScreen(ActivitiesScreen, find.text(text));

void main() {
  testWidgets('children stay hidden until the chevron opens them', (tester) async {
    await bootApp(tester, viewport: _phone, seed: _seedTree);
    await openTab(tester, 'ACTIVITIES');

    expect(_onTab('Work'), findsOneWidget);
    expect(_onTab('Client'), findsNothing);
    expect(_onTab('▸ 2'), findsOneWidget);

    await tester.tap(_onTab('▸ 2'));
    await settle(tester);
    expect(_onTab('Client'), findsOneWidget);
    expect(_onTab('Admin'), findsOneWidget);
    expect(_onTab('▾ 2'), findsOneWidget);

    await tester.tap(_onTab('▾ 2'));
    await settle(tester);
    expect(_onTab('Client'), findsNothing);

    await disposeApp(tester);
  });

  testWidgets('tapping the row still opens the editor and leaves it folded', (tester) async {
    await bootApp(tester, viewport: _phone, seed: _seedTree);
    await openTab(tester, 'ACTIVITIES');

    await tester.tap(_onTab('Work'));
    await settle(tester);

    expect(editorNameField, findsOneWidget);
    expect(find.text('Client'), findsNothing);

    await disposeApp(tester);
  });

  testWidgets('add sub-activity unfolds its parent', (tester) async {
    await bootApp(tester, viewport: _phone, seed: _seedTree);
    await openTab(tester, 'ACTIVITIES');

    await tester.longPress(_onTab('Home'));
    await settle(tester);
    await tester.tap(find.text('+ ADD SUB-ACTIVITY'));
    await settle(tester);
    await fillEditor(tester, 'Chores', confirm: 'CREATE');

    expect(_onTab('Chores'), findsOneWidget);
    expect(_onTab('▾ 1'), findsOneWidget);

    await disposeApp(tester);
  });
}
