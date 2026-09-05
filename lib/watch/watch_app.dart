import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart' show Activity;
import '../data/manual_sync.dart';
import '../data/providers.dart';
import '../data/sync_service.dart';
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

/// Tapping a tile arms it; a second tap within [_confirmWindow] switches.
///
/// A watch is operated by feel, with 40px targets under a thumb — a misfire is
/// easy and, unlike on the phone, neither visible nor easy to undo. Two taps is
/// the cost; it stays one gesture-per-hand and needs no modal, which there is no
/// room for anyway. Arming expires on its own so a stray tap does not leave the
/// watch waiting.
const _confirmWindow = Duration(seconds: 4);

/// What fills the shell. One at a time, and only [_WatchPane.home] survives
/// having nothing to track.
enum _WatchPane { home, menu, editStart, swap }

/// Where a left-to-right swipe lands from each pane. Home is the floor.
_WatchPane _paneBehind(_WatchPane pane) => switch (pane) {
  _WatchPane.home || _WatchPane.menu => _WatchPane.home,
  _WatchPane.editStart || _WatchPane.swap => _WatchPane.menu,
};

/// How far across the screen a swipe must carry to navigate, as a fraction of
/// the width — or, failing that, how fast it was moving when it lifted.
///
/// Distance *or* velocity, because a wrist flicks short and quick: a gesture
/// people actually make often never travels the ~50px a distance gate alone
/// would demand.
const _swipeFraction = 0.22;
const _swipeVelocity = 320.0;

/// The travel a flick still has to clear, however fast it was going.
///
/// A tap is rejected once it wanders [kTouchSlop], so a thumb rolling off a tile
/// covers about that much at speed. Gating the flick one pixel past it would
/// turn exactly the misfire the two-tap arming exists to catch into a
/// navigation instead.
const _swipeFloor = 2 * kTouchSlop;

class _WatchHome extends ConsumerStatefulWidget {
  const _WatchHome();

  @override
  ConsumerState<_WatchHome> createState() => _WatchHomeState();
}

class _WatchHomeState extends ConsumerState<_WatchHome> {
  String? _armed;
  Timer? _disarm;

  _WatchPane _pane = _WatchPane.home;

  /// Travel of the swipe in progress. Accumulated rather than read at the end,
  /// because a drag reports deltas and only the total says which way it went.
  double _dragX = 0;

  /// Nudges run one at a time. See [_nudge] for why concurrent ones collapse.
  Future<void> _nudges = Future.value();

  @override
  void dispose() {
    _disarm?.cancel();
    super.dispose();
  }

  /// Returns true when the caller should go ahead.
  bool _confirm(String key) {
    if (_armed == key) {
      _disarm?.cancel();
      setState(() => _armed = null);
      return true;
    }
    _disarm?.cancel();
    setState(() => _armed = key);
    _disarm = Timer(_confirmWindow, () {
      if (mounted) setState(() => _armed = null);
    });
    return false;
  }

  /// Every pane change goes through here, so that arming cannot outlive the
  /// screen it was started on: a tile armed, left behind and returned to inside
  /// the confirm window would otherwise commit on a single tap.
  void _show(_WatchPane pane) {
    _disarm?.cancel();
    setState(() {
      _armed = null;
      _pane = pane;
    });
  }

  void _back() {
    if (_pane == _WatchPane.home) return;
    _show(_paneBehind(_pane));
  }

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

    // Every pane but home edits the running block, and the swap pane names it
    // from activities.first — so an empty set is as unusable as no block at all,
    // and it happens: the timeline fuses three streams, and a new change can
    // arrive before its join row does. Corrected after the frame, not inline:
    // this is a build method, and current is still needed below to lay out this
    // same pass. Past this point, a pane other than home means current is there.
    final editable = current != null && current.activities.isNotEmpty;
    if (_pane != _WatchPane.home && !editable) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _show(_WatchPane.home);
      });
    }
    final pane = editable ? _pane : _WatchPane.home;

    // The display is a circle, so the usable area narrows towards the top and
    // bottom and the corners are cut entirely. Insets are a fraction of the
    // screen rather than fixed pixels, because that is what the geometry is:
    // proportional to the diameter, not to a device.
    final size = MediaQuery.of(context).size;
    final sideInset = size.width * 0.10;
    final topInset = size.height * 0.09;

    final fixedTop = _fixedTop(pane, current, editable);

    return PopScope(
      // Wear routes its own dismiss gesture here as a pop, so this is what
      // makes that gesture unwind one pane rather than leave the app — and at
      // home, where there is nothing to unwind, it still leaves. The physical
      // button takes the same path.
      canPop: pane == _WatchPane.home,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: GestureDetector(
        key: const ValueKey('watch-shell'),
        behavior: HitTestBehavior.opaque,
        // The default resets the recognizer's origin when the drag is accepted,
        // swallowing the first kTouchSlop — a third of the distance gate here.
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragStart: (_) => _dragX = 0,
        onHorizontalDragUpdate: (d) => _dragX += d.delta.dx,
        onHorizontalDragCancel: () => _dragX = 0,
        onHorizontalDragEnd: (d) => _swipeSettled(d.primaryVelocity ?? 0, size.width, editable),
        // Outside the padding, so a swipe starting in the side gutter counts.
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(sideInset, topInset, sideInset, 0),
            child: Column(
              children: [
                // The top inset is outside the scroll view, so whatever starts
                // at the top of it starts clear of the curve — which is what
                // the clock needed, not a pin. Scrolling may carry it off.
                // What stays here stays because its pane edits it: the
                // start-time and swap screens are read as "this, instead of
                // that", so the thing being changed has to stay in view.
                if (fixedTop != null) ...[fixedTop, const SizedBox(height: 8)],
                Expanded(
                  child: _body(pane, current, editable, bookmarked, currentId, unnamedRunning),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _swipeSettled(double velocity, double width, bool editable) {
    final dx = _dragX;
    _dragX = 0;

    final far = dx.abs() >= width * _swipeFraction;
    final flicked =
        velocity.abs() >= _swipeVelocity && dx.abs() >= _swipeFloor && velocity.sign == dx.sign;
    if (!far && !flicked) return;

    if (dx < 0) {
      if (_pane == _WatchPane.home && editable) _show(_WatchPane.menu);
    } else {
      _back();
    }
  }

  /// Null where the pane wants nothing pinned and scrolls everything instead.
  Widget? _fixedTop(_WatchPane pane, Block? current, bool editable) {
    switch (pane) {
      case _WatchPane.home:
        return null;
      case _WatchPane.menu:
        return _NowHero(key: const ValueKey('hero'), current: current, menuHint: false);
      case _WatchPane.editStart:
        return _ElapsedClock(current!);
      case _WatchPane.swap:
        return _runningTile(current!);
    }
  }

  Widget _body(
    _WatchPane pane,
    Block? current,
    bool editable,
    List<Activity> bookmarked,
    String? currentId,
    bool unnamedRunning,
  ) {
    switch (pane) {
      case _WatchPane.home:
        return _switchList(current, editable, unnamedRunning, bookmarked, currentId);
      case _WatchPane.menu:
        return _menu();
      case _WatchPane.editStart:
        return _startTimeBody(current!);
      case _WatchPane.swap:
        return _swapBody(current!, bookmarked, currentId);
    }
  }

  /// Bottom padding, not an inset: the last row has to be scrollable clear of
  /// the curve rather than permanently short of it.
  EdgeInsets get _bodyPadding => EdgeInsets.only(bottom: MediaQuery.of(context).size.height * 0.14);

  /// Space above the hero, so at rest it reads as the top of the screen rather
  /// than the first row of a list. A fraction of the diameter for the same
  /// reason the insets are: it is the geometry that scales, not the device.
  double get _heroLead => MediaQuery.of(context).size.height * 0.22;

  Widget _switchList(
    Block? current,
    bool editable,
    bool unnamedRunning,
    List<Activity> bookmarked,
    String? currentId,
  ) {
    // No PageStorageKey: the clock is the first row now, so restoring an offset
    // would re-enter home with the one thing worth glancing at already scrolled
    // off. Opening at the top costs a long list its remembered position, which
    // is the cheaper of the two.
    return ListView(
      padding: _bodyPadding,
      children: [
        SizedBox(height: _heroLead),
        // menuHint takes the same condition the swipe is gated on, so the caret
        // cannot promise a menu that will not open.
        _NowHero(key: const ValueKey('hero'), current: current, menuHint: editable),
        const SizedBox(height: 8),
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
          armed: _armed == kUnsortedActivityId,
          onTap: () {
            if (!_confirm(kUnsortedActivityId)) return;
            ref.read(wearSyncProvider).startUnsorted();
          },
        ),
        const SizedBox(height: 6),
        for (final a in bookmarked) ...[
          _ActivityTile(
            key: ValueKey('tile-${a.syncId}'),
            name: a.name,
            color: parseHexColor(a.color),
            selected: a.syncId == currentId,
            armed: _armed == a.syncId,
            // Tapping what is already running would only split the block; the
            // phone guards this too, but not offering it is clearer than a tap
            // that does nothing.
            onTap: a.syncId == currentId
                ? null
                : () {
                    if (!_confirm(a.syncId)) return;
                    ref.read(wearSyncProvider).requestSwitch(a.syncId);
                  },
          ),
          const SizedBox(height: 6),
        ],
        if (bookmarked.isEmpty) const _NoBookmarksHint(),
        const SizedBox(height: 6),
        const _SyncRow(),
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

  /// What can be done to the running block. Rows navigate rather than change
  /// anything, so unlike the tiles they act on the first tap.
  Widget _menu() {
    return ListView(
      padding: _bodyPadding,
      children: [
        _MenuRow(
          key: const ValueKey('menu-edit-start'),
          label: 'edit start time',
          onTap: () => _show(_WatchPane.editStart),
        ),
        const SizedBox(height: 6),
        _MenuRow(
          key: const ValueKey('menu-swap'),
          label: 'swap current action',
          onTap: () => _show(_WatchPane.swap),
        ),
      ],
    );
  }

  /// Nudge the running block's start. The clock above is fixed and reads the
  /// database, so it is the preview.
  Widget _startTimeBody(Block current) {
    return ListView(
      padding: _bodyPadding,
      children: [
        Text(
          'started ${formatTimeOfDay(current.start)}',
          textAlign: TextAlign.center,
          style: mono(context, size: 11, weight: FontWeight.w700, color: neo(context).muted),
        ),
        const SizedBox(height: 8),
        // Two rows of three, not one of six: the usable width after the
        // shell's side insets is ~207px, so three across lands at ~65px each,
        // above the 44px thumb target the tiles use. Six across would put the
        // outer two under the curve.
        _nudgeRow(current, const [-15, -5, -1]),
        const SizedBox(height: 6),
        _nudgeRow(current, const [1, 5, 15]),
      ],
    );
  }

  /// Re-point the running block: same boundary, same clock, a different name on
  /// the time already accrued. What it is now is pinned above, so the list is
  /// read as "instead of that".
  Widget _swapBody(Block current, List<Activity> bookmarked, String? currentId) {
    final t = neo(context);
    // Swapping to what is already running would be a no-op the tap would have
    // to be told is a no-op — simpler to just not offer it, as the switch list
    // already does for the same reason.
    final candidates = [
      for (final a in bookmarked)
        if (a.syncId != currentId) a,
    ];

    return ListView(
      padding: _bodyPadding,
      children: [
        Text(
          'this is actually',
          textAlign: TextAlign.center,
          style: mono(context, size: 10, weight: FontWeight.w700, color: t.muted, spacing: 1),
        ),
        const SizedBox(height: 6),
        for (final a in candidates) ...[
          _ActivityTile(
            key: ValueKey('repoint-${a.syncId}'),
            name: a.name,
            color: parseHexColor(a.color),
            selected: false,
            armed: _armed == 'repoint-${a.syncId}',
            // Unlike the nudges, this rewrites what is already recorded rather
            // than adjusting it — the arm-then-tap-again gesture the switch
            // list uses for the same reason applies here too.
            onTap: () {
              if (!_confirm('repoint-${a.syncId}')) return;
              ref
                  .read(wearSyncProvider)
                  .requestAssign(changeSyncId: current.change.syncId, activityId: a.syncId);
              // Leaving is not politeness: once it commits, the pinned tile and
              // the list both re-derive, so staying would reshuffle the rows
              // under a finger still on the glass.
              _show(_WatchPane.home);
            },
          ),
          const SizedBox(height: 6),
        ],
        if (candidates.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'nothing else bookmarked',
              textAlign: TextAlign.center,
              style: mono(context, size: 9, weight: FontWeight.w700, color: t.muted),
            ),
          ),
      ],
    );
  }

  /// What the swap list is swapping away from, in the fixed region so it cannot
  /// be scrolled apart from the choices below it.
  Widget _runningTile(Block current) {
    return _ActivityTile(
      key: const ValueKey('swap-current'),
      name: current.activities.map((a) => a.name).join(' + '),
      color: parseHexColor(current.activities.first.color),
      selected: true,
      onTap: null,
    );
  }

  /// One row of three start-time nudges.
  ///
  /// No confirm step, unlike the tiles: a nudge adjusts what is recorded rather
  /// than rewriting it, and the clock above shows the result immediately. Nor is
  /// there a save — the phone's sheet batches nudges into one write, but each
  /// tap here commits, so the database is what the clock and the "started" line
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
  const _NowHero({super.key, required this.current, required this.menuHint});
  final Block? current;

  /// Show the caret that says there is a menu one swipe to the left. A swipe is
  /// invisible; this is the only thing on screen that says it exists.
  final bool menuHint;

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
        _ElapsedClock(block),
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
            if (menuHint) ...[
              const SizedBox(width: 4),
              Text(
                // Pointing right, because a right-to-left swipe brings the menu
                // in from the right.
                '›',
                key: const ValueKey('menu-hint'),
                style: mono(context, size: 11, weight: FontWeight.w800, color: t.muted),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// How long the block has been running, ticking.
///
/// Shrinks rather than wraps once it reaches hours — a three-part time is wider
/// than a 227px screen at this size.
class _ElapsedClock extends StatelessWidget {
  const _ElapsedClock(this.block);
  final Block block;

  @override
  Widget build(BuildContext context) {
    return SecondTicker(
      builder: (context, now) => FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          formatElapsedClock(block.duration(now)),
          style: mono(
            context,
            size: 34,
            weight: FontWeight.w800,
            color: neo(context).brand,
            height: 1,
          ),
        ),
      ),
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

/// Push what this watch has recorded, without waiting for the phone to be
/// opened.
///
/// On home rather than in the menu, which is where the other actions live: every
/// pane but this one is gated on a running block, and forcing a sync is exactly
/// as useful with nothing tracking — arguably more, since that is when you have
/// just finished something.
///
/// Absent rather than disabled when it cannot work — no backend in this build,
/// or no token relayed yet. Unlike the phone there is no invitation state to
/// offer: a 227px screen has no room for the setup sheet, and the account has to
/// come from the phone anyway.
class _SyncRow extends ConsumerWidget {
  const _SyncRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = neo(context);
    if (!ref.watch(syncConfigProvider).hasServer) return const SizedBox.shrink();
    if (ref.watch(syncServiceProvider) == null) return const SizedBox.shrink();

    final sync = ref.watch(manualSyncProvider);
    return NeoPressable(
      // On the control rather than on the widget: this returns an empty box on
      // a build that cannot sync, and a key held by the widget would still be
      // found there — so "no sync row" could not be asserted at all.
      key: const ValueKey('sync-now'),
      shadowOffset: 3,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      onTap: sync.running ? null : () => _syncNow(ref),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            sync.running ? '⟳ syncing…' : '⟳ sync now',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: mono(context, size: 12, weight: FontWeight.w800),
          ),
          // The only feedback there is. A failure inside sync is silent by
          // design everywhere else, and on a watch there is no second screen to
          // go and check.
          if (sync.status != null) ...[
            const SizedBox(height: 3),
            Text(
              sync.status!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono(context, size: 9, weight: FontWeight.w700, color: t.muted),
            ),
          ],
        ],
      ),
    );
  }

  /// Direct first, then over the wrist. The watch holds the account token so it
  /// can reach the server itself, which is the only path that works with the
  /// phone asleep — but a Bluetooth-only watch off wifi has no route at all, and
  /// then the phone is the one device that does.
  Future<void> _syncNow(WidgetRef ref) async {
    if (await ref.read(manualSyncProvider.notifier).run()) return;
    await ref.read(wearSyncProvider).requestSyncNow();
  }
}

/// One way further in. Shaped unlike [_ActivityTile] on purpose: a row that only
/// navigates must not read like one that changes what is recorded.
class _MenuRow extends StatelessWidget {
  const _MenuRow({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return NeoPressable(
      shadowOffset: 3,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono(context, size: 12, weight: FontWeight.w800),
            ),
          ),
          Text('›', style: mono(context, size: 12, weight: FontWeight.w800)),
        ],
      ),
    );
  }
}

/// One switch target. Full-width and tall: on a watch the finger is the whole
/// input device, so tiles are sized for a thumb rather than for density.
class _ActivityTile extends StatelessWidget {
  const _ActivityTile({
    super.key,
    required this.name,
    required this.color,
    required this.selected,
    required this.onTap,
    this.armed = false,
  });

  final String name;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  /// Tapped once and waiting for confirmation.
  final bool armed;

  @override
  Widget build(BuildContext context) {
    final t = neo(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          // Armed is the loudest state on the screen on purpose: it is asking a
          // question, and an unanswered one should not be mistakable for the
          // running activity.
          color: armed ? t.brand : (selected ? color.withValues(alpha: .30) : t.surface),
          border: Border.all(
            color: armed ? t.brand : (selected ? color : t.line),
            width: armed || selected ? 3 : 2,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            Container(width: 6, height: 22, color: armed ? t.brandInk : color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                armed ? 'tap again' : name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mono(
                  context,
                  size: 13,
                  weight: armed || selected ? FontWeight.w800 : FontWeight.w700,
                  color: armed ? t.brandInk : t.ink,
                ),
              ),
            ),
            if (armed)
              Text(
                '✓',
                style: mono(context, size: 13, weight: FontWeight.w800, color: t.brandInk),
              )
            else if (selected)
              Text(
                '●',
                style: mono(context, size: 10, weight: FontWeight.w800, color: color),
              ),
          ],
        ),
      ),
    );
  }
}
