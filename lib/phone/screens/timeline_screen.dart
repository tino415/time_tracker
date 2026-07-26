import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../domain/block.dart';
import '../../format.dart';
import '../widgets/activity_picker.dart';
import '../widgets/neo.dart';

/// The timeline: derived blocks newest-first, grouped by local day. Tap a block
/// to tag it with another activity (the forgot-to-switch case), edit its note,
/// or delete the boundary (merging the adjacent blocks).
class TimelineScreen extends ConsumerWidget {
  const TimelineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = neo(context);
    final blocks = ref.watch(blocksProvider);

    if (blocks.isEmpty) {
      return Center(
        child: Text('no history yet', style: mono(context, color: t.muted)),
      );
    }

    return SecondTicker(
      builder: (context, now) {
        // Group by local calendar day of the block's start (newest first).
        final rows = <Widget>[];
        DateTime? lastDay;
        for (final b in blocks) {
          final day = DateTime(b.start.year, b.start.month, b.start.day);
          if (lastDay == null || day != lastDay) {
            rows.add(Padding(
              padding: EdgeInsets.only(top: lastDay == null ? 0 : 18, bottom: 10),
              child: NeoChip(_dayLabel(day, now)),
            ));
            lastDay = day;
          }
          rows.add(Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _BlockCard(block: b, now: now),
          ));
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          children: rows,
        );
      },
    );
  }

  static String _dayLabel(DateTime day, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${days[day.weekday - 1]} ${day.day}/${day.month}';
  }
}

class _BlockCard extends ConsumerWidget {
  const _BlockCard({required this.block, required this.now});
  final Block block;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = neo(context);
    final acts = block.activities;
    final multi = acts.length > 1;
    final range = block.isOpen
        ? '${formatTimeOfDay(block.start)} – now'
        : '${formatTimeOfDay(block.start)} – ${formatTimeOfDay(block.end!)}';

    return NeoPressable(
      onTap: () => _showBlockActions(context, ref, block),
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
                        Text(formatDurationHm(block.duration(now)),
                            style: mono(context, weight: FontWeight.w800)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(range, style: mono(context, size: 11, color: t.muted)),
                        if (block.isOpen) ...[
                          const SizedBox(width: 8),
                          Text('● open', style: mono(context, size: 11, weight: FontWeight.w700, color: t.brand)),
                        ],
                      ],
                    ),
                    if (multi) ...[
                      const SizedBox(height: 6),
                      Text('forgot to switch · even-split ${formatDurationHm(Duration(microseconds: block.duration(now).inMicroseconds ~/ acts.length))} each',
                          style: mono(context, size: 10, weight: FontWeight.w700, color: t.muted)),
                    ],
                    if (block.comment != null && block.comment!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text('✎ ${block.comment}',
                          maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: mono(context, size: 12, weight: FontWeight.w700)),
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
      decoration: BoxDecoration(border: Border(right: BorderSide(color: t.line, width: 3))),
      child: Column(
        children: [for (final c in cs) Expanded(child: Container(color: c))],
      ),
    );
  }
}

Future<void> _showBlockActions(BuildContext context, WidgetRef ref, Block block) async {
  final t = neo(context);
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => Container(
      margin: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: t.bg, border: Border.all(color: t.line, width: 3)),
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NeoChip('Block · ${block.activities.map((a) => a.name).join(", ")}'),
          const SizedBox(height: 14),
          NeoButton(
            label: '+ tag another activity',
            onTap: () async {
              Navigator.pop(sheetContext);
              final id = await showActivityPicker(
                context,
                ref,
                title: 'Tag with activity',
                exclude: block.activities.map((a) => a.syncId).toSet(),
              );
              if (id != null) {
                await ref.read(changeRepositoryProvider).addActivityToChange(block.change.syncId, id);
              }
            },
          ),
          if (block.activities.length > 1) ...[
            const SizedBox(height: 10),
            NeoButton(
              label: '- untag an activity',
              onTap: () async {
                Navigator.pop(sheetContext);
                final id = await showActivityPicker(
                  context,
                  ref,
                  title: 'Remove which activity',
                );
                if (id != null) {
                  await ref.read(changeRepositoryProvider).removeActivityFromChange(block.change.syncId, id);
                }
              },
            ),
          ],
          const SizedBox(height: 10),
          NeoButton(
            label: 'delete boundary (merge)',
            onTap: () async {
              Navigator.pop(sheetContext);
              await ref.read(changeRepositoryProvider).deleteChange(block.change.syncId);
            },
          ),
        ],
      ),
    ),
  );
}
