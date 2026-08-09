import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/providers.dart';
import '../../data/tracker_controller.dart';
import '../../domain/block.dart';
import '../../domain/unsorted.dart';
import '../../format.dart';
import '../../theme/tokens.dart';
import '../widgets/activity_editor.dart';
import '../widgets/assign_activity.dart';
import '../widgets/block_actions.dart';
import '../widgets/block_comment.dart';
import '../widgets/block_start.dart';
import '../widgets/neo.dart';

/// The live "Now" screen: the current-activity hero, a bookmarked quick-switch
/// grid, and a paste/search field for switching to (or creating) any activity.
class NowScreen extends ConsumerWidget {
  const NowScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activities = ref.watch(activitiesStreamProvider).valueOrNull ?? const [];
    final current = ref.watch(currentBlockProvider);
    final bookmarked = activities.where((a) => a.bookmarked).toList();

    if (activities.isEmpty) return const _FirstRunEmpty();

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            children: [
              _HeroCard(block: current),
              const SizedBox(height: 18),
              NeoSectionHeader('Switch to · bookmarked'),
              const SizedBox(height: 12),
              if (bookmarked.isEmpty)
                Text('no bookmarks yet — star an activity to pin it here',
                    style: mono(context, color: neo(context).muted))
              else
                _SwitchGrid(activities: bookmarked, current: current),
            ],
          ),
        ),
        const _StartNowBar(),
        const _QuickSwitchField(),
      ],
    );
  }
}

/// One tap, no typing: open a boundary *now* and decide what it was afterwards.
///
/// Sits directly above the search field and below the fold of everything else,
/// because the whole value is that it is reachable without reading the screen.
class _StartNowBar extends ConsumerWidget {
  const _StartNowBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = neo(context);
    final current = ref.watch(currentBlockProvider);
    // Already running something unnamed — offering to start another would just
    // split it, and the useful action then is naming this one.
    if (current != null && isUnsortedSet(current.activities)) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(top: BorderSide(color: t.line, width: 3)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: NeoButton(
        label: '▶ start now · name it later',
        shadowOffset: 4,
        onTap: () => ref.read(trackerControllerProvider).startUnsorted(),
      ),
    );
  }
}

class _HeroCard extends ConsumerWidget {
  const _HeroCard({required this.block});
  final Block? block;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = neo(context);
    if (block == null || block!.activities.isEmpty) {
      return Container(
        decoration: t.card(shadowOffset: 10),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NeoChip('Not tracking'),
            const SizedBox(height: 14),
            Text('pick something below to start',
                style: mono(context, size: 16, weight: FontWeight.w700, color: t.muted)),
          ],
        ),
      );
    }

    final b = block!;
    final acts = b.activities;
    final fill = parseHexColor(acts.first.color);
    final onFill = ActivityPalette.onFill(fill);
    final tree = ref.watch(activityTreeProvider);
    final multi = acts.length > 1;
    final unnamed = isUnsortedSet(acts);

    return Container(
      decoration: BoxDecoration(
        color: fill,
        border: Border.all(color: t.line, width: 3),
        boxShadow: t.hardShadow(10),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                color: onFill,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                child: Text(
                  tree.pathName(acts.first.syncId),
                  style: mono(context, size: 11, weight: FontWeight.w800, color: fill),
                ),
              ),
              const Spacer(),
              _LiveDot(color: onFill),
              const SizedBox(width: 6),
              Text('TRACKING', style: mono(context, size: 10, weight: FontWeight.w800, color: onFill)),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            unnamed ? 'unnamed' : (multi ? acts.map((a) => a.name).join('  +  ') : acts.first.name),
            style: mono(context, size: 24, weight: FontWeight.w800, color: onFill, height: 1.1),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (unnamed) ...[
                // The clock is already running against this block, so answering
                // it later costs nothing — which is the point.
                NeoPressable(
                  onTap: () => assignBlockActivity(context, ref, b),
                  fill: onFill,
                  shadowOffset: 4,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Text('▸ WHAT IS THIS?',
                      style: mono(context, size: 12, weight: FontWeight.w800, spacing: .8, color: fill)),
                ),
                const SizedBox(width: 8),
              ],
              // The full block menu — change, tag, untag, retime — on the block
              // that is hardest to reach any other way, because it has no end
              // yet and so is only one card on the timeline.
              NeoPressable(
                onTap: () => showBlockActions(
                  context,
                  ref,
                  b,
                  canMerge: ref.read(blocksProvider).length > 1,
                ),
                fill: onFill,
                shadowOffset: 4,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Text(unnamed ? '⋯' : '⋯ EDIT BLOCK',
                    style: mono(context, size: 12, weight: FontWeight.w800, spacing: .8, color: fill)),
              ),
            ],
          ),
          if (multi) ...[
            const SizedBox(height: 6),
            Text('${acts.length} activities · even-split',
                style: mono(context, size: 11, weight: FontWeight.w700, color: onFill)),
          ],
          const SizedBox(height: 16),
          SecondTicker(
            builder: (context, now) => Text(
              formatElapsedClock(b.duration(now)),
              style: mono(context, size: 40, weight: FontWeight.w800, color: onFill, height: 1),
            ),
          ),
          const SizedBox(height: 6),
          // The one correction worth a direct tap: you almost always notice the
          // start is wrong while looking at the clock it drives.
          GestureDetector(
            onTap: () => editBlockStart(context, ref, b),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Text('since ${formatTimeOfDay(b.start)}',
                    style: mono(context, size: 12, weight: FontWeight.w700, color: onFill)),
                const SizedBox(width: 8),
                Text('edit',
                    style: mono(context, size: 10, weight: FontWeight.w800, spacing: .8, color: onFill)
                        .copyWith(decoration: TextDecoration.underline, decorationColor: onFill)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _CommentRow(block: b, onFill: onFill),
        ],
      ),
    );
  }
}

class _CommentRow extends ConsumerWidget {
  const _CommentRow({required this.block, required this.onFill});
  final Block block;
  final Color onFill;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comment = block.comment;
    return GestureDetector(
      onTap: () => editBlockComment(context, ref, block),
      behavior: HitTestBehavior.opaque,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('✎ ', style: mono(context, size: 13, weight: FontWeight.w800, color: onFill)),
          Expanded(
            child: Text(
              comment == null || comment.isEmpty ? 'add a note…' : comment,
              style: mono(context, size: 13, weight: FontWeight.w700, color: onFill).copyWith(
                fontStyle: (comment == null || comment.isEmpty) ? FontStyle.italic : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveDot extends StatefulWidget {
  const _LiveDot({required this.color});
  final Color color;

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.35, end: 1.0).animate(_c),
      child: Container(width: 10, height: 10, color: widget.color),
    );
  }
}

class _SwitchGrid extends ConsumerWidget {
  const _SwitchGrid({required this.activities, required this.current});
  final List<Activity> activities;
  final Block? current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIds = current?.activities.map((a) => a.syncId).toSet() ?? const {};
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: activities.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.9,
      ),
      itemBuilder: (_, i) {
        final a = activities[i];
        final fill = parseHexColor(a.color);
        final onFill = ActivityPalette.onFill(fill);
        final active = currentIds.contains(a.syncId);
        return NeoPressable(
          fill: fill,
          shadowOffset: 6,
          padding: const EdgeInsets.all(12),
          onTap: () => ref.read(trackerControllerProvider).switchTo(a.syncId),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  if (active) Text('● ', style: mono(context, size: 11, weight: FontWeight.w800, color: onFill)),
                  if (a.externalId != null)
                    Expanded(
                      child: Text(a.externalId!,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: mono(context, size: 10, weight: FontWeight.w800, color: onFill)),
                    ),
                ],
              ),
              Text(
                a.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: mono(context, size: 15, weight: FontWeight.w800, color: onFill, height: 1.1),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Paste-a-task / search field with recency-ordered suggestions. Tapping a
/// suggestion switches; the create row makes a new activity and switches to it.
class _QuickSwitchField extends ConsumerStatefulWidget {
  const _QuickSwitchField();

  @override
  ConsumerState<_QuickSwitchField> createState() => _QuickSwitchFieldState();
}

class _QuickSwitchFieldState extends ConsumerState<_QuickSwitchField> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<Activity> _suggestions(List<Activity> all) {
    final q = _query.trim().toLowerCase();
    final matches = all.where((a) {
      if (q.isEmpty) return true;
      return a.name.toLowerCase().contains(q) || (a.externalId?.toLowerCase().contains(q) ?? false);
    }).toList()
      ..sort((a, b) {
        final la = a.lastUsedAt, lb = b.lastUsedAt;
        if (la != null && lb != null) return lb.compareTo(la);
        if (la != null) return -1;
        if (lb != null) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return matches.take(5).toList();
  }

  Future<void> _switch(String id) async {
    await ref.read(trackerControllerProvider).switchTo(id);
    _controller.clear();
    setState(() => _query = '');
  }

  Future<void> _create() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    setState(() => _query = '');
    await showActivityEditor(context, ref, initialName: text, switchToOnCreate: true);
  }

  @override
  Widget build(BuildContext context) {
    final t = neo(context);
    final all = ref.watch(activitiesStreamProvider).valueOrNull ?? const [];
    final showSuggestions = _query.trim().isNotEmpty;
    final suggestions = showSuggestions ? _suggestions(all) : const <Activity>[];

    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(top: BorderSide(color: t.line, width: 3)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showSuggestions) ...[
            for (final a in suggestions)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: NeoPressable(
                  onTap: () => _switch(a.syncId),
                  shadowOffset: 3,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(children: [
                    NeoSwatch(parseHexColor(a.color), size: 14),
                    const SizedBox(width: 10),
                    Expanded(child: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: mono(context, weight: FontWeight.w700))),
                    if (a.externalId != null) Text(a.externalId!, style: mono(context, size: 11, color: t.muted)),
                  ]),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: NeoPressable(
                onTap: _create,
                fill: t.brand,
                shadowOffset: 3,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                child: Text('+ create & switch: "${_controller.text.trim()}"',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: mono(context, weight: FontWeight.w800, color: t.brandInk)),
              ),
            ),
          ],
          DottedField(
            controller: _controller,
            hint: 'paste task id or search…',
            onChanged: (v) => setState(() => _query = v),
            onSubmitted: (_) {
              if (suggestions.isNotEmpty) {
                _switch(suggestions.first.syncId);
              } else {
                _create();
              }
            },
          ),
        ],
      ),
    );
  }
}

/// A dashed-border input, per the mockup's "paste task id" field.
class DottedField extends StatelessWidget {
  const DottedField({
    super.key,
    required this.controller,
    required this.hint,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final t = neo(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.surface2,
        border: Border.all(color: t.line, width: 2, style: BorderStyle.solid),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          textInputAction: TextInputAction.go,
          style: mono(context, weight: FontWeight.w700),
          decoration: InputDecoration(
            border: InputBorder.none,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            hintText: hint,
            hintStyle: mono(context, color: t.muted),
          ),
        ),
      ),
    );
  }
}

class _FirstRunEmpty extends ConsumerWidget {
  const _FirstRunEmpty();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = neo(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('nothing tracked yet',
                style: mono(context, size: 18, weight: FontWeight.w800), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('create your first activity to start tracking',
                style: mono(context, color: t.muted), textAlign: TextAlign.center),
            const SizedBox(height: 20),
            NeoButton(
              label: '+ new activity',
              primary: true,
              onTap: () => showActivityEditor(context, ref, switchToOnCreate: true),
            ),
          ],
        ),
      ),
    );
  }
}
