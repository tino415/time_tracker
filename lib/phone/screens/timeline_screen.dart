import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/pointer_signal.dart';
import '../../data/providers.dart';
import '../../data/tracker_controller.dart';
import '../../domain/block.dart';
import '../../domain/calendar.dart';
import '../../format.dart';
import '../widgets/block_actions.dart';
import '../widgets/neo.dart';
import 'calendar_screen.dart';

/// Which timeline representation is showing. The list is the reading view; the
/// calendar is the editing view (drag boundaries, split, merge).
final timelineViewProvider = StateProvider<bool>((_) => false); // true = calendar

/// The timeline: derived blocks newest-first, grouped by local day, with a
/// toggle to the calendar edit view. Tap a block to tag it with another activity
/// (the forgot-to-switch case), edit its note, or merge it into the previous
/// block.
class TimelineScreen extends ConsumerWidget {
  const TimelineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final calendar = ref.watch(timelineViewProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: _ViewToggle(
            calendar: calendar,
            onChanged: (v) => ref.read(timelineViewProvider.notifier).state = v,
          ),
        ),
        Expanded(child: calendar ? const CalendarScreen() : const _TimelineList()),
      ],
    );
  }
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.calendar, required this.onChanged});
  final bool calendar;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: NeoButton(
            label: '≣ list',
            primary: !calendar,
            shadowOffset: 3,
            onTap: () => onChanged(false),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: NeoButton(
            label: '▦ calendar',
            primary: calendar,
            shadowOffset: 3,
            onTap: () => onChanged(true),
          ),
        ),
      ],
    );
  }
}

class _TimelineList extends ConsumerWidget {
  const _TimelineList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = neo(context);
    final blocks = ref.watch(blocksProvider);
    final hasPointer = ref.watch(hasPointerProvider);

    if (blocks.isEmpty) {
      return Center(
        child: Text('no history yet', style: mono(context, color: t.muted)),
      );
    }

    return SecondTicker(
      builder: (context, now) {
        // A block crossing midnight appears once under each day it touches, so
        // the rows group by the slice's day, not the block's.
        final rows = <Widget>[];
        DateTime? lastDay;
        for (final s in sliceByLocalDay(blocks, now)) {
          final day = DateTime(s.start.year, s.start.month, s.start.day);
          if (lastDay == null || day != lastDay) {
            rows.add(
              Padding(
                padding: EdgeInsets.only(top: lastDay == null ? 0 : 18, bottom: 10),
                child: NeoChip(_dayLabel(day, now)),
              ),
            );
            lastDay = day;
          }
          rows.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              // Blocks are newest-first, so the last one is the earliest — it has
              // no preceding boundary to merge into.
              child: _BlockCard(slice: s, now: now, canMerge: s.block != blocks.last),
            ),
          );
        }
        final list = ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: rows);
        // Only the list, not `TimelineScreen` as a whole: the calendar this
        // toggles to spends drags on retiming and long-press on splitting, so
        // wrapping the screen instead of this widget would hand it a selection
        // gesture on top of gestures it already needs for something else.
        return hasPointer ? SelectionArea(child: list) : list;
      },
    );
  }

  static String _dayLabel(DateTime day, DateTime now) {
    final relative = todayOrYesterday(day, now);
    if (relative != null) return relative;
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${days[day.weekday - 1]} ${day.day}/${day.month}';
  }
}

class _BlockCard extends ConsumerWidget {
  const _BlockCard({required this.slice, required this.now, this.canMerge = true});
  final bool canMerge;

  /// The day's share of a block. The card *shows* the slice — its range and its
  /// duration — but every action goes to [DaySlice.block], whole.
  final DaySlice slice;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = neo(context);
    final block = slice.block;
    final acts = block.activities;
    final multi = acts.length > 1;
    // The open block's final slice runs to the present; its earlier slices (and
    // every closed block's) end where the next day or block starts.
    final openEnd = block.isOpen && !slice.continuesAfter;
    final range = openEnd
        ? '${formatTimeOfDay(slice.start)} – now'
        : '${formatTimeOfDay(slice.start)} – ${formatTimeOfDay(slice.end)}';

    return NeoPressable(
      onTap: () => showBlockActions(context, ref, block, canMerge: canMerge),
      shadowOffset: 5,
      padding: EdgeInsets.zero,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ColourRail(colors: [for (final a in acts) parseHexColor(a.color)]),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            acts.isEmpty ? '(empty)' : acts.map((a) => a.name).join('  +  '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: mono(context, weight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          formatSpan(slice.duration),
                          style: mono(context, weight: FontWeight.w800),
                        ),
                        // Resume, one tap, without opening anything. A visible
                        // control rather than a swipe: there is no swipe on a
                        // mouse, and a gesture nobody sees is not an affordance.
                        //
                        // Nothing to resume on the open block — it is already
                        // running — so the slot is simply absent there rather
                        // than disabled.
                        if (!block.isOpen && acts.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          _ResumeButton(block: block),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(range, style: mono(context, size: 11, color: t.muted)),
                        if (openEnd) ...[
                          const SizedBox(width: 8),
                          Text(
                            '● open',
                            style: mono(context, size: 11, weight: FontWeight.w700, color: t.brand),
                          ),
                        ],
                      ],
                    ),
                    if (multi) ...[
                      const SizedBox(height: 6),
                      Text(
                        // The slice's share, not the block's: reports clip to
                        // the day before splitting evenly, so this is the very
                        // number the day's report attributes to each activity.
                        'forgot to switch · even-split ${formatSpan(Duration(microseconds: slice.duration.inMicroseconds ~/ acts.length))} each',
                        style: mono(context, size: 10, weight: FontWeight.w700, color: t.muted),
                      ),
                    ],
                    if (block.comment != null && block.comment!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        '✎ ${block.comment}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: mono(context, size: 12, weight: FontWeight.w700),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Track this again" on a timeline row.
///
/// Its own gesture detector inside the card's, so a tap here resumes instead of
/// opening the edit sheet the rest of the card opens. `Semantics(button:)` is
/// what gives it a label a browser test — and a screen reader — can find, since
/// the glyph carries no text of its own.
class _ResumeButton extends ConsumerWidget {
  const _ResumeButton({required this.block});

  final Block block;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = neo(context);
    return Semantics(
      button: true,
      label: 'track again',
      // Its own node, not an annotation folded into the card's. Without this the
      // label is absorbed by the surrounding pressable and there is nothing a
      // screen reader — or a browser test — can point at.
      container: true,
      child: GestureDetector(
        onTap: () => ref.read(trackerControllerProvider).resumeBlock(block),
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: t.line,
          // Comfortably past a thumb's worth without making the row taller.
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          // The glyph is decoration once the node above is labelled. Left in, it
          // joins that label — the node reads "track again ▶", which is what a
          // screen reader would say and what a text-matching browser check
          // would have to work around.
          child: ExcludeSemantics(
            child: Text(
              '▶',
              style: mono(context, size: 12, weight: FontWeight.w800, color: t.surface),
            ),
          ),
        ),
      ),
    );
  }
}

/// The left rail — one colour, or a vertical split for a multi-activity block.
class _ColourRail extends StatelessWidget {
  const _ColourRail({required this.colors});
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    final t = neo(context);
    final cs = colors.isEmpty ? [t.muted] : colors;
    return Container(
      width: 14,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: t.line, width: 3)),
      ),
      child: Column(
        children: [for (final c in cs) Expanded(child: Container(color: c))],
      ),
    );
  }
}
