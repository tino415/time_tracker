import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../data/wear_sync.dart';
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
      home: const Scaffold(
        backgroundColor: Color(0xFF000000),
        body: _WatchHome(),
      ),
    );
  }
}

class _WatchHome extends ConsumerWidget {
  const _WatchHome();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activities = ref.watch(activitiesStreamProvider).valueOrNull ?? const [];
    final bookmarked = [
      for (final a in activities)
        if (a.bookmarked) a,
    ];
    final current = ref.watch(currentBlockProvider);
    final currentId = current != null && current.activities.length == 1
        ? current.activities.first.syncId
        : null;

    return SafeArea(
      child: Padding(
        // A round screen clips its corners, so nothing sits flush to the edge.
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        child: Column(
          children: [
            _NowHeader(current: current),
            const SizedBox(height: 6),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 2),
                // One extra row at the top: "start now". On a watch this is the
                // most valuable action of all — a glance and a tap, with the
                // naming deferred to the phone.
                itemCount: bookmarked.length + 1,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    final unnamedRunning =
                        current != null && isUnsortedSet(current.activities);
                    return _ActivityTile(
                      name: unnamedRunning ? 'unnamed · name on phone' : 'start now',
                      color: parseHexColor(kUnsortedColor),
                      selected: unnamedRunning,
                      onTap: unnamedRunning
                          ? null
                          : () => ref.read(wearSyncProvider).startUnsorted(),
                    );
                  }

                  final a = bookmarked[index - 1];
                  final selected = a.syncId == currentId;
                  return _ActivityTile(
                    name: a.name,
                    color: parseHexColor(a.color),
                    selected: selected,
                    // Tapping what is already running would only split the
                    // block; the phone guards this too, but not offering it is
                    // clearer than a tap that does nothing.
                    onTap: selected
                        ? null
                        : () => ref.read(wearSyncProvider).requestSwitch(a.syncId),
                  );
                },
              ),
            ),
            // The start-now tile means the screen is never empty, so this is a
            // hint rather than an empty state.
            if (bookmarked.isEmpty) const _NoBookmarksHint(),
          ],
        ),
      ),
    );
  }
}

/// What is tracking, with a live elapsed clock — the one thing worth a glance.
class _NowHeader extends StatelessWidget {
  const _NowHeader({required this.current});
  final Block? current;

  @override
  Widget build(BuildContext context) {
    final t = neo(context);
    final block = current;

    if (block == null || block.activities.isEmpty) {
      return Text(
        'nothing tracked',
        style: mono(context, size: 11, weight: FontWeight.w700, color: t.muted),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: parseHexColor(block.activities.first.color),
                border: Border.all(color: t.line, width: 1),
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                block.activities.map((a) => a.name).join(' + '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: mono(context, size: 12, weight: FontWeight.w800),
              ),
            ),
          ],
        ),
        SecondTicker(
          builder: (context, now) => Text(
            formatElapsedClock(block.duration(now)),
            style: mono(context, size: 15, weight: FontWeight.w800, color: t.brand),
          ),
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
    final reachable =
        ref.watch(wearReachabilityProvider).valueOrNull == WearReachability.reachable;

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
class _ActivityTile extends StatelessWidget {
  const _ActivityTile({
    required this.name,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = neo(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: .30) : t.surface,
          border: Border.all(color: selected ? color : t.line, width: selected ? 3 : 2),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            Container(width: 6, height: 20, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mono(
                  context,
                  size: 12,
                  weight: selected ? FontWeight.w800 : FontWeight.w700,
                ),
              ),
            ),
            if (selected)
              Text('●', style: mono(context, size: 10, weight: FontWeight.w800, color: color)),
          ],
        ),
      ),
    );
  }
}
