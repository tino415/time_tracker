/// The sync wire format and, more importantly, the rule that decides who wins.
///
/// Kept pure so the conflict rule is stated once, in one place, and tested
/// without a database or a network.
///
/// ## The rule
///
/// Every syncable row carries a monotonic [version], bumped on each local edit,
/// and a nullable `deletedAt` tombstone — deletions sync like any other change
/// rather than vanishing. Resolution is **version-LWW with the server as the
/// serialization point**:
///
///   * The server accepts a pushed row when `incoming.version >= stored.version`
///     and rejects it as stale otherwise. Accepting the *equal* case is what
///     makes concurrent edits converge: two devices that both edited a row at
///     version 3 both arrive with version 4, and whoever reaches the server last
///     wins. That is a real choice — one edit is lost — but it is deterministic,
///     and for a single user's own devices it beats inventing merge semantics
///     for a colour or a name.
///   * A client adopts a remote row when it is strictly newer, or when it is not
///     holding an unpushed edit of its own ([SyncDecision]).
///
/// Ties are impossible to break "correctly" without vector clocks or per-field
/// causality; both cost more than this app's conflict surface is worth. What
/// matters is that every device ends up with the same row, which this gives.
library;

/// Where a row stands relative to its peer.
enum SyncDecision {
  /// Take the remote row.
  adopt,

  /// Keep what we have — ours is newer, or an unpushed local edit outranks an
  /// equal-version remote.
  keep,
}

/// Decide what to do with an incoming row.
///
/// [localDirty] means the local row has an edit that has not reached the server
/// yet. Such a row keeps its ground on an equal version: it is about to be
/// pushed, and the server will accept it (`>=`). Without this, a pull that
/// happens between a local edit and its push would silently undo the edit.
SyncDecision decideIncoming({
  required int localVersion,
  required int remoteVersion,
  required bool localDirty,
}) {
  if (remoteVersion > localVersion) return SyncDecision.adopt;
  if (remoteVersion == localVersion && !localDirty) return SyncDecision.adopt;
  return SyncDecision.keep;
}

/// Server side: whether a pushed row supersedes what is stored.
bool acceptsPush({required int storedVersion, required int incomingVersion}) =>
    incomingVersion >= storedVersion;

/// An activity as it travels. Mirrors the local columns exactly — a sync DTO
/// that drops fields silently loses them on the next round trip.
class ActivityDto {
  const ActivityDto({
    required this.syncId,
    required this.name,
    required this.color,
    required this.version,
    this.parentId,
    this.bookmarked = false,
    this.lastUsedAt,
    this.externalId,
    this.deletedAt,
  });

  final String syncId;
  final String? parentId;
  final String name;
  final String color;
  final bool bookmarked;
  final DateTime? lastUsedAt;
  final String? externalId;
  final int version;
  final DateTime? deletedAt;

  Map<String, Object?> toJson() => {
        'syncId': syncId,
        'parentId': parentId,
        'name': name,
        'color': color,
        'bookmarked': bookmarked,
        'lastUsedAt': lastUsedAt?.millisecondsSinceEpoch,
        'externalId': externalId,
        'version': version,
        'deletedAt': deletedAt?.millisecondsSinceEpoch,
      };

  static ActivityDto? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final syncId = raw['syncId'];
    final name = raw['name'];
    final color = raw['color'];
    final version = raw['version'];
    if (syncId is! String || syncId.isEmpty) return null;
    if (name is! String || color is! String || version is! int) return null;
    return ActivityDto(
      syncId: syncId,
      parentId: raw['parentId'] is String ? raw['parentId'] as String : null,
      name: name,
      color: color,
      bookmarked: raw['bookmarked'] == true,
      lastUsedAt: _millis(raw['lastUsedAt']),
      externalId: raw['externalId'] is String ? raw['externalId'] as String : null,
      version: version,
      deletedAt: _millis(raw['deletedAt']),
    );
  }
}

/// A change plus the activity set it owns.
///
/// The join travels *inside* its change rather than as its own syncable entity:
/// it has no independent identity or version, and a change whose set arrived
/// separately could be observed mid-update as a block tracking nothing.
class ChangeDto {
  const ChangeDto({
    required this.syncId,
    required this.changedAt,
    required this.version,
    this.comment,
    this.deletedAt,
    this.activityIds = const [],
  });

  final String syncId;
  final DateTime changedAt;
  final String? comment;
  final int version;
  final DateTime? deletedAt;
  final List<String> activityIds;

  Map<String, Object?> toJson() => {
        'syncId': syncId,
        'changedAt': changedAt.millisecondsSinceEpoch,
        'comment': comment,
        'version': version,
        'deletedAt': deletedAt?.millisecondsSinceEpoch,
        'activityIds': activityIds,
      };

  static ChangeDto? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final syncId = raw['syncId'];
    final changedAt = raw['changedAt'];
    final version = raw['version'];
    if (syncId is! String || syncId.isEmpty) return null;
    if (changedAt is! int || version is! int) return null;
    final ids = raw['activityIds'];
    return ChangeDto(
      syncId: syncId,
      changedAt: DateTime.fromMillisecondsSinceEpoch(changedAt),
      comment: raw['comment'] is String ? raw['comment'] as String : null,
      version: version,
      deletedAt: _millis(raw['deletedAt']),
      activityIds: [
        if (ids is List)
          for (final id in ids)
            if (id is String && id.isNotEmpty) id,
      ],
    );
  }
}

/// One round trip: everything we have to say, and where we last read up to.
///
/// Push and pull share a request deliberately. A separate pull would need its
/// own round trip and could interleave with a push, which is exactly when the
/// "did my edit survive?" question gets hard to answer.
class SyncRequest {
  const SyncRequest({
    required this.cursor,
    this.activities = const [],
    this.changes = const [],
  });

  /// Opaque server position; null on a first sync, which pulls everything.
  final String? cursor;
  final List<ActivityDto> activities;
  final List<ChangeDto> changes;

  Map<String, Object?> toJson() => {
        'cursor': cursor,
        'activities': [for (final a in activities) a.toJson()],
        'changes': [for (final c in changes) c.toJson()],
      };
}

class SyncResponse {
  const SyncResponse({
    required this.cursor,
    this.activities = const [],
    this.changes = const [],
    this.rejected = const [],
  });

  final String cursor;
  final List<ActivityDto> activities;
  final List<ChangeDto> changes;

  /// syncIds the server refused as stale. The client must re-read them from the
  /// pulled rows rather than assume its push landed — silently treating a
  /// rejection as success is how a device ends up permanently out of step.
  final List<String> rejected;

  static SyncResponse? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final cursor = raw['cursor'];
    if (cursor is! String) return null;
    final activities = raw['activities'];
    final changes = raw['changes'];
    final rejected = raw['rejected'];
    return SyncResponse(
      cursor: cursor,
      activities: [
        if (activities is List)
          for (final a in activities) ?ActivityDto.fromJson(a),
      ],
      changes: [
        if (changes is List)
          for (final c in changes) ?ChangeDto.fromJson(c),
      ],
      rejected: [
        if (rejected is List)
          for (final id in rejected)
            if (id is String) id,
      ],
    );
  }
}

DateTime? _millis(Object? raw) =>
    raw is int ? DateTime.fromMillisecondsSinceEpoch(raw) : null;
