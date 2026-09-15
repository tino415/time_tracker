import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/pointer_signal.dart';
import '../../data/providers.dart';
import '../../data/tracker_controller.dart';
import '../../domain/block.dart';
import '../../domain/reporting.dart';
import '../../domain/unsorted.dart';
import '../../format.dart';
import '../../theme/tokens.dart';
import '../breakpoints.dart';
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
class NowScreen extends ConsumerStatefulWidget {
  const NowScreen({super.key});

  @override
  ConsumerState<NowScreen> createState() => _NowScreenState();
}

class _NowScreenState extends ConsumerState<NowScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _switchTo(String activityId) async {
    await switchWithUndo(context, ref, activityId);
    _search.clear();
  }

  Future<void> _createFromSearch() async {
    final name = _search.text.trim();
    if (name.isEmpty) return;
    _search.clear();
    await showActivityEditor(context, ref, initialName: name, switchToOnCreate: true);
  }

  @override
  Widget build(BuildContext context) {
    final activities = ref.watch(activitiesStreamProvider).valueOrNull ?? const [];
    final current = ref.watch(currentBlockProvider);

    if (activities.isEmpty) return const _FirstRunEmpty();

    // Which edge the chrome band takes, and the only thing width decides here.
    // Every inset that eats the screen arrives from the bottom — the soft
    // keyboard, a short window — so on a phone the band stays down there in
    // thumb reach and the region above it gives way. A wide window has no thumb
    // and does have a controls strip along the top, so the band goes up and the
    // clipping happens where nothing lives.
    //
    // MediaQuery rather than the LayoutBuilder's own constraint: on the wide
    // shell _ReadableWidth caps this screen at contentMaxWidth and the sidebar
    // takes sidebarWidth off it, so the local width answers a different question
    // than "does this window have a sidebar".
    final onTop = MediaQuery.sizeOf(context).width >= sidebarBreakpoint;

    // The band is measured against the body rather than against the infinity a
    // Column hands a non-flexible child, and it scrolls from its own pinned
    // edge: a window too short for both rows loses the start bar, not the field.
    // The field sits on the pinned edge at either width, so dropping the start
    // bar while a query is typed never moves the field under the finger.
    return LayoutBuilder(
      builder: (context, body) => ValueListenableBuilder(
        valueListenable: _search,
        builder: (context, value, _) {
          final query = value.text.trim();
          return Column(
            verticalDirection: onTop ? VerticalDirection.down : VerticalDirection.up,
            children: [
              _ChromeBand(
                onTop: onTop,
                maxHeight: body.maxHeight,
                showStartBar: query.isEmpty,
                controller: _search,
                onSubmitted: () {
                  final matches = matchingActivities(activities, query);
                  if (matches.isEmpty) {
                    _createFromSearch();
                  } else {
                    _switchTo(matches.first.syncId);
                  }
                },
              ),
              Expanded(
                child: query.isEmpty
                    ? _Browse(activities: activities, current: current)
                    : _Matches(
                        matches: matchingActivities(activities, query),
                        query: query,
                        fromTop: onTop,
                        onSwitch: _switchTo,
                        onCreate: _createFromSearch,
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The start bar and the search field, as one block pinned to a screen edge.
///
/// Which edge is the only thing that varies. The border is drawn here rather
/// than by the rows inside, so it stays put when the band scrolls. On the phone
/// that border is one rule against the body — the other three sides are the
/// screen's own edges. On the wide shell the band floats inside the content
/// cap, edges against bare bg, so it takes the full 3px outline every boxed
/// slab in the app has: a single rule there would leave the fill ending
/// mid-air.
class _ChromeBand extends StatelessWidget {
  const _ChromeBand({
    required this.onTop,
    required this.maxHeight,
    required this.showStartBar,
    required this.controller,
    required this.onSubmitted,
  });

  final bool onTop;
  final double maxHeight;
  final bool showStartBar;
  final TextEditingController controller;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final t = neo(context);
    final rule = BorderSide(color: t.line, width: 3);
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: t.surface,
        border: onTop ? Border.fromBorderSide(rule) : Border(top: rule),
      ),
      child: SingleChildScrollView(
        reverse: !onTop,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          // The field is the child on the pinned edge, so it is the one thing
          // here that never moves.
          verticalDirection: onTop ? VerticalDirection.down : VerticalDirection.up,
          children: [
            _QuickSwitchField(controller: controller, onSubmitted: onSubmitted),
            // Nothing to start blind while you are reading matches. The divider
            // goes with it: on its own it would be a rule under nothing.
            if (showStartBar) ...[Container(height: 3, color: t.line), const _StartNowBar()],
          ],
        ),
      ),
    );
  }
}

/// What the screen shows when nothing is typed.
class _Browse extends StatelessWidget {
  const _Browse({required this.activities, required this.current});

  final List<Activity> activities;
  final Block? current;

  @override
  Widget build(BuildContext context) {
    final bookmarked = activities.where((a) => a.bookmarked).toList();
    return ListView(
      // Typing replaces this list and clearing brings it back; without a key
      // that round trip returns you to the top of it.
      key: const PageStorageKey('now-browse'),
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
    );
  }
}

/// What the field matched, in the region the bookmarks otherwise hold.
///
/// Anchored against the band, near the field the matches came from, and
/// scrolling: it used to be a rigid child below the field, and growing was how
/// it pushed the field off the screen.
class _Matches extends StatelessWidget {
  const _Matches({
    required this.matches,
    required this.query,
    required this.fromTop,
    required this.onSwitch,
    required this.onCreate,
  });

  final List<Activity> matches;
  final String query;

  /// Whether the band is above this region. Everything here hangs from the edge
  /// the field is on, and the create row takes that edge, so it is the row that
  /// is always on screen and the matches are what scrolls away.
  final bool fromTop;

  final ValueChanged<String> onSwitch;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final t = neo(context);
    final create = Padding(
      padding: EdgeInsets.only(bottom: fromTop ? 8 : 0),
      child: NeoPressable(
        onTap: onCreate,
        fill: t.brand,
        shadowOffset: 3,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Text(
          '+ create & switch: "$query"',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: mono(context, weight: FontWeight.w800, color: t.brandInk),
        ),
      ),
    );
    // One scroll view, anchored at the field, with the create row on the
    // anchored edge. Order rather than pinning: a row held outside the scroll
    // view is a row that cannot scroll, and a region shorter than it then
    // overflows instead. Here nothing can overflow and the row that acts on
    // what you typed is the last thing a shrinking window takes.
    return SingleChildScrollView(
      reverse: !fromTop,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (fromTop) create,
          for (final a in matches)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: NeoPressable(
                onTap: () => onSwitch(a.syncId),
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
          if (!fromTop) create,
        ],
      ),
    );
  }
}

/// Recency first, then alphabetical: the activity you just left is the one you
/// are most likely coming back to. Five, so the matches stay a glance rather
/// than a list to read; the create row sits on the scroll view's anchored edge
/// and does not depend on this cap to stay on screen.
List<Activity> matchingActivities(List<Activity> all, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  final matches =
      all.where((a) {
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

/// One tap, no typing: open a boundary *now* and decide what it was afterwards.
///
/// The row of the band furthest from the pinned edge, so it is the one that
/// scrolls away when the window runs out of room. The band owns the fill and the
/// rule against the body, which is why those stay put; the divider above this
/// row scrolls with it, because a rule under nothing is worse than no rule.
class _StartNowBar extends ConsumerWidget {
  const _StartNowBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Offered unconditionally, including while an unnamed block is already
    // running. It used to hide itself then, on the reasoning that the useful
    // action was naming the running block instead — but starting a second
    // unnamed block is exactly what the watch does, and two in a row are two
    // different things to name later, not one thing tapped twice.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    'pick something below to start',
                    style: mono(context, size: 16, weight: FontWeight.w700, color: t.muted),
                  ),
                ),
                const SizedBox(width: 12),
                // Its own ticker: this branch has none, and the question the
                // number answers does not depend on anything running. By the
                // minute, because that is how often the printed value changes.
                // The tracking branch ticks per second for the clock beside it;
                // this branch has no clock to pay for.
                SecondTicker(
                  period: const Duration(minutes: 1),
                  builder: (context, now) => _DayLeft(now: now, color: t.muted),
                ),
              ],
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
    final hasPointer = ref.watch(hasPointerProvider);
    final nameText = Text(
      // No special case for the catch-all: its row is named for reading,
      // so printing the activity's own name keeps this screen and the
      // timeline saying the same word.
      multi ? acts.map((a) => a.name).join('  +  ') : acts.first.name,
      style: mono(context, size: 24, weight: FontWeight.w800, color: onFill, height: 1.1),
    );

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
          // Selectable only with a mouse: the hero is otherwise a tap target
          // (the buttons below it, the start-time row), and a drag has nothing
          // to spend on a surface with no gestures of its own.
          hasPointer ? SelectionArea(child: nameText) : nameText,
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
          // One ticker for the clock and its since-row: the clock resets to
          // count from midnight the moment the day turns, and that is exactly
          // when "since 23:00" has to grow its day prefix — one `now` keeps the
          // two from ever telling different stories.
          SecondTicker(
            builder: (context, now) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // The clock answers "how long today" — a block left running
                    // over a weekend counts from midnight instead of printing
                    // 62:14:07. The FittedBox stays anyway: a narrow window can
                    // still be tighter than 40pt of digits.
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          formatElapsedClock(elapsedToday(b.start, now)),
                          style: mono(
                            context,
                            size: 40,
                            weight: FontWeight.w800,
                            color: onFill,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _DayLeft(now: now, color: onFill),
                  ],
                ),
                const SizedBox(height: 6),
                // The one correction worth a direct tap: you almost always
                // notice the start is wrong while looking at the clock it
                // drives. The timestamp grows a weekday once the start is not
                // today — with the clock capped, this row is what still says
                // the block is older than it counts.
                GestureDetector(
                  onTap: () => editBlockStart(context, ref, b),
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    children: [
                      Text(
                        'since ${formatTimestamp(b.start, now)}',
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

/// How much of today is left, beside the clock counting how much of it is gone.
///
/// Sized to fit the space the elapsed clock leaves rather than to match it. On a
/// 320dp screen the hero has 248dp inside it and the 40pt clock takes 168 of
/// them, so this column has about 80 to work with and the caption, not the
/// number, is what sets its width. Growing either one shrinks the clock that is
/// the reason anyone looks at this card.
class _DayLeft extends StatelessWidget {
  const _DayLeft({required this.now, required this.color});

  final DateTime now;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          formatDurationHm(remainingToday(now)),
          style: mono(context, size: 16, weight: FontWeight.w800, color: color, height: 1),
        ),
        const SizedBox(height: 3),
        Text(
          'to midnight',
          style: mono(context, size: 9, weight: FontWeight.w700, spacing: .6, color: color),
        ),
      ],
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
    final noteText = Text(
      comment == null || comment.isEmpty ? 'add a note…' : comment,
      style: mono(
        context,
        size: 13,
        weight: FontWeight.w700,
        color: onFill,
      ).copyWith(fontStyle: (comment == null || comment.isEmpty) ? FontStyle.italic : null),
    );
    final hasPointer = ref.watch(hasPointerProvider);
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
          Expanded(child: hasPointer ? SelectionArea(child: noteText) : noteText),
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

/// The paste/search row, and nothing that grows with what it matched — that is
/// the screen's region, on the other side of the band.
///
/// The band pins this row against a screen edge, so it is the row that survives
/// a soft keyboard and a short window.
///
/// Pasting a task id still works — [matchingActivities] matches `externalId` —
/// but the hint no longer says so, and the only place that does is the keyboard
/// cheatsheet, which a touch build never shows: its button is behind `kIsWeb`
/// and its bindings need a hardware keyboard. So on a phone the paste is
/// undocumented, which is a real cost of the shorter hint rather than an
/// oversight.
class _QuickSwitchField extends ConsumerWidget {
  const _QuickSwitchField({required this.controller, required this.onSubmitted});

  final TextEditingController controller;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: DottedField(
        controller: controller,
        focusNode: ref.watch(quickSwitchFocusProvider),
        hint: 'search or create task',
        onSubmitted: (_) => onSubmitted(),
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
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String hint;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Take the keyboard as soon as this is on screen. For a field that *is* the
  /// surface it opened with — asking someone to click the only thing in a dialog
  /// before they can use it is a step with no purpose.
  ///
  /// The framework's own flag rather than a `requestFocus` after the first
  /// frame: a route animating in moves focus itself as its scope settles, and a
  /// post-frame request races that and loses about as often as it wins.
  final bool autofocus;

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
          autofocus: autofocus,
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
    // Centred where it fits and scrolling where it does not: this is what the
    // screen shows before the first stream emission, so it is laid out at every
    // window size the app is ever opened at, short ones included.
    return SingleChildScrollView(
      child: Center(
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
      ),
    );
  }
}
