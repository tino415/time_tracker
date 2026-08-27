import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/tracker_controller.dart';
import '../../domain/block.dart';
import '../../domain/calendar.dart';
import '../../format.dart';
import '../screens/now_screen.dart' show DottedField;
import 'neo.dart';

/// Retime the boundary that opens [block] — "I actually started this at 09:15".
///
/// The calendar already moves the same value by dragging, which is the right
/// gesture when the whole day is on screen. This is the version for the block
/// you are looking at: nudges for the usual "a few minutes ago", typing for a
/// correction big enough that nudging would be silly.
Future<void> editBlockStart(BuildContext context, WidgetRef ref, Block block) async {
  await showNeoSheet<void>(context, (_) => _StartSheet(block: block));
}

class _StartSheet extends ConsumerStatefulWidget {
  const _StartSheet({required this.block});
  final Block block;

  @override
  ConsumerState<_StartSheet> createState() => _StartSheetState();
}

class _StartSheetState extends ConsumerState<_StartSheet> {
  final _typed = TextEditingController();

  /// Captured once. The upper bound for the running block is the present, and
  /// letting it advance under the sheet would make the preview drift while you
  /// are reading it. Committing later only ever widens the window, so a value
  /// legal here stays legal at [TrackerController.moveBoundary].
  final _openedAt = DateTime.now();

  late DateTime _start = widget.block.start;

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  /// The boundary before this one, which the new start may not cross.
  DateTime? _previousBoundary(List<Block> blocks, int index) =>
      index >= 0 && index + 1 < blocks.length ? blocks[index + 1].start : null;

  void _apply(DateTime? desired, {DateTime? previous, DateTime? next}) {
    if (desired == null) return;
    final target = clampBoundary(
      desired: desired,
      previous: previous,
      next: next,
      notAfter: _openedAt,
    );
    // Null means the neighbours leave no legal room at all — the same no-op the
    // calendar drag takes.
    if (target == null) return;
    setState(() => _start = target);
  }

  Future<void> _save() async {
    await ref.read(trackerControllerProvider).moveBoundary(widget.block.change.syncId, _start);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = neo(context);

    // Re-read the block from the live list: the boundary either side may have
    // moved (a relayed switch from the watch) since the sheet was opened.
    final blocks = ref.watch(blocksProvider);
    final index = blocks.indexWhere((b) => b.change.syncId == widget.block.change.syncId);
    final live = index >= 0 ? blocks[index] : widget.block;
    final previous = _previousBoundary(blocks, index);
    final next = live.end;

    final ends = next ?? _openedAt;
    final earliest = previous?.add(const Duration(minutes: 1));
    final latest = (next ?? _openedAt).subtract(const Duration(minutes: 1));

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
                  NeoChip('Started at'),
                  const Spacer(),
                  Text(
                    live.activities.map((a) => a.name).join('  +  '),
                    style: mono(context, size: 11, weight: FontWeight.w700, color: t.muted),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    formatTimeOfDay(_start),
                    style: mono(context, size: 38, weight: FontWeight.w800, height: 1),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '→ ${formatDurationHm(ends.difference(_start))}',
                    style: mono(context, size: 13, weight: FontWeight.w700, color: t.muted),
                  ),
                ],
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
                          onTap: () => _apply(
                            _start.add(Duration(minutes: m)),
                            previous: previous,
                            next: next,
                          ),
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
                hint: 'or type a time, e.g. ${formatTimeOfDay(_start)}',
                onSubmitted: (v) {
                  _apply(
                    parseTimeOfDay(v, onDay: live.start),
                    previous: previous,
                    next: next,
                  );
                  _typed.clear();
                },
              ),
              const SizedBox(height: 8),
              Text(
                _window(earliest, latest),
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
                    child: NeoButton(label: 'save', primary: true, shadowOffset: 3, onTap: _save),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Why the nudges stop where they do. A boundary cannot cross its neighbours,
  /// and the running block's end is the present.
  String _window(DateTime? earliest, DateTime? latest) {
    final from = earliest == null ? null : 'no earlier than ${formatTimeOfDay(earliest)}';
    final to = latest == null ? null : 'no later than ${formatTimeOfDay(latest)}';
    if (from != null && to != null) return '$from · $to';
    return from ?? to ?? '';
  }
}
