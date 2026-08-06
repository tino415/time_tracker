import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

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

  /// The last snapshot the phone put on the wire, so an unchanged catalogue
  /// does not re-send on every stream tick.
  String? _lastSentSnapshot;

  Future<void> start() async {
    _subscriptions.add(_bridge.messages.listen(_onMessage));
    _subscriptions.add(_bridge.reachability.listen(_onReachability));

    // Anything the listener service parked while no engine was running.
    await _bridge.drainPending();

    if (_isWatch) {
      await _bridge.send(const SnapshotRequest());
    } else {
      _subscriptions.add(_watchCatalogue());
    }
  }

  /// Phone side: re-send whenever the bookmarked set or the current activity
  /// changes. Driven off the same streams the UI uses, so there is no separate
  /// notion of "dirty".
  StreamSubscription<Object?> _watchCatalogue() {
    return _activities.watchActivities().listen((_) => _pushSnapshot());
  }

  void _onReachability(WearReachability state) {
    if (state != WearReachability.reachable) return;
    // Reconnected. The watch asks for a fresh set; the phone volunteers one,
    // since the watch may have been away while bookmarks changed.
    if (_isWatch) {
      _bridge.send(const SnapshotRequest());
    } else {
      _lastSentSnapshot = null; // force a send even if nothing changed meanwhile
      _pushSnapshot();
    }
  }

  Future<void> _onMessage(WearMessage message) async {
    switch (message) {
      case SnapshotRequest():
        if (!_isWatch) await _pushSnapshot(force: true);

      case BookmarkSnapshot(:final activities):
        if (_isWatch) await _activities.applyBookmarkSnapshot(activities);

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

    final current = await _changes.currentChange();
    String? currentActivityId;
    if (current != null) {
      final ids = await _changes.activityIdsForChange(current.syncId);
      // A multi-activity block is the retrospective "forgot to switch" case,
      // which the watch has no way to show — treat it as nothing selected
      // rather than picking one arbitrarily.
      if (ids.length == 1) currentActivityId = ids.first;
    }

    final snapshot = BookmarkSnapshot(
      activities: bookmarked,
      currentActivityId: currentActivityId,
    );

    final fingerprint = snapshot.toPayload().toString();
    if (!force && fingerprint == _lastSentSnapshot) return;
    _lastSentSnapshot = fingerprint;

    await _bridge.send(snapshot);
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
