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
  const WearActivity({required this.syncId, required this.name, required this.color});

  final String syncId;
  final String name;

  /// Stored `#RRGGBB`, same as the phone's catalogue.
  final String color;

  Map<String, Object?> toPayload() => {'syncId': syncId, 'name': name, 'color': color};

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
      other is WearActivity && other.syncId == syncId && other.name == name && other.color == color;

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
      AssignRequest.kind => AssignRequest.fromPayload(map),
      RetimeRequest.kind => RetimeRequest.fromPayload(map),
      SnapshotRequest.kind => SnapshotRequest.fromPayload(map),
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
  const SyncCredential({required this.token, required this.version});

  static const kind = 'sync_credential';

  final String? token;

  /// How many times the account has been granted or revoked. Newest wins, the
  /// same rule the rest of the data model uses.
  ///
  /// Not decoration: the listener service parks messages while the app is down
  /// and drains them on next start, so a stale grant really can arrive after a
  /// fresh revocation. Without a version that would silently re-grant a token
  /// you had taken away.
  final int version;

  @override
  String get type => kind;

  @override
  Map<String, Object?> toPayload() => {'token': token, 'version': version};

  static SyncCredential fromPayload(Map<Object?, Object?> payload) {
    final token = payload['token'];
    final version = payload['version'];
    // Anything that is not a usable token revokes. A malformed message must not
    // leave a stale credential in place — failing safe here means failing shut.
    //
    // A missing version reads as 0, which loses to everything: a peer too old to
    // send one cannot overwrite a credential this device already has.
    return SyncCredential(
      token: token is String && token.isNotEmpty ? token : null,
      version: version is int ? version : 0,
    );
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
    this.version,
  });

  final String changeId;
  final DateTime startedAt;
  final WearActivity activity;

  /// The sender's version of this change row, so the receiver's copy lands on
  /// the sender's counter instead of the column default. Two devices can only
  /// compare versions if they started from the same one.
  ///
  /// Optional, unlike the version on [AssignRequest] and [RetimeRequest]:
  /// refusing a snapshot from a peer too old to send it would leave the watch
  /// with nothing to draw, where refusing one correction loses only that
  /// correction.
  final int? version;

  Map<String, Object?> toPayload() => {
    'changeId': changeId,
    'startedAt': startedAt.millisecondsSinceEpoch,
    'activity': activity.toPayload(),
    'version': version,
  };

  static CurrentBlock? fromPayload(Object? raw) {
    if (raw is! Map) return null;
    final changeId = raw['changeId'];
    final startedAt = raw['startedAt'];
    final version = raw['version'];
    final activity = WearActivity.fromPayload(raw['activity']);
    if (changeId is! String || changeId.isEmpty) return null;
    if (startedAt is! int || activity == null) return null;
    return CurrentBlock(
      changeId: changeId,
      startedAt: DateTime.fromMillisecondsSinceEpoch(startedAt),
      activity: activity,
      version: version is int ? version : null,
    );
  }
}

/// Phone → watch: the whole bookmarked set, plus what is tracking right now.
///
/// A full snapshot rather than a diff: the set is small, and it means a watch
/// that missed messages while off the wrist recovers completely from the next
/// one instead of accumulating drift.
class BookmarkSnapshot extends WearMessage {
  const BookmarkSnapshot({required this.activities, this.current, this.credentialVersion = 0});

  static const kind = 'bookmarks';

  final List<WearActivity> activities;

  /// The open block, or null when the phone tracks nothing — or tracks a
  /// multi-activity ("forgot to switch") block, which the watch cannot show.
  final CurrentBlock? current;

  /// How many times the sender's account has been granted or revoked — the
  /// number only, never the token.
  ///
  /// This is how the watch learns there is a credential to fetch without ever
  /// guessing. Polling for one is not an option: sync is opt-in, so most watches
  /// have nothing coming, and a device asking every half minute forever on the
  /// chance that it might is a battery cost for nothing. Advertised here instead,
  /// on a message the phone already sends whenever the catalogue changes or the
  /// peer reconnects, so it costs no extra traffic at all.
  ///
  /// When both sides sit at 0 — no account anywhere — nothing is ever asked and
  /// nothing is ever sent. That is the common case, and it is silent.
  ///
  /// The number is not a secret. It says how often the account changed and
  /// nothing else: no token, and no hint of one.
  final int credentialVersion;

  @override
  String get type => kind;

  @override
  Map<String, Object?> toPayload() => {
    'activities': [for (final a in activities) a.toPayload()],
    'current': current?.toPayload(),
    'credentialVersion': credentialVersion,
  };

  static BookmarkSnapshot fromPayload(Map<Object?, Object?> payload) {
    final raw = payload['activities'];
    final list = raw is List ? raw : const [];
    final version = payload['credentialVersion'];
    return BookmarkSnapshot(
      // Unparseable entries are skipped rather than failing the whole snapshot:
      // a peer on a newer build may send fields this one does not know.
      activities: [for (final entry in list) ?WearActivity.fromPayload(entry)],
      current: CurrentBlock.fromPayload(payload['current']),
      // A peer too old to advertise one reads as 0, which is never newer than
      // anything — so an older phone simply never prompts a fetch, rather than
      // prompting one that cannot be answered.
      credentialVersion: version is int ? version : 0,
    );
  }
}

/// Watch → phone: "start tracking this, as of then".
///
/// [changeSyncId] is minted on the watch so the relay is idempotent: the phone
/// upserts that id, so a message delivered twice — or replayed from the
/// listener service's queue after the app restarts — cannot open two boundaries.
class SwitchRequest extends WearMessage {
  const SwitchRequest({required this.changeSyncId, required this.activityId, required this.at});

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

/// Watch → phone: "the block I'm already running is actually [activityId], and
/// my row for it is now at [version]".
///
/// [changeSyncId] names the boundary already open, not a new one. A statement
/// rather than an instruction, which is what makes it safe to replay: see
/// [RetimeRequest] for why the version is on the wire.
class AssignRequest extends WearMessage {
  const AssignRequest({
    required this.changeSyncId,
    required this.activityId,
    required this.version,
  });

  static const kind = 'assign';

  final String changeSyncId;
  final String activityId;

  /// The sender's row version *after* it made this edit. See [RetimeRequest].
  final int version;

  @override
  String get type => kind;

  @override
  Map<String, Object?> toPayload() => {
    'changeSyncId': changeSyncId,
    'activityId': activityId,
    'version': version,
  };

  static AssignRequest? fromPayload(Map<Object?, Object?> payload) {
    final changeSyncId = payload['changeSyncId'];
    final activityId = payload['activityId'];
    final version = payload['version'];
    if (changeSyncId is! String || changeSyncId.isEmpty) return null;
    if (activityId is! String || activityId.isEmpty) return null;
    if (version is! int) return null;
    return AssignRequest(changeSyncId: changeSyncId, activityId: activityId, version: version);
  }
}

/// Watch → phone: "the block I'm already running started at [at], and my row
/// for it is now at [version]".
///
/// Read it as a statement of the sender's answer, not a request to compute one.
/// [at] is what the sender actually landed on after its own clamping, so the
/// receiver adopts it the way it adopts a row pulled from the sync server —
/// version compared, value taken as-is, no re-clamping and no version bump.
///
/// That is the whole reason [version] is here. Applying a correction as a
/// *local edit* bumps the row past whatever it was, so a stale one replayed
/// from the outbox after a disconnect would outrank a newer edit made on the
/// receiving side and win everywhere. Carrying the version makes the relay obey
/// the same rule as the sync leg: strictly newer is adopted, a tie against
/// unpushed local work is refused, and a duplicate delivery is a no-op.
///
/// A payload without a version is rejected rather than guessed at — an older
/// peer's correction is ignored, which is the protocol's existing stance on
/// anything it cannot read.
class RetimeRequest extends WearMessage {
  const RetimeRequest({required this.changeSyncId, required this.at, required this.version});

  static const kind = 'retime';

  final String changeSyncId;
  final DateTime at;

  /// The sender's row version *after* it made this edit.
  final int version;

  @override
  String get type => kind;

  @override
  Map<String, Object?> toPayload() => {
    'changeSyncId': changeSyncId,
    // Epoch millis, matching how the boundary is stored.
    'at': at.millisecondsSinceEpoch,
    'version': version,
  };

  static RetimeRequest? fromPayload(Map<Object?, Object?> payload) {
    final changeSyncId = payload['changeSyncId'];
    final at = payload['at'];
    final version = payload['version'];
    if (changeSyncId is! String || changeSyncId.isEmpty) return null;
    if (at is! int) return null;
    if (version is! int) return null;
    return RetimeRequest(
      changeSyncId: changeSyncId,
      at: DateTime.fromMillisecondsSinceEpoch(at),
      version: version,
    );
  }
}

/// Watch → phone: "send me a snapshot". Issued on watch start and whenever the
/// phone becomes reachable again, so the watch never shows a stale set for
/// longer than it has to.
///
/// It carries [credentialVersion] too, which is what keeps the account in step
/// without ever putting the token on the wire needlessly. The phone answers with
/// a [SyncCredential] only when it holds something newer, so a watch that is
/// current is told nothing — and a watch that missed a revocation while off the
/// wrist is told about it the moment it asks.
class SnapshotRequest extends WearMessage {
  const SnapshotRequest({this.credentialVersion = 0});

  static const kind = 'snapshot_request';

  /// The credential version this device already has. 0 means none.
  final int credentialVersion;

  @override
  String get type => kind;

  @override
  Map<String, Object?> toPayload() => {'credentialVersion': credentialVersion};

  static SnapshotRequest fromPayload(Map<Object?, Object?> payload) {
    final version = payload['credentialVersion'];
    // A peer too old to send one reads as 0, so it is offered the credential —
    // which is the old behaviour, and the safe direction to be wrong in.
    return SnapshotRequest(credentialVersion: version is int ? version : 0);
  }
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
