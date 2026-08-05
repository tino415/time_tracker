import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/tracker_controller.dart';
import '../../domain/calendar.dart';
import '../../format.dart';
import '../widgets/block_actions.dart';
import '../widgets/neo.dart';

/// The calendar edit view: one local day on a vertical time axis, blocks drawn
/// to scale, with draggable boundaries.
///
/// Editing model — a boundary belongs to *both* the block above and the block
/// below it, so dragging the handle between two blocks lengthens one and
/// shortens the other in a single write. That is why the handles sit between
/// blocks rather than on their edges: there is only ever one thing to drag.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

/// Pixels per hour. 56 keeps a whole day (1344px) inside two or three flicks
/// while leaving a 5-minute step (~4.7px) comfortably draggable.
const _hourHeight = 56.0;
const _pxPerMinute = _hourHeight / 60.0;

/// Width of the hour-label gutter on the left.
const _gutter = 44.0;

/// Drags land on tidy times rather than wherever the finger stopped.
const _snap = Duration(minutes: 5);

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  int _dayOffset = 0; // 0 = today, -1 = yesterday, …

  /// While a handle is held: the boundary being moved and its live time, so the
  /// view can follow the finger before anything is written.
  String? _draggingId;
  DateTime? _dragAt;

  @override
  Widget build(BuildContext context) {
    final t = neo(context);
    final blocks = ref.watch(blocksProvider);
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day + _dayOffset);

    final slices = sliceDay(blocks: blocks, day: day, now: now);
    // Newest-first, so the earliest block — the one with no boundary before it
    // — is last.
    final earliestId = blocks.isEmpty ? null : blocks.last.change.syncId;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: _DaySelector(
            label: _dayLabel(day, now),
            onPrev: () => setState(() => _dayOffset--),
            onNext: _dayOffset < 0 ? () => setState(() => _dayOffset++) : null,
          ),
        ),
        Expanded(
          child: slices.isEmpty
              ? Center(child: Text('nothing tracked this day', style: mono(context, color: t.muted)))
              : SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: SizedBox(
                      height: 24 * _hourHeight,
                      child: Stack(
                        children: [
                          const _HourGrid(),
                          for (final s in slices) _sliceCard(context, s, now),
                          // Handles paint above the cards so a boundary stays
                          // grabbable where two blocks meet.
                          for (final s in slices)
                            if (_hasHandle(s, earliestId)) _handleFor(s),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  /// A boundary is draggable only when it is genuinely on this day (a midnight
  /// clip is not a real boundary) and is not the very first change — that one
  /// has nothing before it to trade time with.
  bool _hasHandle(DaySlice s, String? earliestId) =>
      !s.continuesBefore && s.block.change.syncId != earliestId;

  /// The handle that *opens* [s] — it sits at the slice's top edge.
  Widget _handleFor(DaySlice s) {
    final live = _draggingId == s.block.change.syncId ? _dragAt : null;
    final at = live ?? s.start;
    final top = minutesFromMidnight(at) * _pxPerMinute;

    return Positioned(
      key: ValueKey('handle-${s.block.change.syncId}'),
      left: _gutter,
      right: 0,
      // The visible bar is 3px but the grab area is 22px — a 3px target is not
      // reachable with a finger.
      top: top - 11,
      height: 22,
      child: _BoundaryHandle(
        label: formatTimeOfDay(at),
        dragging: live != null,
        onStart: () => setState(() {
          _draggingId = s.block.change.syncId;
          _dragAt = s.start;
        }),
        onUpdate: (dy) => setState(() {
          final moved = (_dragAt ?? s.start).add(
            Duration(milliseconds: (dy / _pxPerMinute * 60000).round()),
          );
          _dragAt = moved;
        }),
        onEnd: () => _commitDrag(s),
      ),
    );
  }

  Future<void> _commitDrag(DaySlice s) async {
    final at = _dragAt;
    setState(() {
      _draggingId = null;
      _dragAt = null;
    });
    if (at == null) return;
    await ref.read(trackerControllerProvider).moveBoundary(
          s.block.change.syncId,
          snapTime(at, _snap),
        );
  }

  Widget _sliceCard(BuildContext context, DaySlice s, DateTime now) {
    final top = s.startMinutes * _pxPerMinute;
    final height = (s.endMinutes - s.startMinutes) * _pxPerMinute;

    return Positioned(
      key: ValueKey('slice-${s.block.change.syncId}'),
      left: _gutter,
      right: 0,
      top: top,
      height: height,
      child: _SliceCard(
        slice: s,
        now: now,
        onTap: () => showBlockActions(
          context,
          ref,
          s.block,
          canMerge: !s.continuesBefore,
          onSplit: () => _split(s, _midpoint(s, now)),
        ),
        onLongPressAt: (fraction) => _split(s, _timeAtFraction(s, fraction)),
      ),
    );
  }

  /// Split at the point the finger landed, so a long-press on the calendar cuts
  /// exactly where it looks like it will.
  DateTime _timeAtFraction(DaySlice s, double fraction) {
    final span = s.end.difference(s.start).inMilliseconds;
    return snapTime(
      s.start.add(Duration(milliseconds: (span * fraction).round())),
      _snap,
    );
  }

  DateTime _midpoint(DaySlice s, DateTime now) {
    final end = s.block.end ?? now;
    return snapTime(
      s.block.start.add(Duration(milliseconds: end.difference(s.block.start).inMilliseconds ~/ 2)),
      _snap,
    );
  }

  Future<void> _split(DaySlice s, DateTime at) => promptSplit(context, ref, s.block, at);

  static String _dayLabel(DateTime day, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${days[day.weekday - 1]} ${day.day}/${day.month}';
  }
}

class _DaySelector extends StatelessWidget {
  const _DaySelector({required this.label, required this.onPrev, this.onNext});
  final String label;
  final VoidCallback onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        NeoButton(label: '‹', onTap: onPrev, shadowOffset: 3, compact: true),
        Expanded(
          child: Center(child: Text(label, style: mono(context, weight: FontWeight.w800))),
        ),
        NeoButton(label: '›', onTap: onNext, shadowOffset: 3, compact: true),
      ],
    );
  }
}

/// Hour lines + labels behind the blocks.
class _HourGrid extends StatelessWidget {
  const _HourGrid();

  @override
  Widget build(BuildContext context) {
    final t = neo(context);
    return Stack(
      children: [
        for (var h = 0; h < 24; h++)
          Positioned(
            left: 0,
            right: 0,
            top: h * _hourHeight,
            height: _hourHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: _gutter,
                  child: Text(
                    '${h.toString().padLeft(2, '0')}:00',
                    style: mono(context, size: 10, color: t.muted),
                  ),
                ),
                Expanded(
                  child: Container(height: 1, color: t.line.withValues(alpha: .18)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SliceCard extends StatelessWidget {
  const _SliceCard({
    required this.slice,
    required this.now,
    required this.onTap,
    required this.onLongPressAt,
  });

  final DaySlice slice;
  final DateTime now;
  final VoidCallback onTap;

  /// Long-press position as a 0..1 fraction down the card.
  final void Function(double fraction) onLongPressAt;

  @override
  Widget build(BuildContext context) {
    final t = neo(context);
    final acts = slice.block.activities;
    final color = acts.isEmpty ? t.muted : parseHexColor(acts.first.color);
    final label = acts.isEmpty ? '(empty)' : acts.map((a) => a.name).join('  +  ');
    final height = (slice.endMinutes - slice.startMinutes) * _pxPerMinute;

    return LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        onTap: onTap,
        onLongPressStart: (d) => onLongPressAt(
          (d.localPosition.dy / constraints.maxHeight).clamp(0.0, 1.0),
        ),
        behavior: HitTestBehavior.opaque,
        child: Container(
          decoration: BoxDecoration(
            color: color.withValues(alpha: .35),
            border: Border(
              left: BorderSide(color: color, width: 6),
              top: BorderSide(
                color: t.line,
                // A midnight clip is not a real boundary — draw it faint so it
                // does not read as something draggable.
                width: slice.continuesBefore ? 1 : 3,
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          // A block of a few minutes gets a card shorter than its text; ClipRect
          // trims it to a colour bar that is still tappable.
          child: ClipRect(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: mono(context, size: 11, weight: FontWeight.w800),
                ),
                // Only worth laying out when there is room for a second line.
                if (height >= 26)
                  Text(
                    '${formatTimeOfDay(slice.start)}–${slice.block.isOpen ? "now" : formatTimeOfDay(slice.end)}'
                    ' · ${formatDurationHm(slice.duration)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mono(context, size: 10, color: t.muted),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The draggable bar sitting on a boundary between two blocks.
class _BoundaryHandle extends StatelessWidget {
  const _BoundaryHandle({
    required this.label,
    required this.dragging,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
  });

  final String label;
  final bool dragging;
  final VoidCallback onStart;
  final void Function(double dy) onUpdate;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final t = neo(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (_) => onStart(),
      onVerticalDragUpdate: (d) => onUpdate(d.delta.dy),
      onVerticalDragEnd: (_) => onEnd(),
      onVerticalDragCancel: onEnd,
      child: Center(
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              color: dragging ? t.brand : t.line,
              child: Text(
                dragging ? label : '⇕',
                style: mono(
                  context,
                  size: 9,
                  weight: FontWeight.w800,
                  color: dragging ? t.brandInk : t.surface,
                ),
              ),
            ),
            Expanded(child: Container(height: 3, color: dragging ? t.brand : t.line)),
          ],
        ),
      ),
    );
  }
}
