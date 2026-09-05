import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../build_info.dart';
import '../../data/pointer_signal.dart';
import '../../data/providers.dart';
import '../../data/sync_service.dart';
import '../../domain/activity_tree.dart';
import '../../domain/block.dart';
import '../../domain/csv_export.dart';
import '../../domain/reporting.dart';
import '../../format.dart';
import '../widgets/activity_picker.dart';
import '../widgets/neo.dart';

/// Which week the report is showing: 0 = this week, -1 = last week, …
///
/// Lifted out of the screen's own state so a keyboard shortcut can move it. The
/// screen stays alive inside an `IndexedStack` and holds no focus of its own, so
/// its `State` is not reachable from the app shell where the bindings live.
final weekOffsetProvider = StateProvider<int>((_) => 0);

/// The day that day mode is scoped to — an absolute date, not an offset,
/// because it has to survive independently of whichever week
/// [weekOffsetProvider] is on. Starts at today.
final reportDayProvider = StateProvider<DateTime>((_) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

/// Week roll-up or a single day. Same device as `timelineViewProvider`: lifted
/// out of the screen so the `h`/`l` shortcut can read it to decide which of
/// [shiftReportWeek] / [shiftReportDay] applies.
final reportModeProvider = StateProvider<bool>((_) => false); // true = day mode

/// Step the report week, refusing to walk into the future.
///
/// The guard lives here rather than in the button, so the keyboard and the
/// arrows cannot disagree about where the report ends.
void shiftReportWeek(WidgetRef ref, int delta) {
  final next = ref.read(weekOffsetProvider) + delta;
  if (next > 0) return;
  ref.read(weekOffsetProvider.notifier).state = next;
}

/// Step the reported day, refusing to walk into the future. [shiftReportWeek]'s
/// counterpart for day mode.
void shiftReportDay(WidgetRef ref, int delta) {
  final current = ref.read(reportDayProvider);
  final next = DateTime(current.year, current.month, current.day + delta);
  final now = DateTime.now();
  if (next.isAfter(DateTime(now.year, now.month, now.day))) return;
  ref.read(reportDayProvider.notifier).state = next;
}

/// Weekly or daily report: rolled-up horizontal bars per top-level category that
/// **drill down into their sub-activities**, and a client-side CSV export
/// (optionally subtree-filtered).
///
/// One period on screen at a time — a toggle switches between the week and a
/// single day rather than showing both, so the category bars answer one
/// question ("what did this week look like" or "what did Tuesday look like")
/// instead of resizing under a tap on a day row. The toggle carries context
/// across: entering day mode lands on today when the viewed week holds it,
/// otherwise the week's first day; leaving day mode shows the week the selected
/// day belongs to.
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
    final hasPointer = ref.watch(hasPointerProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final dayMode = ref.watch(reportModeProvider);
    final weekOffset = ref.watch(weekOffsetProvider);
    final base = DateTime(now.year, now.month, now.day + weekOffset * 7);
    final week = localWeekRange(base);
    final day = ref.watch(reportDayProvider);

    final scope = dayMode ? localDayRange(day) : week;
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
        dayMode
            ? _PeriodSelector(
                label: _dayLabel(day, now),
                onPrev: () => shiftReportDay(ref, -1),
                onNext: day.isBefore(today) ? () => shiftReportDay(ref, 1) : null,
              )
            : _PeriodSelector(
                label: _weekLabel(week.start, now),
                onPrev: () => shiftReportWeek(ref, -1),
                onNext: weekOffset < 0 ? () => shiftReportWeek(ref, 1) : null,
              ),
        const SizedBox(height: 10),
        _ModeToggle(dayMode: dayMode, onChanged: (v) => _setMode(v, week)),
        const SizedBox(height: 18),
        NeoSectionHeader(
          'Per category',
          brand: true,
          trailing: drillable
              ? Text(
                  'tap to drill in',
                  style: mono(context, size: 10, weight: FontWeight.w700, color: t.muted),
                )
              : null,
        ),
        const SizedBox(height: 12),
        if (roots.isEmpty)
          // An empty state, not a zero total: with continuous tracking the only
          // way to reach it is a range that holds no data at all.
          Text(
            dayMode ? _emptyDayMessage(day, now) : 'nothing tracked this week',
            style: mono(context, color: t.muted),
          )
        else
          _categoryRows(hasPointer, tree, totals, roots, max: maxRoot, depth: 0),
        const SizedBox(height: 18),
        NeoButton(
          label: '↧ export csv · all history',
          icon: null,
          primary: true,
          onTap: () => _exportCsv(context, ref, blocks, tree, now),
        ),
        const SizedBox(height: 14),
        const _StorageLine(),
      ],
    );
  }

  /// Carries context across the toggle: entering day mode picks a day inside
  /// the week on screen (today if the week holds it, its first day otherwise);
  /// leaving it shows the week the selected day belongs to. Without this the
  /// switch would drop you on whatever the other mode was last left at, which
  /// could be a different month entirely.
  void _setMode(bool toDayMode, ({DateTime start, DateTime end}) week) {
    if (toDayMode) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final inWeek = !today.isBefore(week.start) && today.isBefore(week.end);
      ref.read(reportDayProvider.notifier).state = inWeek ? today : week.start;
    } else {
      final day = ref.read(reportDayProvider);
      final thisWeekStart = localWeekRange(DateTime.now()).start;
      final dayWeekStart = localWeekRange(day).start;
      ref.read(weekOffsetProvider.notifier).state =
          dayWeekStart.difference(thisWeekStart).inDays ~/ 7;
    }
    ref.read(reportModeProvider.notifier).state = toDayMode;
  }

  /// The rows built by [_rows], selectable as one region when [hasPointer] —
  /// the rows are `NeoPressable`s (tap to drill in), and a mouse drag has
  /// nothing to spend against a tap.
  Widget _categoryRows(
    bool hasPointer,
    ActivityTree tree,
    ReportTotals totals,
    List<String> ids, {
    required Duration max,
    required int depth,
  }) {
    final rows = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _rows(tree, totals, ids, max: max, depth: depth),
    );
    return hasPointer ? SelectionArea(child: rows) : rows;
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

      out.add(
        _ReportBar(
          label: activity.name,
          color: parseHexColor(activity.color),
          value: totals.subtreeOf(id),
          max: max,
          depth: depth,
          expanded: open,
          onTap: children.isEmpty
              ? null
              : () => setState(() => open ? _expanded.remove(id) : _expanded.add(id)),
        ),
      );

      if (!open || children.isEmpty) continue;

      // Time booked on the node itself belongs to this level too, or the
      // children would visibly fail to add up to their parent.
      final direct = totals.directOf(id);
      final childMax = totals.subtreeOf(id);

      if (direct > Duration.zero) {
        out.add(
          _ReportBar(
            label: 'direct',
            color: parseHexColor(activity.color),
            value: direct,
            max: childMax,
            depth: depth + 1,
            muted: true,
          ),
        );
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

  /// "Today"/"Yesterday" the way the calendar and timeline already spell them;
  /// [formatWeekdayDay] otherwise, which this screen already used for the same
  /// purpose.
  static String _dayLabel(DateTime day, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return formatWeekdayDay(day);
  }

  static String _emptyDayMessage(DateTime day, DateTime now) {
    final label = _dayLabel(day, now);
    return label == 'Today' || label == 'Yesterday'
        ? 'nothing tracked ${label.toLowerCase()}'
        : 'nothing tracked on $label';
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
            Text(
              'LOCAL DB · ',
              style: mono(context, size: 10, weight: FontWeight.w800, spacing: 1, color: t.muted),
            ),
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
        Text(
          'BUILD · $kBuildId',
          style: mono(context, size: 10, weight: FontWeight.w700, color: t.muted),
        ),
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
        Text(
          'SYNC · ',
          style: mono(context, size: 10, weight: FontWeight.w800, spacing: 1, color: t.muted),
        ),
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

/// A period's label with `‹`/`›` steppers either side. The same shape whether
/// the period is a week or a single day — only the label and what the arrows
/// call differ.
class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({required this.label, required this.onPrev, this.onNext});
  final String label;
  final VoidCallback onPrev;
  final VoidCallback? onNext;

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
      ],
    );
  }
}

/// Week roll-up or a single day — never both. Built like `timeline_screen.dart`'s
/// `_ViewToggle`: two buttons, the active one `primary`.
class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.dayMode, required this.onChanged});
  final bool dayMode;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: NeoButton(
            label: '▦ week',
            primary: !dayMode,
            shadowOffset: 3,
            onTap: () => onChanged(false),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: NeoButton(
            label: '▤ day',
            primary: dayMode,
            shadowOffset: 3,
            onTap: () => onChanged(true),
          ),
        ),
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

/// One labelled bar in the drill-down. Deeper rows are indented and rendered a
/// size down, so the level a number belongs to is readable without a legend.
///
/// A [NeoPressable] rather than a bare gesture detector — the app's one device
/// for a tappable row that also takes keyboard focus, answers Enter and Space,
/// and shows a focus ring. Rows with nothing to drill into pass no [onTap],
/// which `NeoPressable` already reads as "not a control": no focus stop, no
/// cursor.
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
      child: NeoPressable(
        onTap: onTap,
        shadowOffset: root ? 5 : 3,
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
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mono(context, size: size, weight: FontWeight.w700, color: ink),
                  ),
                ),
                Text(
                  formatDurationHm(value),
                  style: mono(context, size: size, weight: FontWeight.w800, color: ink),
                ),
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

/// The export, without being on Reports first.
///
/// It always covered all history rather than the range on screen, so the screen
/// was never a precondition — only where the button happened to be.
Future<void> exportCsv(BuildContext context, WidgetRef ref) => _exportCsv(
  context,
  ref,
  ref.read(blocksProvider),
  ref.read(activityTreeProvider),
  DateTime.now(),
);

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
    scope = await showNeoSheet<String>(context, (sheet) {
      final t = neo(sheet);
      return Container(
        margin: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: t.bg,
          border: Border.all(color: t.line, width: 3),
        ),
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
    });
  }
  if (scope == null) return; // dismissed

  final subtreeRootId = scope == '__all__' ? null : scope;
  final csv = buildCsv(blocks: blocks, tree: tree, now: now, subtreeRootId: subtreeRootId);
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
          XFile.fromData(Uint8List.fromList(utf8.encode(csv)), mimeType: 'text/csv', name: name),
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
      shape: RoundedRectangleBorder(
        side: BorderSide(color: t.line, width: 3),
        borderRadius: BorderRadius.zero,
      ),
      title: Text('CSV · $rowCount rows', style: mono(context, weight: FontWeight.w800)),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(child: SelectableText(csv, style: mono(context, size: 11))),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'COPIED ✓ DONE',
            style: mono(context, weight: FontWeight.w800, color: t.brand),
          ),
        ),
      ],
    ),
  );
}
