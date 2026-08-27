import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/block.dart';
import '../../format.dart';
import '../screens/now_screen.dart' show DottedField;
import 'neo.dart';

/// The shortest half a split may leave, matching `TrackerController.splitBlock`.
const kMinHalf = Duration(minutes: 1);

/// True when [block] is long enough to have two real halves.
bool canSplit(Block block, DateTime now) =>
    (block.end ?? now).difference(block.start) >= kMinHalf * 2;

/// Ask *where* to cut [block], returning the instant or null if dismissed.
///
/// Split used to be calendar-only, on the reasoning that a split has a
/// meaningful position only where the day is drawn to scale. That reasoning does
/// not survive short blocks: the calendar draws a minute as 0.93px, so a
/// five-minute block is under five pixels tall and a three-minute one cannot be
/// hit at all — and boundary drags there snap to five minutes, which is longer
/// than the block. For a day made of short blocks the visual position is not
/// merely awkward, it does not exist.
///
/// So the position is typed or nudged instead, at minute resolution, the same
/// way `editBlockStart` moves a boundary. The midpoint is only the starting
/// guess.
Future<DateTime?> chooseSplitPoint(BuildContext context, WidgetRef ref, Block block) {
  return showNeoSheet<DateTime>(context, (_) => _SplitSheet(block: block));
}

class _SplitSheet extends ConsumerStatefulWidget {
  const _SplitSheet({required this.block});
  final Block block;

  @override
  ConsumerState<_SplitSheet> createState() => _SplitSheetState();
}

class _SplitSheetState extends ConsumerState<_SplitSheet> {
  final _typed = TextEditingController();

  /// Captured once, for the same reason `editBlockStart` captures it: a running
  /// block's end is the present, and letting it advance under the sheet would
  /// make the halves drift while you are reading them.
  final _openedAt = DateTime.now();

  late final DateTime _end = widget.block.end ?? _openedAt;
  late DateTime _at = _clamp(widget.block.start.add(_end.difference(widget.block.start) ~/ 2));

  /// The sheet reads and writes whole minutes, so it must not *store* anything
  /// finer. The midpoint of a five-minute block is 09:02:30, which this screen
  /// would show as "09:02" while writing a boundary half a minute later — a
  /// display quietly disagreeing with what it saves.
  static DateTime _toMinute(DateTime t) => DateTime(t.year, t.month, t.day, t.hour, t.minute);

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  /// Keep the cut strictly inside the block, leaving a real half either side.
  ///
  /// The bounds themselves can carry seconds — a block starts whenever the tap
  /// landed — so pinning to a bound is the one case that writes a sub-minute
  /// boundary. That is unavoidable: rounding away from the bound would cross it.
  DateTime _clamp(DateTime desired) {
    final earliest = widget.block.start.add(kMinHalf);
    final latest = _end.subtract(kMinHalf);
    final whole = _toMinute(desired);
    if (whole.isBefore(earliest)) return earliest;
    if (whole.isAfter(latest)) return latest;
    return whole;
  }

  void _apply(DateTime? desired) {
    if (desired == null) return;
    setState(() => _at = _clamp(desired));
  }

  @override
  Widget build(BuildContext context) {
    final t = neo(context);
    final first = _at.difference(widget.block.start);
    final second = _end.difference(_at);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        margin: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: t.bg,
          border: Border.all(color: t.line, width: 3),
        ),
        padding: const EdgeInsets.all(14),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  NeoChip('Split at'),
                  const Spacer(),
                  Text(
                    widget.block.activities.map((a) => a.name).join('  +  '),
                    style: mono(context, size: 11, weight: FontWeight.w700, color: t.muted),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                formatTimeOfDay(_at),
                style: mono(context, size: 38, weight: FontWeight.w800, height: 1),
              ),
              const SizedBox(height: 8),
              // Both halves, because the question being answered is where the
              // boundary goes, and a single time does not show what it buys.
              Text(
                '${formatDurationHm(first)}  |  ${formatDurationHm(second)}',
                style: mono(context, size: 13, weight: FontWeight.w700, color: t.muted),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (final m in const [-15, -5, -1, 1, 5, 15])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: NeoPressable(
                          shadowOffset: 3,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          onTap: () => _apply(_at.add(Duration(minutes: m))),
                          child: Center(
                            child: Text(
                              m > 0 ? '+$m' : '$m',
                              style: mono(context, size: 13, weight: FontWeight.w800),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'minutes',
                textAlign: TextAlign.center,
                style: mono(context, size: 10, weight: FontWeight.w700, color: t.muted, spacing: 1),
              ),
              const SizedBox(height: 12),
              DottedField(
                controller: _typed,
                hint: 'or type a time, e.g. ${formatTimeOfDay(_at)}',
                onSubmitted: (v) {
                  _apply(parseTimeOfDay(v, onDay: widget.block.start));
                  _typed.clear();
                },
              ),
              const SizedBox(height: 8),
              Text(
                'between ${formatTimeOfDay(widget.block.start.add(kMinHalf))} '
                'and ${formatTimeOfDay(_end.subtract(kMinHalf))}',
                style: mono(context, size: 11, weight: FontWeight.w700, color: t.muted),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: NeoButton(
                      label: 'cancel',
                      shadowOffset: 3,
                      onTap: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: NeoButton(
                      label: 'split here',
                      primary: true,
                      shadowOffset: 3,
                      onTap: () => Navigator.pop(context, _at),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
