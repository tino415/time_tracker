// The sync wire format and the conflict rule.
//
// The rule is the whole point of this file: version-LWW with the server as the
// serialization point, where accepting the *equal* case is what makes concurrent
// edits converge. If any of these change, devices stop agreeing.

import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/domain/sync_protocol.dart';

void main() {
  group('decideIncoming', () {
    test('a strictly newer remote row is adopted', () {
      expect(
        decideIncoming(localVersion: 1, remoteVersion: 2, localDirty: false),
        SyncDecision.adopt,
      );
      // Even over an unpushed local edit: the remote is provably later, and the
      // local edit will be re-pushed with a bumped version.
      expect(
        decideIncoming(localVersion: 1, remoteVersion: 2, localDirty: true),
        SyncDecision.adopt,
      );
    });

    test('an older remote row is ignored', () {
      expect(
        decideIncoming(localVersion: 3, remoteVersion: 2, localDirty: false),
        SyncDecision.keep,
      );
    });

    test('an equal version is adopted only when nothing local is pending', () {
      // Nothing pending: the server's copy is the same generation, so taking it
      // is free and keeps the row byte-identical across devices.
      expect(
        decideIncoming(localVersion: 2, remoteVersion: 2, localDirty: false),
        SyncDecision.adopt,
      );
      // Pending: a pull that lands between a local edit and its push must not
      // silently undo the edit. It is about to be pushed, and the server accepts
      // `>=`, so this device wins there too.
      expect(
        decideIncoming(localVersion: 2, remoteVersion: 2, localDirty: true),
        SyncDecision.keep,
      );
    });
  });

  group('acceptsPush', () {
    test('accepts newer and equal, rejects stale', () {
      expect(acceptsPush(storedVersion: 2, incomingVersion: 3), isTrue);
      // The equal case is deliberate: two devices that both edited version 2
      // arrive with 3, and the later arrival wins. One edit is lost, but every
      // device converges on the same row.
      expect(acceptsPush(storedVersion: 3, incomingVersion: 3), isTrue);
      expect(acceptsPush(storedVersion: 3, incomingVersion: 2), isFalse);
    });
  });

  group('ActivityDto', () {
    test('round-trips every field', () {
      final dto = ActivityDto(
        syncId: 'a',
        parentId: 'root',
        name: 'Deep work',
        color: '#4F8FEE',
        bookmarked: true,
        lastUsedAt: DateTime.fromMillisecondsSinceEpoch(1770000000000),
        externalId: 'CU-1042',
        aliases: ['Focus', 'Deep'],
        version: 7,
        deletedAt: DateTime.fromMillisecondsSinceEpoch(1770000009999),
      );

      final decoded = ActivityDto.fromJson(dto.toJson())!;

      // A DTO that drops a field loses it on the next round trip, so this
      // checks all of them rather than a representative few.
      expect(decoded.syncId, 'a');
      expect(decoded.parentId, 'root');
      expect(decoded.name, 'Deep work');
      expect(decoded.color, '#4F8FEE');
      expect(decoded.bookmarked, isTrue);
      expect(decoded.lastUsedAt, dto.lastUsedAt);
      expect(decoded.externalId, 'CU-1042');
      expect(decoded.aliases, ['Focus', 'Deep']);
      expect(decoded.version, 7);
      expect(decoded.deletedAt, dto.deletedAt);
    });

    test('an alias holding a comma survives the trip', () {
      final dto = ActivityDto(
        syncId: 'a',
        name: 'Learning',
        color: '#4F8FEE',
        version: 1,
        aliases: ['deep, focused'],
      );

      expect(ActivityDto.fromJson(dto.toJson())!.aliases, ['deep, focused']);
    });

    test('a row from a client without aliases decodes to none', () {
      final json = {'syncId': 'a', 'name': 'n', 'color': '#4F8FEE', 'version': 1};

      expect(ActivityDto.fromJson(json)!.aliases, isEmpty);
    });

    test('a tombstone survives the trip', () {
      // Deletions sync like any other change; losing deletedAt would resurrect
      // deleted rows on every other device.
      final dto = ActivityDto(
        syncId: 'a',
        name: 'Gone',
        color: '#000000',
        version: 2,
        deletedAt: DateTime.fromMillisecondsSinceEpoch(1770000000000),
      );
      expect(ActivityDto.fromJson(dto.toJson())!.deletedAt, dto.deletedAt);
    });

    test('is rejected when required fields are missing or mistyped', () {
      expect(ActivityDto.fromJson({'name': 'x', 'color': '#fff', 'version': 1}), isNull);
      expect(
        ActivityDto.fromJson({'syncId': '', 'name': 'x', 'color': '#fff', 'version': 1}),
        isNull,
      );
      expect(ActivityDto.fromJson({'syncId': 'a', 'name': 'x', 'color': '#fff'}), isNull);
      expect(
        ActivityDto.fromJson({'syncId': 'a', 'name': 'x', 'color': '#fff', 'version': '1'}),
        isNull,
      );
      expect(ActivityDto.fromJson('not a map'), isNull);
    });
  });

  group('ChangeDto', () {
    test('round-trips, carrying its activity set', () {
      final dto = ChangeDto(
        syncId: 'c1',
        changedAt: DateTime.fromMillisecondsSinceEpoch(1770000000123),
        comment: 'standup, ran long',
        version: 3,
        activityIds: const ['a', 'b'],
      );

      final decoded = ChangeDto.fromJson(dto.toJson())!;

      expect(decoded.changedAt, dto.changedAt);
      // Millisecond precision is the boundary's identity on the timeline.
      expect(decoded.changedAt.millisecondsSinceEpoch, 1770000000123);
      expect(decoded.comment, 'standup, ran long');
      expect(decoded.activityIds, ['a', 'b']);
    });

    test('a malformed id inside the set is dropped, the change survives', () {
      final decoded = ChangeDto.fromJson({
        'syncId': 'c1',
        'changedAt': 1,
        'version': 1,
        'activityIds': ['a', '', 42, null],
      })!;

      expect(decoded.activityIds, ['a']);
    });

    test('is rejected when required fields are missing', () {
      expect(ChangeDto.fromJson({'syncId': 'c', 'version': 1}), isNull);
      expect(ChangeDto.fromJson({'syncId': 'c', 'changedAt': 1}), isNull);
      expect(ChangeDto.fromJson({'changedAt': 1, 'version': 1}), isNull);
    });
  });

  group('SyncResponse', () {
    test('parses a full response', () {
      final decoded = SyncResponse.fromJson({
        'cursor': '42',
        'activities': [
          {'syncId': 'a', 'name': 'A', 'color': '#fff', 'version': 1},
        ],
        'changes': [
          {
            'syncId': 'c',
            'changedAt': 1,
            'version': 1,
            'activityIds': ['a'],
          },
        ],
        'rejected': ['stale-one'],
        'hasMore': true,
      })!;

      expect(decoded.cursor, '42');
      expect(decoded.activities.single.syncId, 'a');
      expect(decoded.changes.single.syncId, 'c');
      expect(decoded.rejected, ['stale-one']);
      expect(decoded.hasMore, isTrue);
    });

    test('a response from a server that does not page says nothing more is waiting', () {
      expect(SyncResponse.fromJson({'cursor': '1'})!.hasMore, isFalse);
    });

    test('unparseable rows are skipped rather than failing the response', () {
      // A server on a newer build may send rows this client cannot read; losing
      // one row beats losing the whole sync.
      final decoded = SyncResponse.fromJson({
        'cursor': '1',
        'activities': [
          {'syncId': 'a', 'name': 'A', 'color': '#fff', 'version': 1},
          {'nonsense': true},
        ],
      })!;

      expect(decoded.activities, hasLength(1));
    });

    test('a response without a cursor is rejected outright', () {
      // The cursor is how the client knows what it has seen — accepting a
      // response without one would silently re-pull or skip forever.
      expect(SyncResponse.fromJson({'activities': []}), isNull);
      expect(SyncResponse.fromJson('nope'), isNull);
    });
  });
}
