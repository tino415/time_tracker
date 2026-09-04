import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../domain/unsorted.dart';
import '../domain/wear_protocol.dart';
import 'providers.dart';
import 'repositories.dart';
import 'sync_service.dart';
import 'sync_store.dart';
import 'tracker_controller.dart';
import 'wear_bridge.dart';
import 'wear_outbox.dart';

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
    required SyncStore syncStore,
    required WearOutboxStore outbox,
    required bool isWatch,
  }) : _bridge = bridge,
       _activities = activities,
       _changes = changes,
       _syncStore = syncStore,
       _outbox = outbox,
       _isWatch = isWatch,
       // Built from the same two repositories rather than passed in: assign and
       // retime are edits of an existing boundary, exactly what TrackerController
       // exists to make safely, and there is no reason for this class to
       // reimplement the clamping it already does for moveBoundary.
       _controller = TrackerController(activities, changes);

  final WearBridge _bridge;
  final ActivityRepository _activities;
  final ChangeRepository _changes;
  final TrackerController _controller;

  /// Read on the phone, written on the watch — the relay is how the watch gets
  /// an account at all.
  final SyncStore _syncStore;

  /// Where an undelivered relay waits for the peer to come back.
  final WearOutboxStore _outbox;

  final bool _isWatch;

  /// One drain at a time. Reachability can flip twice in a second at the edge
  /// of range, and two drains would read the same entry and send it twice.
  bool _draining = false;

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

    // And anything *this* device failed to send before it was last killed. Not
    // gated on the form factor: only the watch relays today, but the outbox
    // belongs to whichever side could not deliver, and a phone with an empty one
    // pays a single query for the symmetry.
    await _drainOutbox();

    if (_isWatch) {
      _beginRequestingSnapshot();
      _subscriptions.addAll(_cacheOwnCatalogue());
    } else {
      _subscriptions.addAll(_watchCatalogue());
    }
  }

  /// Send what was parked while the peer was away, oldest first.
  ///
  /// Stops at the first failure rather than working through the rest: they all
  /// go to the same peer, so one undelivered message means the next will be too,
  /// and stopping keeps the backlog in the order it was made.
  Future<void> _drainOutbox() async {
    if (_draining) return;
    _draining = true;
    try {
      for (final entry in await _outbox.pending()) {
        final message = WearOutboxStore.decode(entry);
        // Unreadable, so it will not become readable. Drop it rather than
        // blocking everything behind it forever.
        if (message == null) {
          await _outbox.remove(entry.id);
          continue;
        }
        if (!await _bridge.send(message)) return;
        await _outbox.remove(entry.id);
      }
    } finally {
      _draining = false;
    }
  }

  /// Relay [message], parking it if the peer is not there.
  ///
  /// The one place the watch's three requests go out, so the answer `send`
  /// already returns cannot be dropped on the floor at one call site and
  /// honoured at another.
  Future<void> _relay(WearMessage message) async {
    if (await _bridge.send(message)) return;
    await _outbox.add(message);
  }

  /// Watch side: ask for a snapshot until one arrives.
  ///
  /// A single request at startup is not enough. Capability discovery may not
  /// have finished when the app opens, so the request goes to nobody; and if the
  /// phone app is not running it cannot answer at all — its listener service
  /// deliberately drops snapshot requests rather than replaying stale ones. So
  /// the watch keeps asking, with a widening gap, until a snapshot lands.
  ///
  /// Stopping on *delivery* was the bug that made this feature look broken on
  /// real devices. `send` reporting true only means the peer device took the
  /// message — which succeeds even with the phone app closed, because Android
  /// wakes the listener service to receive it, and that service then drops it.
  /// The watch asked once into a void, believed it had asked successfully, and
  /// never asked again; meanwhile Samsung freezes the phone app every couple of
  /// minutes, so the window where it can answer is narrow and easily missed.
  ///
  /// Delivery is not an answer. Only [_gotSnapshot] stops this.
  void _beginRequestingSnapshot() {
    _snapshotRetry?.cancel();
    var attempt = 0;

    Future<void> ask() async {
      if (_gotSnapshot) return;
      // The request carries what this device already knows about the account, so
      // the phone can answer with a credential only when it holds something
      // newer. That is what makes the token travel once rather than routinely.
      await _bridge.send(SnapshotRequest(credentialVersion: await _syncStore.credentialVersion()));
      if (_gotSnapshot) return;
      attempt++;
      // 2s, 4s, 8s … capped at 32. Cheap enough to leave running indefinitely:
      // a watch with nobody to talk to wakes twice a minute, not continuously —
      // which was already the accepted cost when the peer was unreachable, and
      // is the same cost when it is merely asleep.
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
      // Joining an account, and leaving one, are both things the watch has to
      // hear about — and neither touches the catalogue, so neither would reach
      // it on the streams above. Pushed unprompted so a watch that *is* present
      // hears immediately rather than waiting until it next asks.
      _syncStore.watchToken().listen((token) async {
        await _pushCredential(token, await _syncStore.credentialVersion());
      }),
    ];
  }

  /// Watch side: caches its own state on the same triggers [_watchCatalogue]
  /// pushes on, but writes rather than sends — the watch has nobody to push a
  /// snapshot *to*. This is what lets a widget or a watch-face complication
  /// read something true without a running Flutter engine, the same trick the
  /// phone uses to answer the watch's own `snapshot_request` while dead.
  List<StreamSubscription<Object?>> _cacheOwnCatalogue() {
    return [
      _activities.watchActivities().listen((_) => _cacheSnapshot()),
      _changes.watchChanges().listen((_) => _cacheSnapshot()),
    ];
  }

  Future<void> _cacheSnapshot() async {
    final snapshot = await _buildSnapshot();
    await _bridge.cacheCurrent(snapshot.toPayload());
  }

  /// Watch → phone: "you have something I do not".
  ///
  /// Re-uses the snapshot request, which already carries this device's
  /// credential version, rather than adding a message that would say the same
  /// thing. The phone answers with the credential because its version is newer,
  /// and re-sends the snapshot, which is cheap and idempotent.
  ///
  /// Sent once per snapshot that advertises something newer. If it fails to
  /// deliver, the next snapshot advertises the same gap and prompts it again —
  /// so the retry is driven by traffic that already exists rather than a timer,
  /// and a device with nothing to fetch never sends anything at all.
  ///
  /// The cooldown stops that becoming a ping-pong. The request makes the phone
  /// re-send its snapshot, and if the credential half is lost while the snapshot
  /// half arrives, the answer would prompt the very question it answers — as
  /// fast as the two devices can talk. Bounded here, so a persistent failure
  /// costs one exchange a minute rather than a spin.
  static const _credentialCooldown = Duration(minutes: 1);
  DateTime? _askedForCredentialAt;

  Future<void> _requestCredential() async {
    final now = DateTime.now();
    final last = _askedForCredentialAt;
    if (last != null && now.difference(last) < _credentialCooldown) return;
    _askedForCredentialAt = now;

    await _bridge.send(SnapshotRequest(credentialVersion: await _syncStore.credentialVersion()));
  }

  /// Phone → watch, when the account changes and when a watch asks for
  /// something newer than it has.
  ///
  /// Deliberately *not* attached to every snapshot. Snapshots go out on every
  /// catalogue change and every switch, so riding along would put a bearer token
  /// on the wire dozens of times a day to deliver a value that needs to arrive
  /// once. The version is what makes asking sufficient.
  Future<void> _pushCredential(String? token, int version) async {
    if (_isWatch) return;
    await _bridge.send(SyncCredential(token: token, version: version));
  }

  void _onReachability(WearReachability state) {
    if (state != WearReachability.reachable) return;
    // The backlog first, and on both sides for the same reason it drains on
    // start: it is older than anything the snapshot below will say, so sending
    // it first means the snapshot already accounts for it.
    unawaited(_drainOutbox());
    // Reconnected. The watch asks again from scratch; the phone volunteers one,
    // since the watch may have been away while bookmarks changed.
    if (_isWatch) {
      _gotSnapshot = false;
      _beginRequestingSnapshot();
    } else {
      _lastSentSnapshot = null; // force a send even if nothing changed meanwhile
      _pushSnapshot();
      // Reconnected: the watch may have been away while the account changed, and
      // it will ask anyway — but volunteering saves a round trip.
      unawaited(() async {
        await _pushCredential(await _syncStore.token(), await _syncStore.credentialVersion());
      }());
    }
  }

  Future<void> _onMessage(WearMessage message) async {
    switch (message) {
      case SnapshotRequest(:final credentialVersion):
        if (_isWatch) return;
        await _pushSnapshot(force: true);
        // Answered only when this device holds something the asker does not.
        //
        // The watch asks on start and on every reconnect, so this is the moment
        // a revocation reaches one that was away when it happened — and equally
        // the moment a watch that is already current is told nothing, which is
        // why the token is not on the wire during ordinary use.
        final mine = await _syncStore.credentialVersion();
        if (mine > credentialVersion) {
          await _pushCredential(await _syncStore.token(), mine);
        }

      case SyncCredential(:final token, :final version):
        // Phone → watch only. A watch cannot hand the phone an account, and
        // honouring it in that direction would let a lost watch dictate which
        // server the phone talks to.
        if (!_isWatch) return;
        // Newest wins. The listener parks messages while the app is down and
        // drains them on next start, so a stale grant really can arrive after a
        // fresh revocation — without this it would quietly re-grant it.
        if (version <= await _syncStore.credentialVersion()) return;
        await _syncStore.adoptCredential(token, version);

      case BookmarkSnapshot(:final activities, :final current, :final credentialVersion):
        if (!_isWatch) return;
        _gotSnapshot = true;
        _snapshotRetry?.cancel();
        // The phone has an account this device has not heard about, so ask for
        // it — once, on evidence, rather than polling on the chance.
        //
        // Waiting for a snapshot and waiting for a credential are separate
        // conditions, and conflating them is what stranded a watch that took a
        // snapshot while the credential push was failing: it had what it was
        // waiting for and went quiet still holding no account.
        if (credentialVersion > await _syncStore.credentialVersion()) {
          await _requestCredential();
        }
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
            version: current.version,
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

      case AssignRequest(:final changeSyncId, :final activityId, :final version):
        // Adopted by version rather than re-applied as a local edit. See
        // ChangeRepository.applyRelayedRetime for why that distinction is the
        // whole safety argument for replaying a correction at all.
        await _changes.applyRelayedAssign(
          changeSyncId: changeSyncId,
          activityId: activityId,
          version: version,
        );
        // Pushed even when the correction was refused: a refusal means this
        // device holds the newer answer, which is exactly when the peer most
        // needs to hear it. On acceptance it is the mirror of SwitchRequest —
        // how the sender learns its correction was taken.
        if (!_isWatch) await _pushSnapshot(force: true);

      case RetimeRequest(:final changeSyncId, :final at, :final version):
        await _changes.applyRelayedRetime(changeSyncId: changeSyncId, at: at, version: version);
        // Same reasoning as above, and the mechanism that settles a
        // disagreement: CurrentBlock carries startedAt, and applyPeerCurrentBlock
        // re-points and retimes the same change id, so a refused correction
        // comes back to the sender as this device's answer.
        if (!_isWatch) await _pushSnapshot(force: true);
    }
  }

  /// Built by both sides from the same two repositories, so the cache one
  /// writes and the snapshot the other sends are always the same shape.
  Future<BookmarkSnapshot> _buildSnapshot() async {
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
            version: change.version,
            activity: WearActivity(
              syncId: tracked.syncId,
              name: tracked.name,
              color: tracked.color,
            ),
          );
        }
      }
    }

    return BookmarkSnapshot(
      activities: bookmarked,
      current: current,
      // The number only. It is what lets the watch fetch a credential when there
      // is one to fetch, and stay silent when there is not.
      credentialVersion: await _syncStore.credentialVersion(),
    );
  }

  /// Phone → watch. [force] skips the unchanged-since-last-send check.
  Future<void> _pushSnapshot({bool force = false}) async {
    if (_isWatch) return;

    final snapshot = await _buildSnapshot();

    // Cached on every build, delivered or not: this is what lets the phone's
    // WearListenerService answer a `snapshot_request` while the app is dead,
    // and a send that fails to reach anyone still leaves the best available
    // answer on disk for next time. Separate from _lastSentSnapshot below,
    // which is about when to re-send, not about what belongs in the cache.
    await _bridge.cacheCurrent(snapshot.toPayload());

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

    await _changes.applyRelayedSwitch(changeSyncId: changeSyncId, activityId: activityId, at: when);
    await _activities.touchUsed(activityId, when);

    await _relay(SwitchRequest(changeSyncId: changeSyncId, activityId: activityId, at: when));
  }

  /// Watch side: re-point the running block at [activityId] without opening a
  /// new boundary — answering an unnamed block, or correcting a mis-pointed one.
  ///
  /// Written locally first, same write-then-relay shape as [requestSwitch].
  Future<void> requestAssign({required String changeSyncId, required String activityId}) async {
    await _controller.assignBlock(changeSyncId, activityId);
    final landed = await _changes.changeById(changeSyncId);
    if (landed == null) return;
    await _relay(
      AssignRequest(changeSyncId: changeSyncId, activityId: activityId, version: landed.version),
    );
  }

  /// Watch side: correct when the running block started.
  ///
  /// [at] is only ever a request *here*. `moveBoundary` clamps it against this
  /// device's neighbours, and what goes on the wire is where it actually landed,
  /// not what was asked for — the receiver adopts that value rather than
  /// re-deriving one, so sending the raw request would mean the two devices
  /// clamped against different neighbours and disagreed about the answer.
  Future<void> requestRetime({required String changeSyncId, required DateTime at}) async {
    await _controller.moveBoundary(changeSyncId, at);
    final landed = await _changes.changeById(changeSyncId);
    if (landed == null) return;
    await _relay(
      RetimeRequest(changeSyncId: changeSyncId, at: landed.changedAt, version: landed.version),
    );
  }

  /// Move the boundary by [by], reading where it currently is rather than being
  /// told — the shape a nudge button wants.
  ///
  /// The caller cannot do this arithmetic itself. Whatever start it is holding
  /// came from a frame, and a run of quick taps all read the same one, compute
  /// the same instant and land as a single minute. Reading here means each call
  /// sees what the one before it committed, including any clamping, so the taps
  /// add up. Callers still have to run these one at a time — two overlapping
  /// reads are the same bug a frame away.
  ///
  /// What goes on the wire is still the absolute instant [requestRetime] sends,
  /// not [by]: a delta replayed from the queue would move the boundary twice.
  Future<void> requestNudge({required String changeSyncId, required Duration by}) async {
    for (final change in await _changes.loadChanges()) {
      if (change.syncId != changeSyncId) continue;
      await requestRetime(changeSyncId: changeSyncId, at: change.changedAt.add(by));
      return;
    }
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
    syncStore: ref.watch(syncStoreProvider),
    outbox: ref.watch(wearOutboxProvider),
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
