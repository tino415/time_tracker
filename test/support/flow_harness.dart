// Shared harness for the phone-flow suites: the widget-level one under test/
// and the on-device one under integration_test/. Both drive the same screens,
// so the finders and the pumping strategy live here.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/data/providers.dart';
import 'package:time_tracker/phone/phone_app.dart';

/// A bounded stand-in for `pumpAndSettle`, which would never return here: the
/// Now hero animates forever (live dot + second ticker). Route and sheet
/// transitions need *successive* frames — one big `pump(1s)` only starts them —
/// and they ignore pointers until finished, so taps before this are inert.
Future<void> settle(WidgetTester tester, {int frames = 24}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The tab bar is an IndexedStack, whose off-screen children stay built, so
/// screen-scoped finders are needed to avoid matching a hidden tab's identical
/// label (both Now and Activities offer "+ NEW ACTIVITY").
Finder inScreen(Type screen, Finder matching) =>
    find.descendant(of: find.byType(screen), matching: matching);

/// Boot the app against a fresh in-memory database. Pass [viewport] to force a
/// phone-shaped surface (the widget-test default is a 800x600 landscape one);
/// on a real device leave it null and use the device's own screen.
Future<AppDatabase> bootApp(WidgetTester tester, {Size? viewport}) async {
  if (viewport != null) {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const PhoneApp(),
    ),
  );
  await settle(tester); // route transition + first stream emissions
  return db;
}

/// Tear the app down *inside* the test body. Cancelling the last listener of a
/// drift stream makes `StreamQueryStore.markAsClosed` schedule a zero-duration
/// timer; if the ProviderScope is only disposed by the framework's own post-test
/// unmount, that timer is created after the last pump and trips the
/// "A Timer is still pending" invariant. Disposing here leaves a frame to flush it.
Future<void> disposeApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 50));
}

/// Fills the activity-editor sheet (the last text field in the tree is the one
/// in the freshly pushed sheet) and confirms it.
Future<void> fillEditor(
  WidgetTester tester,
  String name, {
  required String confirm,
}) async {
  await tester.enterText(find.byType(TextField).last, name);
  await tester.pump();
  await tester.tap(find.text(confirm));
  await settle(tester);
}

Future<void> openTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await settle(tester);
}
