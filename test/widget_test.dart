// Scaffold smoke tests — pure token/palette logic, no plugins or DB so the
// suite runs anywhere. Real widget + drift tests arrive with the phase-1 UI.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/theme/tokens.dart';

void main() {
  test('light and dark tokens are distinct', () {
    expect(NeoTokens.light.bg, isNot(NeoTokens.dark.bg));
    expect(NeoTokens.light.line, const Color(0xFF0A0A0A));
    expect(NeoTokens.dark.line, const Color(0xFFF3F3EF));
  });

  test('hard shadow has zero blur (neobrutalist)', () {
    final s = NeoTokens.light.hardShadow(6).single;
    expect(s.blurRadius, 0);
    expect(s.offset, const Offset(6, 6));
  });

  test('onFill picks readable text colour', () {
    expect(ActivityPalette.onFill(ActivityPalette.amber), const Color(0xFF0A0A0A));
    expect(ActivityPalette.onFill(const Color(0xFF10203A)), Colors.white);
  });
}
