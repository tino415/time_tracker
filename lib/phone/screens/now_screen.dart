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
import '../widgets/switch_undo.dart';

/// Focus for the Now screen's paste/search field.
///
/// Held outside the widget so a keyboard shortcut can reach it from any tab —
/// the field itself is buried in a private state class, and the binding that
/// jumps to it fires from the app shell.
final quickSwitchFocusProvider = Provider<FocusNode>((ref) {
  final node = FocusNode(debugLabel: 'quick switch');
  ref.onDispose(node.dispose);
  return node;
});

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
                Text(
                  'no bookmarks yet — star an activity to pin it here',
                  style: mono(context, color: neo(context).muted),
                )
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
    // Offered unconditionally, including while an unnamed block is already
    // running. It used to hide itself then, on the reasoning that the useful
    // action was naming the running block instead — but starting a second
    // unnamed block is exactly what the watch does, and two in a row are two
    // different things to name later, not one thing tapped twice.
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
            Text(
              'pick something below to start',
              style: mono(context, size: 16, weight: FontWeight.w700, color: t.muted),
            ),
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
          // Only the breadcrumb gives way: the dot and TRACKING keep their
          // natural width, and a deep path is cut off at the hero's border
          // instead of pushing the row past it.
          //
          // spaceBetween rather than a Spacer: a Spacer is flexible too, so it
          // would take half the free width and the chip would ellipsize with
          // room to spare. As the only flexible child the chip is offered
          // everything the trailing group does not need, and loose fit lets a
          // short path stay short.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Container(
                  color: onFill,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  child: Text(
                    tree.pathName(acts.first.syncId),
                    maxLines: 1,
                    softWrap: false,
                    // Truncated at the end, losing the leaf, which is right
                    // here: the leaf is already the 24pt headline directly
                    // below, so what this chip uniquely carries is the ancestor
                    // chain. Head-truncation was tried and reverted — a `rtl`
                    // textDirection moves the ellipsis glyph to the left but
                    // still keeps the string's *head*, so it renders "…Work /
                    // Infrastructure": an ellipsis pointing at text that was
                    // never cut.
                    overflow: TextOverflow.ellipsis,
                    style: mono(context, size: 11, weight: FontWeight.w800, color: fill),
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _LiveDot(color: onFill),
                  const SizedBox(width: 6),
                  Text(
                    'TRACKING',
                    style: mono(context, size: 10, weight: FontWeight.w800, color: onFill),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            // No special case for the catch-all: its row is named for reading,
            // so printing the activity's own name keeps this screen and the
            // timeline saying the same word.
            multi ? acts.map((a) => a.name).join('  +  ') : acts.first.name,
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
                  child: Text(
                    '▸ WHAT IS THIS?',
                    style: mono(
                      context,
                      size: 12,
                      weight: FontWeight.w800,
                      spacing: .8,
                      color: fill,
                    ),
                  ),
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
                child: Text(
                  unnamed ? '⋯' : '⋯ EDIT BLOCK',
                  style: mono(context, size: 12, weight: FontWeight.w800, spacing: .8, color: fill),
                ),
              ),
            ],
          ),
          if (multi) ...[
            const SizedBox(height: 6),
            Text(
              '${acts.length} activities · even-split',
              style: mono(context, size: 11, weight: FontWeight.w700, color: onFill),
            ),
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
                Text(
                  'since ${formatTimeOfDay(b.start)}',
                  style: mono(context, size: 12, weight: FontWeight.w700, color: onFill),
                ),
                const SizedBox(width: 8),
                Text(
                  'edit',
                  style: mono(
                    context,
                    size: 10,
                    weight: FontWeight.w800,
                    spacing: .8,
                    color: onFill,
                  ).copyWith(decoration: TextDecoration.underline, decorationColor: onFill),
                ),
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
          Text(
            '✎ ',
            style: mono(context, size: 13, weight: FontWeight.w800, color: onFill),
          ),
          Expanded(
            child: Text(
              comment == null || comment.isEmpty ? 'add a note…' : comment,
              style: mono(
                context,
                size: 13,
                weight: FontWeight.w700,
                color: onFill,
              ).copyWith(fontStyle: (comment == null || comment.isEmpty) ? FontStyle.italic : null),
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
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

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

/// Two lines of 13pt name at 1.15 line-height, plus the tile's vertical padding
/// and its 3px borders. Named so the reason for the number stays with it.
const _tileHeight = 56.0;

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
      // mainAxisExtent, not childAspectRatio: a ratio ties tile *height* to
      // column width, so the tiles grew with the screen and a handful of
      // bookmarks pushed the paste field out of thumb reach. A fixed height
      // keeps a tile two lines of text tall on every device — which is all it
      // has ever needed to be.
      //
      // A maximum width rather than a fixed count, so a desktop pane holds three
      // or four tiles instead of two very wide ones. 220 is chosen to leave every
      // phone at two: a 400pt screen less its gutters is 368, and 368/230 rounds
      // up to 2.
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        mainAxisExtent: _tileHeight,
      ),
      itemBuilder: (_, i) {
        final a = activities[i];
        final fill = parseHexColor(a.color);
        final onFill = ActivityPalette.onFill(fill);
        final active = currentIds.contains(a.syncId);
        // Paste-to-create keeps the id inside the name ("CU-1042 Refund
        // webhook"), so an id line above it would print the id twice and spend
        // one of the tile's two lines doing it.
        final id = a.externalId;
        final showId = id != null && !a.name.contains(id);
        return NeoPressable(
          fill: fill,
          shadowOffset: 4,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          onTap: () => switchWithUndo(context, ref, a.syncId),
          // Centred rather than spaceBetween: at this height there is no room to
          // push a header and a name apart, and the external id now shares the
          // name's line instead of claiming one of its own.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (showId)
                Text(
                  id,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: mono(context, size: 9, weight: FontWeight.w800, color: onFill),
                ),
              Row(
                children: [
                  if (active)
                    Text(
                      '● ',
                      style: mono(context, size: 11, weight: FontWeight.w800, color: onFill),
                    ),
                  Expanded(
                    child: Text(
                      a.name,
                      // One line when the tile also carries an id line, two when
                      // the name has the tile to itself.
                      maxLines: showId ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: mono(
                        context,
                        size: 13,
                        weight: FontWeight.w800,
                        color: onFill,
                        height: 1.15,
                      ),
                    ),
                  ),
                ],
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
    final matches =
        all.where((a) {
          if (q.isEmpty) return true;
          return a.name.toLowerCase().contains(q) ||
              (a.externalId?.toLowerCase().contains(q) ?? false);
        }).toList()..sort((a, b) {
          final la = a.lastUsedAt, lb = b.lastUsedAt;
          if (la != null && lb != null) return lb.compareTo(la);
          if (la != null) return -1;
          if (lb != null) return 1;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
    return matches.take(5).toList();
  }

  Future<void> _switch(String id) async {
    await switchWithUndo(context, ref, id);
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
                  child: Row(
                    children: [
                      NeoSwatch(parseHexColor(a.color), size: 14),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          a.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: mono(context, weight: FontWeight.w700),
                        ),
                      ),
                      if (a.externalId != null)
                        Text(a.externalId!, style: mono(context, size: 11, color: t.muted)),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: NeoPressable(
                onTap: _create,
                fill: t.brand,
                shadowOffset: 3,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                child: Text(
                  '+ create & switch: "${_controller.text.trim()}"',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: mono(context, weight: FontWeight.w800, color: t.brandInk),
                ),
              ),
            ),
          ],
          DottedField(
            controller: _controller,
            focusNode: ref.watch(quickSwitchFocusProvider),
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
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final FocusNode? focusNode;
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
          focusNode: focusNode,
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
            Text(
              'nothing tracked yet',
              style: mono(context, size: 18, weight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'create your first activity to start tracking',
              style: mono(context, color: t.muted),
              textAlign: TextAlign.center,
            ),
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
