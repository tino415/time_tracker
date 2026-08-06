// The Wear wire format. Pure — no channels, no database.
//
// Decoding is deliberately forgiving in one direction only: a malformed or
// unknown message is dropped, never thrown, because the peer may be running a
// different build of the app and must not be able to crash this one.

import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/domain/wear_protocol.dart';

/// Round-trip through the shape the platform channel actually carries.
WearMessage? roundTrip(WearMessage message) =>
    WearMessage.decode(message.type, message.toPayload());

void main() {
  group('BookmarkSnapshot', () {
    test('round-trips activities and the current selection', () {
      final original = BookmarkSnapshot(
        activities: const [
          WearActivity(syncId: 'a', name: 'Deep work', color: '#4F8FEE'),
          WearActivity(syncId: 'b', name: 'Email', color: '#EE7C4F'),
        ],
        currentActivityId: 'a',
      );

      final decoded = roundTrip(original) as BookmarkSnapshot;

      expect(decoded.activities, original.activities);
      expect(decoded.currentActivityId, 'a');
    });

    test('an absent current selection stays absent', () {
      final decoded = roundTrip(const BookmarkSnapshot(activities: [])) as BookmarkSnapshot;

      expect(decoded.activities, isEmpty);
      expect(decoded.currentActivityId, isNull);
    });

    test('an empty current id is treated as none', () {
      final decoded = BookmarkSnapshot.fromPayload({'currentActivityId': ''});

      expect(decoded.currentActivityId, isNull);
    });

    test('malformed activity entries are skipped, the rest survive', () {
      final decoded = BookmarkSnapshot.fromPayload({
        'activities': [
          {'syncId': 'a', 'name': 'Good', 'color': '#4F8FEE'},
          {'syncId': 'b', 'name': 'Missing colour'},
          'not a map',
          {'syncId': '', 'name': 'Empty id', 'color': '#000000'},
        ],
      });

      expect(decoded.activities.map((a) => a.syncId), ['a']);
    });
  });

  group('SwitchRequest', () {
    test('round-trips, keeping the instant exact', () {
      final at = DateTime.fromMillisecondsSinceEpoch(1770000000123);
      final decoded = roundTrip(SwitchRequest(
        changeSyncId: 'change-1',
        activityId: 'a',
        at: at,
      )) as SwitchRequest;

      expect(decoded.changeSyncId, 'change-1');
      expect(decoded.activityId, 'a');
      // Millisecond precision matters: it is the boundary's identity on the
      // timeline, and the phone stores epoch millis.
      expect(decoded.at, at);
      expect(decoded.at.millisecondsSinceEpoch, 1770000000123);
    });

    test('is rejected when any field is missing or the wrong type', () {
      expect(SwitchRequest.fromPayload({'activityId': 'a', 'at': 1}), isNull);
      expect(SwitchRequest.fromPayload({'changeSyncId': 'c', 'at': 1}), isNull);
      expect(SwitchRequest.fromPayload({'changeSyncId': 'c', 'activityId': 'a'}), isNull);
      expect(
        SwitchRequest.fromPayload({'changeSyncId': '', 'activityId': 'a', 'at': 1}),
        isNull,
      );
      expect(
        SwitchRequest.fromPayload({'changeSyncId': 'c', 'activityId': 'a', 'at': '1'}),
        isNull,
      );
    });
  });

  group('decode', () {
    test('SnapshotRequest needs no payload', () {
      expect(WearMessage.decode('snapshot_request', null), isA<SnapshotRequest>());
      expect(roundTrip(const SnapshotRequest()), isA<SnapshotRequest>());
    });

    test('an unknown type is dropped, not thrown', () {
      expect(WearMessage.decode('something_from_the_future', {'a': 1}), isNull);
      expect(WearMessage.decode(null, null), isNull);
      expect(WearMessage.decode(42, {}), isNull);
    });

    test('a malformed switch is dropped rather than half-decoded', () {
      expect(WearMessage.decode('switch', {'activityId': 'a'}), isNull);
    });
  });

  group('WearReachability', () {
    test('parses the states the bridge emits', () {
      expect(WearReachability.parse('reachable'), WearReachability.reachable);
      expect(
        WearReachability.parse('pairedButNotReachable'),
        WearReachability.pairedButNotReachable,
      );
      expect(WearReachability.parse('notPaired'), WearReachability.notPaired);
    });

    test('anything unexpected reads as not paired', () {
      // Failing closed matters: claiming reachable when we cannot tell would
      // make the watch show "waiting for the phone…" forever.
      expect(WearReachability.parse(null), WearReachability.notPaired);
      expect(WearReachability.parse('nonsense'), WearReachability.notPaired);
    });
  });
}
