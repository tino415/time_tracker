// Shared harness for the phone-flow suites: the widget-level one under test/
// and the on-device one under integration_test/. Both drive the same screens,
// so the finders and the pumping strategy live here.

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/data/providers.dart';
import 'package:time_tracker/phone/phone_app.dart';
import 'package:time_tracker/theme/tokens.dart';

/// Register the app's own mono face, for widget tests whose rows are laid out
/// from text widths: the fallback face `flutter test` supplies is wide enough
/// that a realistic activity name overflows one by a pixel or two — an artefact
/// of the stand-in font that says nothing about the screen.
///
/// Read off disk rather than through `rootBundle`, so it only works where the
/// package root is the working directory — `flutter test`, not a device.
Future<void> loadMonoFont() async {
  final loader = FontLoader(kMonoFont);
  for (final weight in ['Regular', 'Bold', 'ExtraBold']) {
    final bytes = File('assets/fonts/JetBrainsMono-$weight.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

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
///
/// [keyboard] raises a soft keyboard of that many logical pixels. The Scaffold
/// takes the *greater* of this and the tab bar out of the body rather than their
/// sum, so a value under the bar's 52 changes nothing.
///
/// [seed] runs against the database *before* the first frame, for tests that
/// need existing history rather than history built through the UI.
Future<AppDatabase> bootApp(
  WidgetTester tester, {
  Size? viewport,
  double keyboard = 0,
  Future<void> Function(AppDatabase db)? seed,
}) async {
  if (viewport != null) {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  if (keyboard > 0) {
    // Physical pixels, like physicalSize — the same as logical only because the
    // ratio above is pinned to 1.
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.resetViewInsets);
  }

  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  if (seed != null) await seed(db);
  await tester.pumpWidget(
    ProviderScope(overrides: [databaseProvider.overrideWithValue(db)], child: const PhoneApp()),
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

final editorNameField = find.widgetWithText(TextField, 'name (paste CU-1234 Title…)').last;

/// Fills the activity-editor sheet's name field and confirms it.
Future<void> fillEditor(WidgetTester tester, String name, {required String confirm}) async {
  await tester.enterText(editorNameField, name);
  await tester.pump();
  await tester.tap(find.text(confirm));
  await settle(tester);
}

Future<void> openTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await settle(tester);
}
