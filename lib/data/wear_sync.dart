import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../domain/unsorted.dart';
import '../domain/wear_protocol.dart';
import 'providers.dart';
import 'repositories.dart';
import 'wear_bridge.dart';

const _uuid = Uuid();

/// Keeps the watch and the phone in step over the Wear Data Layer.
///
/// Both halves live here rather than in two classes, because the protocol only
/// makes sense read as a pair:
///
///   watch → phone   `snapshot_request`  "tell me the bookmarks"
///   phone → watch   `bookmarks`          the set + what is tracking now
///   watch → phone   `switch`             "start this, as of then"
///
/// The phone owns the database. The watch keeps a cached copy of the bookmarked
/// activities so it can draw tiles and act with the phone asleep, and every tap
/// it makes is written locally *and* relayed under the same change id — so the
/// two databases converge on one row rather than two boundaries.
class WearSyncService {
  WearSyncService({
    required WearBridge bridge,
    required ActivityRepository activities,
    required ChangeRepository changes,
    required bool isWatch,
  })  : _bridge = bridge,
        _activities = activities,
        _changes = changes,
        _isWatch = isWatch;

  final WearBridge _bridge;
  final ActivityRepository _activities;
  final ChangeRepository _changes;
  final bool _isWatch;

  final _subscriptions = <StreamSubscription<Object?>>[];

  /// The last snapshot the phone *delivered*, so an unchanged catalogue does not
  /// re-send on every stream tick. Null again after a failed send, so the next
  /// change retries rather than assuming the peer is up to date.
  String? _lastSentSnapshot;

  /// Watch side: set once a snapshot has arrived, which stops the retry loop.
  bool _gotSnapshot = false;
  Timer? _snapshotRetry;

  Future<void> start() async {
    _subscriptions.add(_bridge.messages.listen(_onMessage));
    _subscriptions.add(_bridge.reachability.listen(_onReachability));

    // Anything the listener service parked while no engine was running.
    await _bridge.drainPending();

    if (_isWatch) {
      _beginRequestingSnapshot();
    } else {
      _subscriptions.addAll(_watchCatalogue());
    }
  }

  /// Watch side: ask for a snapshot until one arrives.
  ///
  /// A single request at startup is not enough. Capability discovery may not
  /// have finished when the app opens, so the request goes to nobody; and if the
  /// phone app is not running it cannot answer at all — its listener service
  /// deliberately drops snapshot requests rather than replaying stale ones. So
  /// the watch keeps asking, with a widening gap, and stops the moment a
  /// snapshot lands.
  void _beginRequestingSnapshot() {
    _snapshotRetry?.cancel();
    var attempt = 0;

    Future<void> ask() async {
      if (_gotSnapshot) return;
      final delivered = await _bridge.send(const SnapshotRequest());
      if (delivered || _gotSnapshot) return;
      attempt++;
      // 2s, 4s, 8s … capped. Cheap enough to leave running: an unpaired watch
      // wakes a few times a minute, not continuously.
      final seconds = (1 << attempt.clamp(1, 5)).clamp(2, 32);
      _snapshotRetry = Timer(Duration(seconds: seconds), ask);
    }

    unawaited(ask());
  }

  /// Phone side: re-send whenever the bookmarked set *or what is tracking*
  /// changes. Driven off the same streams the UI uses, so there is no separate
  /// notion of "dirty".
  ///
  /// Both streams are needed. A switch does happen to touch the activity stream
  /// (it bumps recency), but relying on that would make the watch's view of
  /// "what is running" depend on a side effect of the autocomplete.
  List<StreamSubscription<Object?>> _watchCatalogue() {
    return [
      _activities.watchActivities().listen((_) => _pushSnapshot()),
      _changes.watchChanges().listen((_) => _pushSnapshot()),
    ];
  }

  void _onReachability(WearReachability state) {
    if (state != WearReachability.reachable) return;
    // Reconnected. The watch asks again from scratch; the phone volunteers one,
    // since the watch may have been away while bookmarks changed.
    if (_isWatch) {
      _gotSnapshot = false;
      _beginRequestingSnapshot();
    } else {
      _lastSentSnapshot = null; // force a send even if nothing changed meanwhile
      _pushSnapshot();
    }
  }

  Future<void> _onMessage(WearMessage message) async {
    switch (message) {
      case SnapshotRequest():
        if (!_isWatch) await _pushSnapshot(force: true);

      case BookmarkSnapshot(:final activities, :final current):
        if (!_isWatch) return;
        _gotSnapshot = true;
        _snapshotRetry?.cancel();
        await _activities.applyBookmarkSnapshot(activities);
        if (current != null) {
          // The tracked activity may not be bookmarked, so it needs a row of its
          // own before the block can reference it.
          await _activities.ensurePeerActivity(current.activity);
          // Same change id and instant as the phone's, so this reproduces that
          // boundary rather than inventing a second one.
          //
          // Not applyRelayedSwitch: that skips a change it already has, which is
          // right for a one-off event but wrong for a snapshot. The same block
          // legitimately comes back re-pointed once the phone names it, and
          // skipping it leaves the watch stuck on "unnamed".
          await _changes.applyPeerCurrentBlock(
            changeSyncId: current.changeId,
            activityId: current.activity.syncId,
            at: current.startedAt,
          );
        }

      case SwitchRequest(:final changeSyncId, :final activityId, :final at):
        // Applied on whichever side receives it. In practice that is the phone,
        // but the same handler on the watch makes a future phone → watch relay
        // work without new code.
        final opened = await _changes.applyRelayedSwitch(
          changeSyncId: changeSyncId,
          activityId: activityId,
          at: at,
        );
        if (opened) {
          await _activities.touchUsed(activityId, at);
          // The peer's view of "what is tracking" just changed.
          if (!_isWatch) await _pushSnapshot(force: true);
        }
    }
  }

  /// Phone → watch. [force] skips the unchanged-since-last-send check.
  Future<void> _pushSnapshot({bool force = false}) async {
    if (_isWatch) return;

    final all = await _activities.loadActivities();
    final bookmarked = [
      for (final a in all)
        if (a.bookmarked && a.deletedAt == null)
          WearActivity(syncId: a.syncId, name: a.name, color: a.color),
    ];

    final change = await _changes.currentChange();
    CurrentBlock? current;
    if (change != null) {
      final ids = await _changes.activityIdsForChange(change.syncId);
      // A multi-activity block is the retrospective "forgot to switch" case,
      // which the watch has no way to show — send nothing rather than picking
      // one arbitrarily.
      if (ids.length == 1) {
        final tracked = all.where((a) => a.syncId == ids.first).firstOrNull;
        if (tracked != null) {
          current = CurrentBlock(
            changeId: change.syncId,
            startedAt: change.changedAt,
            activity: WearActivity(
              syncId: tracked.syncId,
              name: tracked.name,
              color: tracked.color,
            ),
          );
        }
      }
    }

    final snapshot = BookmarkSnapshot(activities: bookmarked, current: current);

    final fingerprint = snapshot.toPayload().toString();
    if (!force && fingerprint == _lastSentSnapshot) return;

    // Recorded only on delivery. Marking it sent regardless is what made a
    // rename vanish: the push went out while nothing was reachable, the phone
    // considered that state delivered, and no later change re-sent it.
    final delivered = await _bridge.send(snapshot);
    _lastSentSnapshot = delivered ? fingerprint : null;
  }

  /// Watch side: start tracking *something*, without deciding what.
  ///
  /// The catch-all has to exist locally before the boundary can point at it —
  /// the phone only sends *bookmarked* activities, and this one is not a
  /// bookmark. Its id is fixed, so the row the watch creates and the row the
  /// phone creates are the same row once they meet.
  Future<void> startUnsorted() async {
    await _activities.ensureUnsorted();
    await requestSwitch(kUnsortedActivityId);
  }

  /// Watch side: start tracking [activityId].
  ///
  /// Written locally first so the tile reacts immediately even with the phone
  /// out of range, then relayed under the id just minted. If the relay fails,
  /// the local row still carries that id, so a later sync reconciles rather
  /// than duplicating.
  Future<void> requestSwitch(String activityId, {DateTime? at}) async {
    final changeSyncId = _uuid.v4();
    final when = at ?? DateTime.now();

    await _changes.applyRelayedSwitch(
      changeSyncId: changeSyncId,
      activityId: activityId,
      at: when,
    );
    await _activities.touchUsed(activityId, when);

    await _bridge.send(SwitchRequest(
      changeSyncId: changeSyncId,
      activityId: activityId,
      at: when,
    ));
  }

  void dispose() {
    _snapshotRetry?.cancel();
    _snapshotRetry = null;
    for (final s in _subscriptions) {
      s.cancel();
    }
    _subscriptions.clear();
  }
}

final wearSyncProvider = Provider<WearSyncService>((ref) {
  final service = WearSyncService(
    bridge: ref.watch(wearBridgeProvider),
    activities: ref.watch(activityRepositoryProvider),
    changes: ref.watch(changeRepositoryProvider),
    isWatch: ref.watch(isWatchProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Whether this build is running on a Wear OS device. Overridden in `main()`
/// after platform detection; defaults to false so tests take the phone branch.
final isWatchProvider = Provider<bool>((ref) => false);

/// Live reachability of the peer, for the watch's connection dot.
final wearReachabilityProvider = StreamProvider<WearReachability>((ref) {
  return ref.watch(wearBridgeProvider).reachability;
});
