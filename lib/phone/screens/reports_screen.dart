import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../build_info.dart';
import '../../data/providers.dart';
import '../../data/sync_service.dart';
import '../../data/sync_transport.dart';
import '../../domain/activity_tree.dart';
import '../../domain/block.dart';
import '../../domain/csv_export.dart';
import '../../domain/reporting.dart';
import '../../format.dart';
import '../widgets/activity_picker.dart';
import '../widgets/neo.dart';
import '../widgets/sync_setup.dart';

/// Weekly per-category report: a hero total, rolled-up horizontal bars per
/// top-level category, and a client-side CSV export (optionally subtree-filtered).
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  int _weekOffset = 0; // 0 = current week, -1 = last week, …

  @override
  Widget build(BuildContext context) {
    final t = neo(context);
    final blocks = ref.watch(blocksProvider);
    final tree = ref.watch(activityTreeProvider);
    final now = DateTime.now();

    final base = DateTime(now.year, now.month, now.day + _weekOffset * 7);
    final week = localWeekRange(base);

    final totals = rollUpTotals(
      blocks: blocks,
      tree: tree,
      rangeStart: week.start,
      rangeEnd: week.end,
      now: now,
    );

    // Total tracked in-range (independent of activities), for the hero stat.
    var totalMicros = 0;
    for (final b in blocks) {
      final end = b.end ?? now;
      final s = b.start.isAfter(week.start) ? b.start : week.start;
      final e = end.isBefore(week.end) ? end : week.end;
      if (e.isAfter(s)) totalMicros += e.difference(s).inMicroseconds;
    }
    final total = Duration(microseconds: totalMicros);

    final roots = tree.rootIds.where((id) => (totals[id] ?? Duration.zero) > Duration.zero).toList()
      ..sort((a, b) => (totals[b] ?? Duration.zero).compareTo(totals[a] ?? Duration.zero));
    final maxRoot = roots.isEmpty
        ? Duration.zero
        : roots.map((id) => totals[id]!).reduce((a, b) => a > b ? a : b);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        _WeekSelector(
          label: _weekLabel(week.start, now),
          onPrev: () => setState(() => _weekOffset--),
          onNext: _weekOffset < 0 ? () => setState(() => _weekOffset++) : null,
        ),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            color: t.brand,
            border: Border.all(color: t.line, width: 3),
            boxShadow: t.hardShadow(8),
          ),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('TRACKED THIS WEEK',
                  style: mono(context, size: 11, weight: FontWeight.w800, spacing: 1.2, color: t.brandInk)),
              const SizedBox(height: 8),
              Text(formatDurationHm(total),
                  style: mono(context, size: 34, weight: FontWeight.w800, color: t.brandInk, height: 1)),
            ],
          ),
        ),
        const SizedBox(height: 18),
        NeoSectionHeader('Per category'),
        const SizedBox(height: 12),
        if (roots.isEmpty)
          Text('nothing tracked this week', style: mono(context, color: t.muted))
        else
          for (final id in roots)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _CategoryBar(
                label: tree[id]!.name,
                color: parseHexColor(tree[id]!.color),
                value: totals[id]!,
                max: maxRoot,
              ),
            ),
        const SizedBox(height: 18),
        NeoButton(
          label: '↧ export csv · all history',
          icon: null,
          primary: true,
          onTap: () => _exportCsv(context, ref, blocks, tree, now),
        ),
        const SizedBox(height: 10),
        const _SyncAction(),
        const SizedBox(height: 14),
        const _StorageLine(),
      ],
    );
  }

  static String _weekLabel(DateTime weekStart, DateTime now) {
    final end = DateTime(weekStart.year, weekStart.month, weekStart.day + 6);
    final thisWeek = localWeekRange(now).start;
    if (weekStart == thisWeek) return 'This week';
    return '${weekStart.day}/${weekStart.month} – ${end.day}/${end.month}';
  }
}

/// Manual sync. Hidden entirely when no backend is configured — sync is
/// optional, and an action that cannot work is worse than no action.
///
/// Manual rather than a background loop, because the local database is
/// authoritative: syncing is how devices *agree*, not how the app works, so its
/// failure has to be inert and its timing the user's business.
class _SyncAction extends ConsumerStatefulWidget {
  const _SyncAction();

  @override
  ConsumerState<_SyncAction> createState() => _SyncActionState();
}

class _SyncActionState extends ConsumerState<_SyncAction> {
  bool _running = false;
  String? _status;

  Future<void> _sync(SyncService service) async {
    setState(() {
      _running = true;
      _status = null;
    });
    try {
      final result = await service.syncNow();
      if (!mounted) return;
      setState(() {
        _status = '↑${result.pushed} ↓${result.pulled}'
            '${result.rejected > 0 ? " · ${result.rejected} superseded" : ""}';
      });
    } on SyncException catch (e) {
      if (!mounted) return;
      setState(() {
        // Being offline is the normal state for this app, not a failure worth
        // alarming about; a bad token is worth naming, because only the user
        // can fix it.
        _status = e.unauthorized ? 'token rejected' : 'offline';
      });
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = neo(context);
    // No server in this build: nothing to offer, so offer nothing.
    if (!ref.watch(syncConfigProvider).hasServer) return const SizedBox.shrink();

    final service = ref.watch(syncServiceProvider);
    // A server but no account — sync is opt-in, and this is the invitation.
    if (service == null) {
      return NeoButton(
        label: '⟳ set up sync',
        shadowOffset: 3,
        onTap: () => showSyncSetup(context, ref),
      );
    }

    return Row(
      children: [
        Expanded(
          child: NeoButton(
            label: _running ? '⟳ syncing…' : '⟳ sync now',
            shadowOffset: 3,
            onTap: _running ? null : () => _sync(service),
          ),
        ),
        const SizedBox(width: 8),
        NeoButton(
          label: '⚙',
          shadowOffset: 3,
          compact: true,
          onTap: () => showSyncSetup(context, ref),
        ),
        if (_status != null) ...[
          const SizedBox(width: 10),
          Text(_status!, style: mono(context, size: 11, weight: FontWeight.w700, color: t.muted)),
        ],
      ],
    );
  }
}

/// Where the data actually lives. "Offline-first" is a promise the user should
/// be able to check, and on the web it is not guaranteed — a browser can evict
/// an origin's storage unless it has granted persistence.
class _StorageLine extends ConsumerWidget {
  const _StorageLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = neo(context);
    final status = ref.watch(storageStatusProvider).valueOrNull;
    if (status == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('LOCAL DB · ',
                style: mono(context, size: 10, weight: FontWeight.w800, spacing: 1, color: t.muted)),
            Expanded(
              child: Text(
                status.summary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mono(
                  context,
                  size: 10,
                  weight: FontWeight.w700,
                  // Evictable storage is the one state worth looking at.
                  color: status.persistent ? t.muted : t.brand,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // So "which version is on this device?" is answerable by looking, rather
        // than by inferring from what was last installed.
        Text('BUILD · $kBuildId',
            style: mono(context, size: 10, weight: FontWeight.w700, color: t.muted)),
      ],
    );
  }
}

class _WeekSelector extends StatelessWidget {
  const _WeekSelector({required this.label, required this.onPrev, this.onNext});
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

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({required this.label, required this.color, required this.value, required this.max});
  final String label;
  final Color color;
  final Duration value;
  final Duration max;

  @override
  Widget build(BuildContext context) {
    final t = neo(context);
    final frac = max.inMicroseconds == 0 ? 0.0 : value.inMicroseconds / max.inMicroseconds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: mono(context, weight: FontWeight.w700))),
            Text(formatDurationHm(value), style: mono(context, weight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          height: 22,
          decoration: BoxDecoration(color: t.surface2, border: Border.all(color: t.line, width: 3)),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: frac.clamp(0.0, 1.0),
            child: Container(color: color),
          ),
        ),
      ],
    );
  }
}

Future<void> _exportCsv(
  BuildContext context,
  WidgetRef ref,
  List<Block> blocks,
  ActivityTree tree,
  DateTime now,
) async {
  // Optional subtree filter: null scope = everything.
  String? scope = '__all__';
  if (tree.rootIds.isNotEmpty) {
    scope = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheet) {
        final t = neo(sheet);
        return Container(
          margin: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: t.bg, border: Border.all(color: t.line, width: 3)),
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NeoChip('Export scope'),
              const SizedBox(height: 12),
              NeoButton(label: 'all activities', onTap: () => Navigator.pop(sheet, '__all__')),
              const SizedBox(height: 10),
              NeoButton(
                label: 'a subtree…',
                onTap: () async {
                  final id = await showActivityPicker(context, ref, title: 'Export which subtree');
                  if (context.mounted) Navigator.pop(sheet, id);
                },
              ),
            ],
          ),
        );
      },
    );
  }
  if (scope == null) return; // dismissed

  final subtreeRootId = scope == '__all__' ? null : scope;
  final csv = buildCsv(
    blocks: blocks,
    tree: tree,
    now: now,
    subtreeRootId: subtreeRootId,
  );
  final name = csvFileName(
    now,
    scopeName: subtreeRootId == null ? null : tree[subtreeRootId]?.name,
  );

  // A real file via the platform share sheet (Android/iOS/desktop); on web
  // share_plus falls back to a browser download when the Web Share API can't
  // take files. If no share target exists at all, fall back to the clipboard so
  // the export is never a dead end.
  try {
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            Uint8List.fromList(utf8.encode(csv)),
            mimeType: 'text/csv',
            name: name,
          ),
        ],
        fileNameOverrides: [name],
        subject: name,
      ),
    );
  } catch (_) {
    await Clipboard.setData(ClipboardData(text: csv));
    if (!context.mounted) return;
    await _showCsvPreview(context, csv);
  }
}

Future<void> _showCsvPreview(BuildContext context, String csv) {
  final t = neo(context);
  final rowCount = csv.trim().split('\n').length - 1;
  return showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: t.surface,
      shape: RoundedRectangleBorder(side: BorderSide(color: t.line, width: 3), borderRadius: BorderRadius.zero),
      title: Text('CSV · $rowCount rows', style: mono(context, weight: FontWeight.w800)),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: SelectableText(csv, style: mono(context, size: 11)),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('COPIED ✓ DONE', style: mono(context, weight: FontWeight.w800, color: t.brand)),
        ),
      ],
    ),
  );
}
