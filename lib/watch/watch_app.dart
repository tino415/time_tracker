import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart' show Activity;
import '../data/providers.dart';
import '../data/wear_sync.dart';
import '../build_info.dart';
import '../domain/block.dart';
import '../domain/unsorted.dart';
import '../domain/wear_protocol.dart';
import '../format.dart';
import '../phone/widgets/neo.dart';
import '../theme/tokens.dart';

/// The Wear OS shell: what is tracking now, and the bookmarked activities to
/// switch to.
///
/// Deliberately not the phone layout. The screen is ~227x227 and round, so the
/// corners are unusable and there is no room for tabs, a timeline or reports —
/// the watch does one thing, which is change what is being tracked. Everything
/// else stays on the phone.
///
/// Always dark: a watch face is black, and a light shell would be both jarring
/// and expensive on OLED.
class WatchApp extends StatelessWidget {
  const WatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: neoTheme(NeoTokens.dark, Brightness.dark),
      home: const Scaffold(backgroundColor: Color(0xFF000000), body: _WatchHome()),
    );
  }
}

/// A tile acts on a right-to-left drag across it, not on a tap.
///
/// A watch is operated by feel, with 40px targets under a thumb — a misfire is
/// easy and, unlike on the phone, neither visible nor easy to undo. A drag is
/// deliberate in a way a tap is not, so it carries the confirmation in the
/// gesture instead of asking a question the wrist has to answer twice.
///
/// Right-to-left specifically, and never the other way: the reverse is Wear's
/// own swipe-to-dismiss, and this app does not turn that off. So a horizontal
/// direction means one thing here, and the system keeps the one it reserved.
const _actDirection = DismissDirection.endToStart;

class _WatchHome extends ConsumerStatefulWidget {
  const _WatchHome();

  @override
  ConsumerState<_WatchHome> createState() => _WatchHomeState();
}

class _WatchHomeState extends ConsumerState<_WatchHome> {
  /// Whether the hero has been tapped open into the start-time / re-point
  /// panel. Only meaningful while a block is running — [build] treats it as
  /// false once [currentBlockProvider] goes null, since there is nothing left
  /// to edit.
  bool _editing = false;

  /// Nudges run one at a time. See [_nudge] for why concurrent ones collapse.
  Future<void> _nudges = Future.value();

  @override
  Widget build(BuildContext context) {
    final activities = ref.watch(activitiesStreamProvider).valueOrNull ?? const [];
    final bookmarked = [
      for (final a in activities)
        if (a.bookmarked) a,
    ];
    final current = ref.watch(currentBlockProvider);
    final currentId = current != null && current.activities.length == 1
        ? current.activities.first.syncId
        : null;

    final unnamedRunning = current != null && isUnsortedSet(current.activities);

    // A block that stopped running while the panel was open (a switch relayed
    // from the phone, say) leaves nothing to edit. Corrected after the frame,
    // not inline: this is a build method, and current is still needed below to
    // decide which body to lay out this same pass.
    if (_editing && current == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _editing = false);
      });
    }
    final editing = _editing && current != null;

    // The display is a circle, so the usable area narrows towards the top and
    // bottom and the corners are cut entirely. Insets are a fraction of the
    // screen rather than fixed pixels, because that is what the geometry is:
    // proportional to the diameter, not to a device.
    final size = MediaQuery.of(context).size;
    final sideInset = size.width * 0.10;
    final topInset = size.height * 0.09;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(sideInset, topInset, sideInset, 0),
        child: Column(
          children: [
            // Fixed, not scrolled. The elapsed clock is the reason to look at
            // the watch at all, so it must not be something you can scroll away
            // from — and at the top of a scroll view it sat exactly where a
            // round screen cuts. Tapping it opens the correction panel below in
            // its place; there is nothing to correct when nothing is running.
            GestureDetector(
              key: const ValueKey('hero'),
              behavior: HitTestBehavior.opaque,
              onTap: current == null ? null : () => setState(() => _editing = true),
              child: _NowHero(current: current),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: editing
                  ? _editPanel(current, bookmarked, currentId)
                  : _switchList(unnamedRunning, bookmarked, currentId),
            ),
          ],
        ),
      ),
    );
  }

  Widget _switchList(bool unnamedRunning, List<Activity> bookmarked, String? currentId) {
    return ListView(
      // Bottom padding, not an inset: the last tile has to be scrollable clear
      // of the curve rather than permanently short of it.
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).size.height * 0.14),
      children: [
        _ActivityTile(
          // Keyed by identity, not label, so a test can find the tile without
          // depending on wording — and without matching the same name in the
          // hero above it.
          key: const ValueKey('tile-$kUnsortedActivityId'),
          name: unnamedRunning ? 'start another' : 'start now',
          color: parseHexColor(kUnsortedColor),
          // Deliberately enabled while an unnamed block runs: two in a row are
          // two different things to name later, not one long one.
          selected: false,
          onSwipe: () => ref.read(wearSyncProvider).startUnsorted(),
        ),
        const SizedBox(height: 6),
        for (final a in bookmarked) ...[
          _ActivityTile(
            key: ValueKey('tile-${a.syncId}'),
            name: a.name,
            color: parseHexColor(a.color),
            selected: a.syncId == currentId,
            // Switching to what is already running would only split the block;
            // the phone guards this too, but not offering it is clearer than a
            // gesture that does nothing.
            onSwipe: a.syncId == currentId
                ? null
                : () => ref.read(wearSyncProvider).requestSwitch(a.syncId),
          ),
          const SizedBox(height: 6),
        ],
        if (bookmarked.isEmpty) const _NoBookmarksHint(),
        const SizedBox(height: 6),
        // The watch is the device where "what is installed here?" is hardest
        // to answer any other way.
        Text(
          kBuildId,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: mono(context, size: 8, weight: FontWeight.w700, color: neo(context).muted),
        ),
      ],
    );
  }

  /// Replaces [_switchList] while the hero is tapped open: nudge the running
  /// block's start, or re-point what it tracks. Same list, same screen — this
  /// is a mode of the one shell, not a route or a sheet.
  Widget _editPanel(Block current, List<Activity> bookmarked, String? currentId) {
    final t = neo(context);
    // Re-pointing to what is already running would be a no-op the tap would
    // have to be told is a no-op — simpler to just not offer it, as the switch
    // list already does for the same reason.
    final repointable = [
      for (final a in bookmarked)
        if (a.syncId != currentId) a,
    ];

    return ListView(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).size.height * 0.14),
      children: [
        Text(
          'started ${formatTimeOfDay(current.start)}',
          textAlign: TextAlign.center,
          style: mono(context, size: 11, weight: FontWeight.w700, color: t.muted),
        ),
        const SizedBox(height: 8),
        // Two rows of three, not one of six: the usable width after the
        // shell's side insets is ~207px, so three across lands at ~65px each,
        // above the 44px thumb target the tiles below use. Six across would put
        // the outer two under the curve.
        _nudgeRow(current, const [-15, -5, -1]),
        const SizedBox(height: 6),
        _nudgeRow(current, const [1, 5, 15]),
        const SizedBox(height: 12),
        Text(
          'this is actually',
          textAlign: TextAlign.center,
          style: mono(context, size: 10, weight: FontWeight.w700, color: t.muted, spacing: 1),
        ),
        const SizedBox(height: 6),
        for (final a in repointable) ...[
          _ActivityTile(
            key: ValueKey('repoint-${a.syncId}'),
            name: a.name,
            color: parseHexColor(a.color),
            selected: false,
            // Unlike the nudges, this rewrites what is already recorded rather
            // than adjusting it — the drag the switch list uses for the same
            // reason applies here too.
            onSwipe: () => ref
                .read(wearSyncProvider)
                .requestAssign(changeSyncId: current.change.syncId, activityId: a.syncId),
          ),
          const SizedBox(height: 6),
        ],
        if (repointable.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'nothing else bookmarked',
              textAlign: TextAlign.center,
              style: mono(context, size: 9, weight: FontWeight.w700, color: t.muted),
            ),
          ),
        const SizedBox(height: 6),
        NeoButton(
          key: const ValueKey('edit-done'),
          label: '← done',
          shadowOffset: 3,
          onTap: () => setState(() => _editing = false),
        ),
      ],
    );
  }

  /// One row of three start-time nudges.
  ///
  /// No confirm step, unlike the tiles: a nudge adjusts what is recorded rather
  /// than rewriting it, and the hero above shows the result immediately. Nor is
  /// there a save — the phone's sheet batches nudges into one write, but each
  /// tap here commits, so the database is what the hero and the "started" line
  /// are reading. That is also why the taps have to be queued rather than
  /// fired: see [_nudge].
  Widget _nudgeRow(Block current, List<int> deltas) {
    return Row(
      children: [
        for (final m in deltas)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: NeoPressable(
                key: ValueKey('nudge-$m'),
                shadowOffset: 3,
                padding: const EdgeInsets.symmetric(vertical: 10),
                onTap: () => _nudge(current, m),
                child: Center(
                  child: Text(
                    m > 0 ? '+$m' : '$m',
                    style: mono(context, size: 12, weight: FontWeight.w800),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Queue a nudge behind the ones already running.
  ///
  /// Nudging is done in runs — a minute at a time until the clock reads right —
  /// so the taps arrive faster than a write commits. Fired concurrently they
  /// each read the boundary before any of them has moved it, so all of them
  /// write the same instant and a run of five lands as one minute. Chaining is
  /// what makes each tap see the one before it.
  void _nudge(Block current, int minutes) {
    final sync = ref.read(wearSyncProvider);
    _nudges = _nudges
        .then(
          (_) => sync.requestNudge(
            changeSyncId: current.change.syncId,
            by: Duration(minutes: minutes),
          ),
        )
        // One failed nudge must not wedge the rest of the row behind it.
        .catchError((Object _) {});
  }
}

/// What is tracking, dominated by the elapsed clock.
///
/// The clock is the reason to look at the watch at all, so it gets the size:
/// readable at arm's length without focusing, with the activity name as a label
/// beneath it rather than a heading above.
class _NowHero extends StatelessWidget {
  const _NowHero({required this.current});
  final Block? current;

  @override
  Widget build(BuildContext context) {
    final t = neo(context);
    final block = current;

    if (block == null || block.activities.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Text(
          'nothing tracked',
          textAlign: TextAlign.center,
          style: mono(context, size: 13, weight: FontWeight.w700, color: t.muted),
        ),
      );
    }

    final unnamed = isUnsortedSet(block.activities);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SecondTicker(
          builder: (context, now) => FittedBox(
            // Shrinks rather than wraps once the clock reaches hours — a
            // three-part time is wider than a 227px screen at this size.
            fit: BoxFit.scaleDown,
            child: Text(
              formatElapsedClock(block.duration(now)),
              style: mono(context, size: 34, weight: FontWeight.w800, color: t.brand, height: 1),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: parseHexColor(block.activities.first.color),
                border: Border.all(color: t.line, width: 1),
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                // The catch-all's row carries its own label, so this prints the
                // activity name like any other block and the watch cannot drift
                // to a different word from the phone. Only the colour still
                // marks it out.
                block.activities.map((a) => a.name).join(' + '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: mono(
                  context,
                  size: 12,
                  weight: FontWeight.w800,
                  color: unnamed ? t.muted : t.ink,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// No bookmarks yet. Not an empty state — "start now" is still there and is the
/// action that matters — just a pointer at where bookmarks come from.
class _NoBookmarksHint extends ConsumerWidget {
  const _NoBookmarksHint();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = neo(context);
    final reachable = ref.watch(wearReachabilityProvider).valueOrNull == WearReachability.reachable;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        reachable ? 'waiting for the phone…' : 'bookmark on the phone',
        textAlign: TextAlign.center,
        style: mono(context, size: 9, weight: FontWeight.w700, color: t.muted),
      ),
    );
  }
}

/// One switch target. Full-width and tall: on a watch the finger is the whole
/// input device, so tiles are sized for a thumb rather than for density.
///
/// Acts on a drag rather than a tap — see [_actDirection]. [Dismissible] is the
/// vehicle because it already owns the part worth not rewriting: a threshold
/// measured against the tile's own width, the drag tracking the finger, and a
/// spring back when it does not carry. Nothing is dismissed, so [confirmDismiss]
/// fires the action and answers false; the tile returns to where it was and the
/// list it lives in never changes length.
class _ActivityTile extends StatelessWidget {
  const _ActivityTile({
    super.key,
    required this.name,
    required this.color,
    required this.selected,
    required this.onSwipe,
  });

  final String name;
  final Color color;
  final bool selected;

  /// Null for a tile with nothing to do — it then refuses the drag rather than
  /// swallowing one that goes nowhere.
  final VoidCallback? onSwipe;

  @override
  Widget build(BuildContext context) {
    final t = neo(context);
    return Dismissible(
      key: ValueKey('swipe-$name'),
      direction: onSwipe == null ? DismissDirection.none : _actDirection,
      confirmDismiss: (_) async {
        onSwipe?.call();
        return false;
      },
      // Uncovered as the tile slides off it, so the gesture says what it will do
      // while it is still being made.
      background: Container(
        color: t.brand,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 12),
        child: Text(
          'go ✓',
          style: mono(context, size: 12, weight: FontWeight.w800, color: t.brandInk),
        ),
      ),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: .30) : t.surface,
          border: Border.all(color: selected ? color : t.line, width: selected ? 3 : 2),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            Container(width: 6, height: 22, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mono(
                  context,
                  size: 13,
                  weight: selected ? FontWeight.w800 : FontWeight.w700,
                  color: t.ink,
                ),
              ),
            ),
            if (selected)
              Text(
                '●',
                style: mono(context, size: 10, weight: FontWeight.w800, color: color),
              )
            else if (onSwipe != null)
              Text(
                '‹',
                style: mono(context, size: 14, weight: FontWeight.w800, color: t.muted),
              ),
          ],
        ),
      ),
    );
  }
}
