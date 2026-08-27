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

/// Which week the report is showing: 0 = this week, -1 = last week, …
///
/// Lifted out of the screen's own state so a keyboard shortcut can move it. The
/// screen stays alive inside an `IndexedStack` and holds no focus of its own, so
/// its `State` is not reachable from the app shell where the bindings live.
final weekOffsetProvider = StateProvider<int>((_) => 0);

/// Which day inside the shown week the report is scoped to; null = the week.
///
/// A day only means anything inside the week it belongs to, so stepping the week
/// clears it.
final reportDayProvider = StateProvider<DateTime?>((_) => null);

/// Step the report week, refusing to walk into the future.
///
/// The guard lives here rather than in the button, so the keyboard and the
/// arrows cannot disagree about where the report ends.
void shiftReportWeek(WidgetRef ref, int delta) {
  final next = ref.read(weekOffsetProvider) + delta;
  if (next > 0) return;
  ref.read(weekOffsetProvider.notifier).state = next;
  ref.read(reportDayProvider.notifier).state = null;
}

/// Weekly report: a stacked bar per day of the week, rolled-up horizontal bars
/// per top-level category that **drill down into their sub-activities**, and a
/// client-side CSV export (optionally subtree-filtered).
///
/// The two sections are linked: tapping a day scopes the category bars to it,
/// which is the question a day row provokes ("what was Tuesday made of?") and,
/// on today's row, gives a day report without a second range control.
///
/// The drill-down is the point of a hierarchical catalogue: `Work > Payout >
/// CU-1042` means "how much did I work for Payout" is a question about a middle
/// node, and a roots-only report cannot answer it.
///
/// There is deliberately no hero total. Tracking never stops here — every moment
/// between two boundaries belongs to some block — so "time tracked this week"
/// only ever reported *how many hours the week has*: 168 for a past week, or
/// hours-elapsed for the current one. It carried no information and took the
/// most prominent position on the screen. The bars lead instead.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  /// Which rows are drilled open, by activity id. Deliberately kept across week
  /// changes: the question ("how much for Payout?") outlives the week you happen
  /// to be looking at, so stepping back a week should keep the same view open.
  final _expanded = <String>{};

  @override
  Widget build(BuildContext context) {
    final t = neo(context);
    final blocks = ref.watch(blocksProvider);
    final tree = ref.watch(activityTreeProvider);
    final now = DateTime.now();

    final weekOffset = ref.watch(weekOffsetProvider);
    final base = DateTime(now.year, now.month, now.day + weekOffset * 7);
    final week = localWeekRange(base);
    final day = ref.watch(reportDayProvider);

    final days = dailyTotals(
      blocks: blocks,
      tree: tree,
      rangeStart: week.start,
      rangeEnd: week.end,
      now: now,
    );

    // The category section follows the day selection; the day bars keep
    // describing the whole week, so the row you tapped does not resize under
    // your finger.
    final scope = day == null ? week : localDayRange(day);
    final totals = reportTotals(
      blocks: blocks,
      tree: tree,
      rangeStart: scope.start,
      rangeEnd: scope.end,
      now: now,
    );

    // Sorted largest first, so the widest bar is always the level's first row.
    final roots = _tracked(totals, tree.rootIds);
    final maxRoot = roots.isEmpty ? Duration.zero : totals.subtreeOf(roots.first);
    final drillable = roots.any((id) => _tracked(totals, tree.childrenOf(id)).isNotEmpty);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        _WeekSelector(
          label: _weekLabel(week.start, now),
          onPrev: () => shiftReportWeek(ref, -1),
          onNext: weekOffset < 0 ? () => shiftReportWeek(ref, 1) : null,
        ),
        const SizedBox(height: 18),
        ..._dayRows(tree, days, selected: day),
        NeoSectionHeader(
          day == null ? 'Per category' : 'Per category · ${formatWeekdayDay(day)}',
          brand: true,
          trailing: drillable
              ? Text('tap to drill in',
                  style: mono(context, size: 10, weight: FontWeight.w700, color: t.muted))
              : null,
        ),
        const SizedBox(height: 12),
        if (roots.isEmpty)
          // An empty state, not a zero total: with continuous tracking the only
          // way to reach it is a range that holds no data at all.
          Text(
            day == null ? 'nothing tracked this week' : 'nothing tracked on ${formatWeekdayDay(day)}',
            style: mono(context, color: t.muted),
          )
        else
          ..._rows(tree, totals, roots, max: maxRoot, depth: 0),
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

  /// The per-day section: one stacked bar per day the week has reached, tappable
  /// to scope the rest of the screen to that day.
  ///
  /// Segments are ordered and coloured by the **week's** category ranking, not
  /// each day's own, so a category keeps its place in every bar and the seven
  /// rows can be compared down the column instead of row by row.
  List<Widget> _dayRows(ActivityTree tree, List<DayTotals> days, {required DateTime? selected}) {
    final byRoot = <String, Duration>{};
    var busiest = Duration.zero;
    for (final day in days) {
      day.byRoot.forEach((id, d) => byRoot[id] = (byRoot[id] ?? Duration.zero) + d);
      if (day.total > busiest) busiest = day.total;
    }
    if (byRoot.isEmpty) return const [];

    final ranked = byRoot.keys.toList()..sort((a, b) => byRoot[b]!.compareTo(byRoot[a]!));

    return [
      NeoSectionHeader(
        'Per day',
        trailing: Text(
          selected == null ? 'tap to scope' : 'tap again to clear',
          style: mono(context, size: 10, weight: FontWeight.w700, color: neo(context).muted),
        ),
      ),
      const SizedBox(height: 12),
      for (final day in days)
        _DayBar(
          label: formatWeekdayDay(day.day),
          segments: [
            for (final id in ranked)
              if (day.of(id) > Duration.zero)
                (color: parseHexColor(tree[id]?.color ?? ''), duration: day.of(id)),
          ],
          total: day.total,
          max: busiest,
          selected: day.day == selected,
          onTap: () => ref.read(reportDayProvider.notifier).state =
              day.day == selected ? null : day.day,
        ),
      const SizedBox(height: 18),
    ];
  }

  /// One level of the drill-down: a bar per id in [ids], and — under any that is
  /// open — the rows for its children.
  ///
  /// [max] scales this level's bars: the largest root for the top level, and
  /// otherwise the parent's own total. So a child's bar is its **share of the
  /// row above it** — the level's bars fill their parent's bar between them —
  /// rather than its share of the week, which at depth 3 would be a sliver.
  List<Widget> _rows(
    ActivityTree tree,
    ReportTotals totals,
    List<String> ids, {
    required Duration max,
    required int depth,
  }) {
    final out = <Widget>[];
    for (final id in ids) {
      final activity = tree[id]!;
      final children = _tracked(totals, tree.childrenOf(id));
      final open = _expanded.contains(id);

      out.add(_ReportBar(
        label: activity.name,
        color: parseHexColor(activity.color),
        value: totals.subtreeOf(id),
        max: max,
        depth: depth,
        expanded: open,
        onTap: children.isEmpty
            ? null
            : () => setState(() => open ? _expanded.remove(id) : _expanded.add(id)),
      ));

      if (!open || children.isEmpty) continue;

      // Time booked on the node itself belongs to this level too, or the
      // children would visibly fail to add up to their parent.
      final direct = totals.directOf(id);
      final childMax = totals.subtreeOf(id);

      if (direct > Duration.zero) {
        out.add(_ReportBar(
          label: 'direct',
          color: parseHexColor(activity.color),
          value: direct,
          max: childMax,
          depth: depth + 1,
          muted: true,
        ));
      }
      out.addAll(_rows(tree, totals, children, max: childMax, depth: depth + 1));
    }
    return out;
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
        const SizedBox(height: 4),
        const _SyncBackendLine(),
      ],
    );
  }
}

/// Which server this device syncs with, next to the build stamp for the same
/// reason: two devices that disagree are usually not talking to the same place,
/// and until now the only way to know was to remember how each was built.
///
/// The URL is compiled in (`--dart-define=SYNC_URL`), so it cannot be read off
/// the running app any other way — an APK built against a local worker and a web
/// build served from Cloudflare look identical from the inside.
class _SyncBackendLine extends ConsumerWidget {
  const _SyncBackendLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = neo(context);
    final config = ref.watch(syncConfigProvider);

    // The scheme is the same on every build worth comparing and eats a third of
    // a narrow line; the host and path are what actually differ.
    final label = config.hasServer
        ? config.baseUrl!.replaceFirst(RegExp(r'^https?://'), '')
        : 'not configured';

    return Row(
      children: [
        Text('SYNC · ',
            style: mono(context, size: 10, weight: FontWeight.w800, spacing: 1, color: t.muted)),
        Expanded(
          child: SelectableText(
            label,
            maxLines: 1,
            style: mono(
              context,
              size: 10,
              weight: FontWeight.w700,
              // A build with no server at all is the surprising state.
              color: config.hasServer ? t.muted : t.brand,
            ),
          ),
        ),
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

/// The ids in [ids] that have time in the range, largest first — the only ones
/// worth a row. An untracked branch is noise in a report.
List<String> _tracked(ReportTotals totals, List<String> ids) {
  return ids.where((id) => totals.subtreeOf(id) > Duration.zero).toList()
    ..sort((a, b) => totals.subtreeOf(b).compareTo(totals.subtreeOf(a)));
}

/// One day of the week, as a bar segmented by top-level category.
///
/// Stacked rather than a bare total because "what was Tuesday" is the question a
/// day row raises, and answering it in the row itself beats a second screen. It
/// stays legible on a phone only because the days run down the page — seven bars
/// side by side would each be a sliver.
///
/// [max] is the week's busiest day, so bar lengths compare across the section;
/// the unfilled tail is the difference from that day.
class _DayBar extends StatelessWidget {
  const _DayBar({
    required this.label,
    required this.segments,
    required this.total,
    required this.max,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final List<({Color color, Duration duration})> segments;
  final Duration total;
  final Duration max;

  /// This day is what the rest of the screen is scoped to.
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = neo(context);
    // Flex weights in seconds, not microseconds: the ratio is the same and the
    // numbers stay in a range that reads in a debugger.
    final weights = [for (final s in segments) s.duration.inSeconds < 1 ? 1 : s.duration.inSeconds];
    final rest = max.inSeconds - weights.fold<int>(0, (a, b) => a + b);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // The same fixed slot the category rows use, so both sections'
                // labels start on one line.
                SizedBox(
                  width: 16,
                  child: Text(selected ? '▾' : '▸',
                      style: mono(context, size: 14, weight: FontWeight.w800, color: t.muted)),
                ),
                Expanded(
                  child: Text(label,
                      style: mono(
                        context,
                        size: 14,
                        weight: FontWeight.w700,
                        color: selected ? t.brand : t.ink,
                      )),
                ),
                Text(formatDurationHm(total),
                    style: mono(context, size: 14, weight: FontWeight.w800, color: t.ink)),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              height: 20,
              decoration: BoxDecoration(
                color: t.surface2,
                border: Border.all(color: selected ? t.brand : t.line, width: 3),
              ),
              child: Row(
                // Childless colour boxes measure zero high; stretching them fills
                // the bar.
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < segments.length; i++)
                    Expanded(flex: weights[i], child: ColoredBox(color: segments[i].color)),
                  if (rest > 0) Expanded(flex: rest, child: const SizedBox.shrink()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One labelled bar in the drill-down. Deeper rows are indented and rendered a
/// size down, so the level a number belongs to is readable without a legend.
class _ReportBar extends StatelessWidget {
  const _ReportBar({
    required this.label,
    required this.color,
    required this.value,
    required this.max,
    required this.depth,
    this.onTap,
    this.expanded = false,
    this.muted = false,
  });

  final String label;
  final Color color;
  final Duration value;
  final Duration max;
  final int depth;

  /// Null when the row has nothing to drill into.
  final VoidCallback? onTap;
  final bool expanded;

  /// The synthetic "time on this node itself" row, which is a remainder rather
  /// than an activity of its own.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final t = neo(context);
    final frac = max.inMicroseconds == 0 ? 0.0 : value.inMicroseconds / max.inMicroseconds;
    final root = depth == 0;
    final size = root ? 14.0 : 12.0;
    final ink = muted ? t.muted : t.ink;

    return Padding(
      padding: EdgeInsets.only(left: depth * 14.0, bottom: root ? 12 : 8),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // A fixed slot, so labels line up whether or not a row drills.
                SizedBox(
                  width: 16,
                  child: Text(
                    onTap == null ? '' : (expanded ? '▾' : '▸'),
                    style: mono(context, size: size, weight: FontWeight.w800, color: t.muted),
                  ),
                ),
                Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mono(context, size: size, weight: FontWeight.w700, color: ink)),
                ),
                Text(formatDurationHm(value),
                    style: mono(context, size: size, weight: FontWeight.w800, color: ink)),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              height: root ? 22 : 16,
              decoration: BoxDecoration(
                color: t.surface2,
                border: Border.all(color: t.line, width: root ? 3 : 2),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: frac.clamp(0.0, 1.0),
                child: Container(color: color),
              ),
            ),
          ],
        ),
      ),
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
    scope = await showNeoSheet<String>(
      context,
      (sheet) {
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
