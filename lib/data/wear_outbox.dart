import 'dart:convert';

import 'package:drift/drift.dart';

import '../domain/wear_protocol.dart';
import 'database.dart';

/// What this device tried to relay while the peer was out of range.
///
/// The gap it closes: `WearBridge.send` reports an undelivered message, and
/// until now every caller threw that answer away. A tap made on a walk survived
/// in the watch's own database but never reached the phone — and on a pair with
/// no sync account, where the relay is the only route between the two, never
/// reached it at all.
///
/// Entries are drained in the order they were made, and removed one at a time
/// as each is delivered, so a peer that disappears mid-drain leaves the rest
/// parked rather than lost. Nothing here retries on a timer: the only moment
/// worth trying again is when reachability says so.
class WearOutboxStore {
  WearOutboxStore(this._db);

  final AppDatabase _db;

  /// Backstop for entries that cannot collapse. A switch is a distinct event,
  /// so a watch worn all day out of range parks one per tap; past this the
  /// oldest go, which is no worse than the drop this exists to prevent.
  static const maxEntries = 200;

  /// Park [message]. A message with a collapse key replaces the one it matches,
  /// so the backlog holds the sender's latest answer per boundary rather than
  /// every step it took to get there.
  Future<void> add(WearMessage message) async {
    final key = collapseKeyFor(message);
    await _db.transaction(() async {
      if (key != null) {
        await (_db.delete(_db.wearOutbox)..where((t) => t.collapseKey.equals(key))).go();
      }
      await _db
          .into(_db.wearOutbox)
          .insert(
            WearOutboxCompanion.insert(
              type: message.type,
              payload: jsonEncode(message.toPayload()),
              collapseKey: Value(key),
            ),
          );
      await _trim();
    });
  }

  /// Everything parked, oldest first — the order it was made in, which is the
  /// order it has to arrive in.
  Future<List<WearOutboxData>> pending() {
    return (_db.select(_db.wearOutbox)..orderBy([(t) => OrderingTerm.asc(t.id)])).get();
  }

  /// Delivered, so it can go. Called per entry rather than per drain: a send
  /// that fails halfway must leave the rest where they are.
  Future<void> remove(int id) async {
    await (_db.delete(_db.wearOutbox)..where((t) => t.id.equals(id))).go();
  }

  /// Decode an entry back into the message it was. Null for a row this build
  /// cannot read — a downgrade, or a type since removed — which is dropped by
  /// the drain rather than retried forever.
  static WearMessage? decode(WearOutboxData entry) {
    try {
      return WearMessage.decode(entry.type, jsonDecode(entry.payload));
    } on FormatException {
      return null;
    }
  }

  /// Which entries supersede each other. A correction states the sender's whole
  /// answer for one boundary, so only the newest per boundary is worth keeping —
  /// the same reasoning that collapses a bookmark snapshot in the inbound queue.
  /// A switch opens a boundary of its own and never collapses.
  static String? collapseKeyFor(WearMessage message) => switch (message) {
    AssignRequest(:final changeSyncId) => '${AssignRequest.kind}:$changeSyncId',
    RetimeRequest(:final changeSyncId) => '${RetimeRequest.kind}:$changeSyncId',
    _ => null,
  };

  /// Drop anything older than the [maxEntries] newest. Reads the oldest entry
  /// worth keeping rather than counting, so it is one query and a delete
  /// whatever the backlog looks like.
  Future<void> _trim() async {
    final oldestKept =
        await (_db.select(_db.wearOutbox)
              ..orderBy([(t) => OrderingTerm.desc(t.id)])
              ..limit(1, offset: maxEntries - 1))
            .getSingleOrNull();
    if (oldestKept == null) return;
    await (_db.delete(_db.wearOutbox)..where((t) => t.id.isSmallerThanValue(oldestKept.id))).go();
  }
}
