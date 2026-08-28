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
  List<BoxShadow> hardShadow([double offset = 6]) => _hardShadow(shadow, offset);

  /// Width of the [bg] band nearest the box in the two-tone focus ring —
  /// shared with [focusRingWidth] by both renderers of it, shadow and border.
  static const double focusBandWidth = 2;

  /// Width of the visible [brand] layer, just outside the [focusBandWidth] band.
  static const double focusRingWidth = 4;

  /// The keyboard focus ring: [brand], held off whatever the box is drawn
  /// against by a [focusBandWidth] band of [bg].
  ///
  /// A plain brand shadow was tried first and dropped: `brand` measures
  /// 2.6:1 (light) / 1.9:1 (dark) against the `line` border a control usually
  /// sits flush against, and 1:1 against a primary button's own `brand` fill
  /// — invisible in exactly the case where a ring matters most. The `bg` band
  /// gives brand a neighbour it clears at 6.2:1 / 10.1:1 regardless of what
  /// the box itself is filled with.
  ///
  /// Drawn in the shadow rather than the border because it then costs no
  /// layout — focus never nudges what it lands on. Spread, not blurred, so the
  /// edge stays hard like every other shadow here: [focusRingWidth] out is
  /// [brand], [focusBandWidth] out is [bg], between them is a flat colour
  /// change rather than a fade.
  ///
  /// Flutter paints `boxShadow` bottom-to-top by list index — the opposite of
  /// CSS, where the first entry is on top — so this list is built back to
  /// front: the resting hard shadow on the bottom, the brand spread in the
  /// middle, and the bg band last so it punches through the middle of the
  /// brand spread instead of being buried under it.
  List<BoxShadow> focusShadow([double offset = 6]) => [
    ..._hardShadow(shadow, offset),
    BoxShadow(color: brand, spreadRadius: focusBandWidth + focusRingWidth),
    BoxShadow(color: bg, spreadRadius: focusBandWidth),
  ];

  static List<BoxShadow> _hardShadow(Color color, double offset) => [
    BoxShadow(color: color, offset: Offset(offset, offset), blurRadius: 0),
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

/// The activity colour palette: twelve curated fills, offered as swatches in the
/// editor. Storage does not constrain this — an activity's colour is a hex
/// string — so the palette is a convention, and a wider one is what a deep
/// activity tree needs before siblings start sharing a colour.
///
/// Every addition was checked against the three things that actually break:
///
///  * **The [onFill] threshold.** A fill whose luminance sits near 0.45 flips
///    its label between ink and white on rounding alone, so it looks different
///    on a chip than in the calendar. Every colour here clears 0.45 by a wide
///    margin except `teal` (0.373), which predates the rule.
///  * **The calendar's 35% alpha.** Blocks are filled washed-out, which costs
///    saturation, not hue — so separation is carried by hue and lightness, and
///    two colours are never both near-hue and near-luminance. `slate` is the
///    case to watch: it is the only near-blue neutral, and it is kept apart by
///    being much darker (0.18 vs 0.28) and far less saturated (0.15 vs 0.67).
///  * **Colour-blind separability**, which gets *harder* with every colour
///    added, not easier. Luminance is spread deliberately so red/green pairs
///    stay distinguishable when hue does not help. This remains an open manual
///    check — twelve well-separated fills is near the practical ceiling, and a
///    thirteenth should replace one rather than join them.
///
/// Ordered by hue so the swatch row reads as a spectrum, with the neutral last.
class ActivityPalette {
  static const red = Color(0xFFE5604D);
  static const orange = Color(0xFFF0813C);
  static const amber = Color(0xFFF4B740);
  static const olive = Color(0xFF8C9440);
  static const teal = Color(0xFF34B98C);
  static const cyan = Color(0xFF2A8FA6);
  static const blue = Color(0xFF4F8FEE);
  static const indigo = Color(0xFF3E5AC8);
  static const purple = Color(0xFF8B7FE8);
  static const magenta = Color(0xFFC44BB0);
  static const pink = Color(0xFFEC6FA8);
  static const slate = Color(0xFF6E7681);

  static const all = <Color>[
    red,
    orange,
    amber,
    olive,
    teal,
    cyan,
    blue,
    indigo,
    purple,
    magenta,
    pink,
    slate,
  ];

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
    colorScheme: base.colorScheme.copyWith(primary: t.brand, surface: t.surface),
    textTheme: base.textTheme.apply(fontFamily: kMonoFont, bodyColor: t.ink, displayColor: t.ink),
  );
}
