import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

/// Read the neobrutalist tokens off the theme.
NeoTokens neo(BuildContext context) => Theme.of(context).extension<NeoTokens>()!;

TextStyle mono(
  BuildContext context, {
  double size = 14,
  FontWeight weight = FontWeight.w400,
  Color? color,
  double? spacing,
  double? height,
}) {
  final t = neo(context);
  return TextStyle(
    fontFamily: kMonoFont,
    fontSize: size,
    fontWeight: weight,
    color: color ?? t.ink,
    letterSpacing: spacing,
    height: height,
  );
}

/// Inverse label chip — the otin.dev section-header device: a solid [line] box
/// with bold uppercase [surface] text. Green variant fills [brand].
class NeoChip extends StatelessWidget {
  const NeoChip(this.text, {super.key, this.brand = false});

  final String text;
  final bool brand;

  @override
  Widget build(BuildContext context) {
    final t = neo(context);
    return Container(
      color: brand ? t.brand : t.line,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Text(
        text.toUpperCase(),
        style: mono(
          context,
          size: 11,
          weight: FontWeight.w800,
          spacing: 1.2,
          color: brand ? t.brandInk : t.surface,
        ),
      ),
    );
  }
}

/// A section header row: an inverse chip on the left, optional trailing widget.
class NeoSectionHeader extends StatelessWidget {
  const NeoSectionHeader(this.label, {super.key, this.trailing, this.brand = false});

  final String label;
  final Widget? trailing;
  final bool brand;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        NeoChip(label, brand: brand),
        const Spacer(),
        ?trailing,
      ],
    );
  }
}

/// Hard-shadow pressable. On press it translates by the shadow offset and
/// collapses the shadow to zero (physical-button feel), ~120ms.
class NeoPressable extends StatefulWidget {
  const NeoPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.fill,
    this.shadowOffset = 6,
    this.padding = const EdgeInsets.all(12),
    this.borderWidth = 3,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Card fill; null uses [NeoTokens.surface].
  final Color? fill;
  final double shadowOffset;
  final EdgeInsets padding;
  final double borderWidth;

  @override
  State<NeoPressable> createState() => _NeoPressableState();
}

class _NeoPressableState extends State<NeoPressable> {
  bool _pressed = false;

  void _set(bool v) {
    if (widget.onTap == null && widget.onLongPress == null) return;
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final t = neo(context);
    final o = widget.shadowOffset;
    final enabled = widget.onTap != null || widget.onLongPress != null;

    return GestureDetector(
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapUp: enabled ? (_) => _set(false) : null,
      onTapCancel: enabled ? () => _set(false) : null,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(
          _pressed ? o : 0,
          _pressed ? o : 0,
          0,
        ),
        decoration: BoxDecoration(
          color: widget.fill ?? t.surface,
          border: Border.all(color: t.line, width: widget.borderWidth),
          boxShadow: _pressed ? const [] : t.hardShadow(o),
        ),
        padding: widget.padding,
        child: widget.child,
      ),
    );
  }
}

/// A labelled button. Primary = [brand] fill; otherwise [surface].
class NeoButton extends StatelessWidget {
  const NeoButton({
    super.key,
    required this.label,
    this.onTap,
    this.primary = false,
    this.icon,
    this.shadowOffset = 5,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final String? icon;
  final double shadowOffset;

  /// Shrink-wrap the label instead of letting it flex. Required when the button
  /// is a *non-flex child of a Row* — there the incoming width is unbounded, and
  /// a flexing label would assert. Full-width uses (a stretched Column, an
  /// Expanded slot) want the default.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = neo(context);
    final fg = primary ? t.brandInk : t.ink;
    return NeoPressable(
      onTap: onTap,
      fill: primary ? t.brand : t.surface,
      shadowOffset: shadowOffset,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        children: [
          if (icon != null) ...[
            Text(icon!, style: mono(context, weight: FontWeight.w800, color: fg)),
            const SizedBox(width: 8),
          ],
          if (compact)
            Text(
              label.toUpperCase(),
              textAlign: TextAlign.center,
              style: mono(context, weight: FontWeight.w800, spacing: .6, color: fg),
            )
          else
            Flexible(
              child: Text(
                label.toUpperCase(),
                textAlign: TextAlign.center,
                style: mono(context, weight: FontWeight.w800, spacing: .6, color: fg),
              ),
            ),
        ],
      ),
    );
  }
}

/// Rebuilds [builder] every second with the current time — for live elapsed
/// clocks. Ticks only while mounted.
class SecondTicker extends StatefulWidget {
  const SecondTicker({super.key, required this.builder});

  final Widget Function(BuildContext context, DateTime now) builder;

  @override
  State<SecondTicker> createState() => _SecondTickerState();
}

class _SecondTickerState extends State<SecondTicker> {
  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _now);
}

/// A small square colour swatch with the neobrutalist 2px border.
class NeoSwatch extends StatelessWidget {
  const NeoSwatch(this.color, {super.key, this.size = 18});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = neo(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, border: Border.all(color: t.line, width: 2)),
    );
  }
}
