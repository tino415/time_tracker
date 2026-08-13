/// The messages the watch and the phone exchange over the Wear Data Layer.
///
/// Kept pure — no channels, no database — so the wire format can be tested on
/// its own. Every message travels as the same envelope the Kotlin bridge
/// builds, `{"type": ..., "payload": {...}}`, which is why each type here
/// carries its own [type] tag and a `toPayload` / `fromPayload` pair.
///
/// Design note: the watch is *not* a second source of truth. It holds a cached
/// snapshot of the bookmarked activities so it can render and act while the
/// phone is asleep, and every tap it makes is relayed as a [SwitchRequest] the
/// phone applies to the real database. The request carries the change's syncId
/// and its timestamp, so a relay that arrives twice — or late — lands as the
/// same row rather than a duplicate boundary.
library;

/// One bookmarked activity, as much of it as the watch needs to draw a tile.
class WearActivity {
  const WearActivity({
    required this.syncId,
    required this.name,
    required this.color,
  });

  final String syncId;
  final String name;

  /// Stored `#RRGGBB`, same as the phone's catalogue.
  final String color;

  Map<String, Object?> toPayload() => {
        'syncId': syncId,
        'name': name,
        'color': color,
      };

  static WearActivity? fromPayload(Object? raw) {
    if (raw is! Map) return null;
    final syncId = raw['syncId'];
    final name = raw['name'];
    final color = raw['color'];
    if (syncId is! String || name is! String || color is! String) return null;
    if (syncId.isEmpty) return null;
    return WearActivity(syncId: syncId, name: name, color: color);
  }

  @override
  bool operator ==(Object other) =>
      other is WearActivity &&
      other.syncId == syncId &&
      other.name == name &&
      other.color == color;

  @override
  int get hashCode => Object.hash(syncId, name, color);
}

sealed class WearMessage {
  const WearMessage();

  String get type;
  Map<String, Object?> toPayload();

  /// Decode an envelope. Returns null for anything unrecognised or malformed —
  /// a peer running an older build must not be able to crash this one.
  static WearMessage? decode(Object? type, Object? payload) {
    if (type is! String) return null;
    final map = payload is Map ? payload : const {};
    return switch (type) {
      BookmarkSnapshot.kind => BookmarkSnapshot.fromPayload(map),
      SwitchRequest.kind => SwitchRequest.fromPayload(map),
      SnapshotRequest.kind => const SnapshotRequest(),
      SyncCredential.kind => SyncCredential.fromPayload(map),
      _ => null,
    };
  }
}

/// Phone → watch: the sync account's token, or null to revoke it.
///
/// The watch cannot realistically be given this any other way — it is 32
/// generated characters on a 227px screen with no camera — so it inherits the
/// phone's. That is what lets the watch reach the server on its own instead of
/// parking every switch in the relay queue until the phone app is next opened.
///
/// The token is the entire security boundary, so two things matter. It travels
/// only over the Wear Data Layer, the same paired, encrypted channel already
/// carrying the catalogue — nothing new is exposed. And null is a real value,
/// not an absence: leaving the account on the phone sends a null so the watch
/// stops being a device holding a working credential for an account you think
/// you have disconnected.
class SyncCredential extends WearMessage {
  const SyncCredential({required this.token});

  static const kind = 'sync_credential';

  final String? token;

  @override
  String get type => kind;

  @override
  Map<String, Object?> toPayload() => {'token': token};

  static SyncCredential fromPayload(Map<Object?, Object?> payload) {
    final token = payload['token'];
    // Anything that is not a usable token revokes. A malformed message must not
    // leave a stale credential in place — failing safe here means failing shut.
    return SyncCredential(token: token is String && token.isNotEmpty ? token : null);
  }
}

/// What the phone is tracking right now, in enough detail for the watch to
/// reproduce the block locally.
///
/// The activity travels whole rather than as an id: the phone may be tracking
/// something that is *not* bookmarked, so the watch would otherwise have no row
/// to point its block at. [changeId] and [startedAt] are the phone's own, so the
/// watch writes the same boundary rather than a second one — and can run a live
/// elapsed clock instead of guessing when it started.
class CurrentBlock {
  const CurrentBlock({
    required this.changeId,
    required this.startedAt,
    required this.activity,
  });

  final String changeId;
  final DateTime startedAt;
  final WearActivity activity;

  Map<String, Object?> toPayload() => {
        'changeId': changeId,
        'startedAt': startedAt.millisecondsSinceEpoch,
        'activity': activity.toPayload(),
      };

  static CurrentBlock? fromPayload(Object? raw) {
    if (raw is! Map) return null;
    final changeId = raw['changeId'];
    final startedAt = raw['startedAt'];
    final activity = WearActivity.fromPayload(raw['activity']);
    if (changeId is! String || changeId.isEmpty) return null;
    if (startedAt is! int || activity == null) return null;
    return CurrentBlock(
      changeId: changeId,
      startedAt: DateTime.fromMillisecondsSinceEpoch(startedAt),
      activity: activity,
    );
  }
}

/// Phone → watch: the whole bookmarked set, plus what is tracking right now.
///
/// A full snapshot rather than a diff: the set is small, and it means a watch
/// that missed messages while off the wrist recovers completely from the next
/// one instead of accumulating drift.
class BookmarkSnapshot extends WearMessage {
  const BookmarkSnapshot({required this.activities, this.current});

  static const kind = 'bookmarks';

  final List<WearActivity> activities;

  /// The open block, or null when the phone tracks nothing — or tracks a
  /// multi-activity ("forgot to switch") block, which the watch cannot show.
  final CurrentBlock? current;

  @override
  String get type => kind;

  @override
  Map<String, Object?> toPayload() => {
        'activities': [for (final a in activities) a.toPayload()],
        'current': current?.toPayload(),
      };

  static BookmarkSnapshot fromPayload(Map<Object?, Object?> payload) {
    final raw = payload['activities'];
    final list = raw is List ? raw : const [];
    return BookmarkSnapshot(
      // Unparseable entries are skipped rather than failing the whole snapshot:
      // a peer on a newer build may send fields this one does not know.
      activities: [for (final entry in list) ?WearActivity.fromPayload(entry)],
      current: CurrentBlock.fromPayload(payload['current']),
    );
  }
}

/// Watch → phone: "start tracking this, as of then".
///
/// [changeSyncId] is minted on the watch so the relay is idempotent: the phone
/// upserts that id, so a message delivered twice — or replayed from the
/// listener service's queue after the app restarts — cannot open two boundaries.
class SwitchRequest extends WearMessage {
  const SwitchRequest({
    required this.changeSyncId,
    required this.activityId,
    required this.at,
  });

  static const kind = 'switch';

  final String changeSyncId;
  final String activityId;
  final DateTime at;

  @override
  String get type => kind;

  @override
  Map<String, Object?> toPayload() => {
        'changeSyncId': changeSyncId,
        'activityId': activityId,
        // Epoch millis, matching how the boundary is stored.
        'at': at.millisecondsSinceEpoch,
      };

  static SwitchRequest? fromPayload(Map<Object?, Object?> payload) {
    final changeSyncId = payload['changeSyncId'];
    final activityId = payload['activityId'];
    final at = payload['at'];
    if (changeSyncId is! String || changeSyncId.isEmpty) return null;
    if (activityId is! String || activityId.isEmpty) return null;
    if (at is! int) return null;
    return SwitchRequest(
      changeSyncId: changeSyncId,
      activityId: activityId,
      at: DateTime.fromMillisecondsSinceEpoch(at),
    );
  }
}

/// Watch → phone: "send me a snapshot". Issued on watch start and whenever the
/// phone becomes reachable again, so the watch never shows a stale set for
/// longer than it has to.
class SnapshotRequest extends WearMessage {
  const SnapshotRequest();

  static const kind = 'snapshot_request';

  @override
  String get type => kind;

  @override
  Map<String, Object?> toPayload() => const {};
}

/// How the peer device can be reached, as reported by the capability client.
enum WearReachability {
  /// No paired device advertising the capability at all.
  notPaired,

  /// Paired, but out of range / asleep — a send will fail.
  pairedButNotReachable,

  reachable;

  static WearReachability parse(Object? raw) => switch (raw) {
        'reachable' => WearReachability.reachable,
        'pairedButNotReachable' => WearReachability.pairedButNotReachable,
        _ => WearReachability.notPaired,
      };
}
