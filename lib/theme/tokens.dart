import 'package:flutter/material.dart';

/// Neobrutalist design tokens, inspired by otin.dev (see ~/org/todo.org
/// "Time-activity tracking app" → Design). The *chrome* is monochrome + one
/// green accent; per-activity colour is the content that lives inside
/// black-bordered, hard-shadow cards.
@immutable
class NeoTokens extends ThemeExtension<NeoTokens> {
  const NeoTokens({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.ink,
    required this.muted,
    required this.line,
    required this.brand,
    required this.brandInk,
    required this.shadow,
  });

  final Color bg;
  final Color surface;
  final Color surface2;
  final Color ink;
  final Color muted;
  final Color line; // borders
  final Color brand; // otin green
  final Color brandInk; // text/icon on brand
  final Color shadow; // hard offset shadow colour

  static const light = NeoTokens(
    bg: Color(0xFFE7E8EA),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFEDEDEF),
    ink: Color(0xFF0A0A0A),
    muted: Color(0xFF6B6C66),
    line: Color(0xFF0A0A0A),
    brand: Color(0xFF2E5D3A),
    brandInk: Color(0xFFFFFFFF),
    shadow: Color(0xFF0A0A0A),
  );

  static const dark = NeoTokens(
    bg: Color(0xFF000000),
    surface: Color(0xFF141518),
    surface2: Color(0xFF1E2024),
    ink: Color(0xFFF3F3EF),
    muted: Color(0xFF9A9B95),
    line: Color(0xFFF3F3EF),
    brand: Color(0xFF57C97D),
    brandInk: Color(0xFF06140B),
    shadow: Color(0xFF3A3B3E),
  );

  /// Hard, zero-blur offset shadow — the signature neobrutalist device. Press
  /// interactions collapse this to `[]` and translate by [offset].
  List<BoxShadow> hardShadow([double offset = 6]) => [
    BoxShadow(color: shadow, offset: Offset(offset, offset), blurRadius: 0),
  ];

  /// A bordered, hard-shadowed card decoration. Pass an activity [fill] to make
  /// it a colour block; otherwise it uses [surface].
  BoxDecoration card({Color? fill, double shadowOffset = 6}) => BoxDecoration(
    color: fill ?? surface,
    border: Border.all(color: line, width: 3),
    boxShadow: hardShadow(shadowOffset),
  );

  @override
  NeoTokens copyWith({
    Color? bg,
    Color? surface,
    Color? surface2,
    Color? ink,
    Color? muted,
    Color? line,
    Color? brand,
    Color? brandInk,
    Color? shadow,
  }) => NeoTokens(
    bg: bg ?? this.bg,
    surface: surface ?? this.surface,
    surface2: surface2 ?? this.surface2,
    ink: ink ?? this.ink,
    muted: muted ?? this.muted,
    line: line ?? this.line,
    brand: brand ?? this.brand,
    brandInk: brandInk ?? this.brandInk,
    shadow: shadow ?? this.shadow,
  );

  @override
  NeoTokens lerp(ThemeExtension<NeoTokens>? other, double t) {
    if (other is! NeoTokens) return this;
    return NeoTokens(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      line: Color.lerp(line, other.line, t)!,
      brand: Color.lerp(brand, other.brand, t)!,
      brandInk: Color.lerp(brandInk, other.brandInk, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
    );
  }
}

/// Placeholder activity palette (users assign real per-activity colours). Text
/// on any of these = ink; auto-flip to white only for a genuinely dark fill via
/// [onFill].
class ActivityPalette {
  static const blue = Color(0xFF4F8FEE);
  static const amber = Color(0xFFF4B740);
  static const red = Color(0xFFE5604D);
  static const purple = Color(0xFF8B7FE8);
  static const teal = Color(0xFF34B98C);
  static const pink = Color(0xFFEC6FA8);

  static const all = <Color>[blue, amber, red, purple, teal, pink];

  /// Readable text colour for an activity [fill] (black on light, white on dark).
  static Color onFill(Color fill) =>
      fill.computeLuminance() > 0.45 ? const Color(0xFF0A0A0A) : Colors.white;
}

const kMonoFont = 'JetBrainsMono';

/// Build a Material theme wired to [NeoTokens] and the bundled mono face.
ThemeData neoTheme(NeoTokens t, Brightness brightness) {
  final base = ThemeData(brightness: brightness, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: t.bg,
    extensions: [t],
    colorScheme: base.colorScheme.copyWith(
      primary: t.brand,
      surface: t.surface,
    ),
    textTheme: base.textTheme.apply(
      fontFamily: kMonoFont,
      bodyColor: t.ink,
      displayColor: t.ink,
    ),
  );
}
