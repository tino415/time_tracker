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

/// Pixels per hour at each zoom step, and the drag snap that suits it.
///
/// 56 is the original fixed scale: a whole day is 1344px, two or three flicks,
/// with a 5-minute step at ~4.7px — the comfort threshold the handles were built
/// against. The other steps are halves and doubles of it.
///
/// The snap has to move with the scale or zoom buys nothing for editing. At 56 a
/// 1-minute step is 0.9px, so no amount of care lands on it; at 224 it is 3.7px,
/// close enough to the 4.7px that has always been considered draggable. Going
/// the other way, a zoomed-out axis is for reading a dense day, so it snaps
/// coarsely rather than pretending to a precision the pixels cannot carry.
///
/// Precision is no longer only a drag, either: "split at…" and "edit start time"
/// both take a typed minute, so the axis does not have to be the fine
/// instrument. Its job here is legibility.
const _zoomLevels = <({double hourHeight, Duration snap})>[
  (hourHeight: 28.0, snap: Duration(minutes: 15)),
  (hourHeight: 56.0, snap: Duration(minutes: 5)),
  (hourHeight: 112.0, snap: Duration(minutes: 5)),
  (hourHeight: 224.0, snap: Duration(minutes: 1)),
];

/// The scale the view opens at — the one it always had.
const _defaultZoom = 1;

/// Width of the hour-label gutter on the left.
const _gutter = 44.0;

/// Which day the calendar shows: 0 = today, -1 = yesterday, …
///
/// Lifted out of the screen for the same reason the report's week was: the
/// keyboard steps it, and the screen holds no focus of its own for a binding to
/// be scoped to. The zoom stays local — it has no keyboard route, by decision:
/// the calendar is a pointer surface and zoom belongs to the trackpad.
final calendarDayProvider = StateProvider<int>((_) => 0);

/// Step the day, refusing to walk into the future.
///
/// The guard lives here rather than in the button, so the keyboard and the
/// arrows cannot disagree about where the calendar ends.
void shiftCalendarDay(WidgetRef ref, int delta) {
  final next = ref.read(calendarDayProvider) + delta;
  if (next > 0) return;
  ref.read(calendarDayProvider.notifier).state = next;
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  int _zoom = _defaultZoom;

  /// Needed to keep the same time under the eye across a zoom — without it the
  /// pixel offset means a different hour at the new scale, and zooming in on
  /// the afternoon lands you in the evening.
  final _scroll = ScrollController();

  /// While a handle is held: the boundary being moved and its live time, so the
  /// view can follow the finger before anything is written.
  String? _draggingId;
  DateTime? _dragAt;

  double get _hourHeight => _zoomLevels[_zoom].hourHeight;
  double get _pxPerMinute => _hourHeight / 60.0;
  Duration get _snap => _zoomLevels[_zoom].snap;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Change scale about the middle of what is on screen.
  ///
  /// Anchoring to the viewport centre rather than the top: the top of a scrolled
  /// day is usually empty hours, so holding it still would push whatever you
  /// were looking at off the bottom on the way in.
  void _setZoom(int next) {
    final clamped = next.clamp(0, _zoomLevels.length - 1);
    if (clamped == _zoom) return;

    final ratio = _zoomLevels[clamped].hourHeight / _hourHeight;
    final hasViewport = _scroll.hasClients;
    final centre = hasViewport ? _scroll.offset + _scroll.position.viewportDimension / 2 : 0.0;

    setState(() => _zoom = clamped);

    if (!hasViewport) return;
    // After the frame, or the new extent is not known and the offset is clamped
    // against the old one.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = centre * ratio - _scroll.position.viewportDimension / 2;
      _scroll.jumpTo(target.clamp(0.0, _scroll.position.maxScrollExtent));
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = neo(context);
    final blocks = ref.watch(blocksProvider);
    final now = DateTime.now();
    final dayOffset = ref.watch(calendarDayProvider);
    final day = DateTime(now.year, now.month, now.day + dayOffset);

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
            onPrev: () => shiftCalendarDay(ref, -1),
            onNext: dayOffset < 0 ? () => shiftCalendarDay(ref, 1) : null,
            onZoomOut: _zoom > 0 ? () => _setZoom(_zoom - 1) : null,
            onZoomIn: _zoom < _zoomLevels.length - 1 ? () => _setZoom(_zoom + 1) : null,
          ),
        ),
        Expanded(
          child: slices.isEmpty
              ? Center(
                  child: Text('nothing tracked this day', style: mono(context, color: t.muted)),
                )
              : SingleChildScrollView(
                  controller: _scroll,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: SizedBox(
                      height: 24 * _hourHeight,
                      child: Stack(
                        children: [
                          _HourGrid(hourHeight: _hourHeight),
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
    await ref
        .read(trackerControllerProvider)
        .moveBoundary(s.block.change.syncId, snapTime(at, _snap));
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
        height: height,
        onTap: () => showBlockActions(context, ref, s.block, canMerge: !s.continuesBefore),
        onLongPressAt: (fraction) => _split(s, _timeAtFraction(s, fraction)),
      ),
    );
  }

  /// Split at the point the finger landed, so a long-press on the calendar cuts
  /// exactly where it looks like it will.
  DateTime _timeAtFraction(DaySlice s, double fraction) {
    final span = s.end.difference(s.start).inMilliseconds;
    return snapTime(s.start.add(Duration(milliseconds: (span * fraction).round())), _snap);
  }

  /// The long-press keeps its direct split; the sheet's "split at…" asks for a
  /// time instead. A tall block is quicker to cut by pointing at it, and that is
  /// exactly the case the calendar is good at.
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
  const _DaySelector({
    required this.label,
    required this.onPrev,
    this.onNext,
    this.onZoomOut,
    this.onZoomIn,
  });

  final String label;
  final VoidCallback onPrev;
  final VoidCallback? onNext;
  final VoidCallback? onZoomOut;
  final VoidCallback? onZoomIn;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        NeoButton(label: '‹', onTap: onPrev, shadowOffset: 3, compact: true),
        Expanded(
          child: Center(
            child: Text(label, style: mono(context, weight: FontWeight.w800)),
          ),
        ),
        NeoButton(label: '›', onTap: onNext, shadowOffset: 3, compact: true),
        const SizedBox(width: 10),
        // Buttons rather than a pinch. On the web a pinch arrives as ctrl+wheel,
        // which the browser also reads as page zoom, so it would have to be
        // intercepted rather than merely heard — and on the phone the calendar
        // already spends its drags on boundaries and its long-press on split.
        // Buttons cost two taps and are visible, which a gesture is not.
        NeoButton(label: '−', onTap: onZoomOut, shadowOffset: 3, compact: true),
        NeoButton(label: '+', onTap: onZoomIn, shadowOffset: 3, compact: true),
      ],
    );
  }
}

/// Hour lines + labels behind the blocks.
class _HourGrid extends StatelessWidget {
  const _HourGrid({required this.hourHeight});

  final double hourHeight;

  @override
  Widget build(BuildContext context) {
    final t = neo(context);
    return Stack(
      children: [
        for (var h = 0; h < 24; h++)
          Positioned(
            left: 0,
            right: 0,
            top: h * hourHeight,
            height: hourHeight,
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
                Expanded(child: Container(height: 1, color: t.line.withValues(alpha: .18))),
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
    required this.height,
    required this.onTap,
    required this.onLongPressAt,
  });

  final DaySlice slice;
  final DateTime now;

  /// Passed in rather than recomputed: the axis scale lives in the screen's
  /// state now, and two places deriving it from their own constant is exactly
  /// how the card and the layout would drift apart at anything but 1×.
  final double height;

  final VoidCallback onTap;

  /// Long-press position as a 0..1 fraction down the card.
  final void Function(double fraction) onLongPressAt;

  @override
  Widget build(BuildContext context) {
    final t = neo(context);
    final acts = slice.block.activities;
    final color = acts.isEmpty ? t.muted : parseHexColor(acts.first.color);
    final label = acts.isEmpty ? '(empty)' : acts.map((a) => a.name).join('  +  ');

    return LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        onTap: onTap,
        onLongPressStart: (d) =>
            onLongPressAt((d.localPosition.dy / constraints.maxHeight).clamp(0.0, 1.0)),
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
          // A short block gets a card shorter than one line of text. ClipRect
          // alone is not enough — it trims *painting*, while the Column still
          // lays out at its natural height and asserts. OverflowBox lifts the
          // height constraint so there is nothing to overflow, and the clip then
          // trims what does not fit: a few-minute block degrades to a partial
          // line over a colour bar, still tappable.
          //
          // Hiding the label below a threshold was the alternative. It needs
          // ~23px to fit a line plus padding — 25 minutes at 1×, and a full 50
          // at the zoomed-out step — which would leave a lot of ordinary blocks
          // unlabelled exactly when the day is densest. Zooming in is the answer
          // to a block too short to read, rather than blanking it.
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minHeight: 0,
              maxHeight: double.infinity,
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
