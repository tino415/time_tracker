// The store behind the relay's outbox: what it keeps, what it collapses, and
// in what order it hands things back.
//
// The rules here are the ones that make a replayed backlog safe rather than
// merely persistent. Order is the boundaries' order on the timeline; collapsing
// is what keeps a watch worn all day out of range from parking a week of
// corrections to one block.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/data/wear_outbox.dart';
import 'package:time_tracker/domain/wear_protocol.dart';

void main() {
  late AppDatabase db;
  late WearOutboxStore outbox;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    outbox = WearOutboxStore(db);
  });

  tearDown(() => db.close());

  SwitchRequest switchAt(String id, int millis) => SwitchRequest(
    changeSyncId: id,
    activityId: 'a',
    at: DateTime.fromMillisecondsSinceEpoch(millis),
  );

  Future<List<WearMessage>> parked() async => [
    for (final e in await outbox.pending()) WearOutboxStore.decode(e)!,
  ];

  test('hands entries back in the order they were made', () async {
    // Not a detail: these are boundaries, and replaying them out of order would
    // put the timeline together wrong on the receiving device.
    await outbox.add(switchAt('one', 1770000000000));
    await outbox.add(switchAt('two', 1770000060000));
    await outbox.add(switchAt('three', 1770000120000));

    expect((await parked()).cast<SwitchRequest>().map((m) => m.changeSyncId), [
      'one',
      'two',
      'three',
    ]);
  });

  test('keeps every switch, because each one is a distinct event', () async {
    await outbox.add(switchAt('one', 1770000000000));
    await outbox.add(switchAt('two', 1770000060000));

    expect(await outbox.pending(), hasLength(2));
  });

  test('a correction replaces the earlier one for the same boundary', () async {
    // A correction states the sender's whole answer for one boundary, so the
    // older one is not history worth relaying — it is a value that has since
    // been superseded on the device that sent it.
    await outbox.add(
      RetimeRequest(
        changeSyncId: 'block-1',
        at: DateTime.fromMillisecondsSinceEpoch(1770000000000),
        version: 2,
      ),
    );
    await outbox.add(
      RetimeRequest(
        changeSyncId: 'block-1',
        at: DateTime.fromMillisecondsSinceEpoch(1770000300000),
        version: 3,
      ),
    );

    final only = (await parked()).single as RetimeRequest;
    expect(only.version, 3);
    expect(only.at, DateTime.fromMillisecondsSinceEpoch(1770000300000));
  });

  test('corrections to different boundaries do not collapse into each other', () async {
    await outbox.add(const AssignRequest(changeSyncId: 'block-1', activityId: 'a', version: 2));
    await outbox.add(const AssignRequest(changeSyncId: 'block-2', activityId: 'b', version: 2));

    expect(await outbox.pending(), hasLength(2));
  });

  test('an assign and a retime for the same boundary both survive', () async {
    // They say different things about the same row — one where it starts, one
    // what it points at — so neither supersedes the other.
    await outbox.add(const AssignRequest(changeSyncId: 'block-1', activityId: 'a', version: 2));
    await outbox.add(
      RetimeRequest(
        changeSyncId: 'block-1',
        at: DateTime.fromMillisecondsSinceEpoch(1770000000000),
        version: 3,
      ),
    );

    expect(await outbox.pending(), hasLength(2));
  });

  test('removing a delivered entry leaves the rest where they are', () async {
    await outbox.add(switchAt('one', 1770000000000));
    await outbox.add(switchAt('two', 1770000060000));

    final first = (await outbox.pending()).first;
    await outbox.remove(first.id);

    expect((await parked()).cast<SwitchRequest>().map((m) => m.changeSyncId), ['two']);
  });

  test('past the cap the oldest go, not the newest', () async {
    // The backstop for what cannot collapse. Losing the earliest boundary is
    // bad; losing the tap just made would be worse, and would also mean the
    // watch's own screen disagreed with what it relayed.
    for (var i = 0; i <= WearOutboxStore.maxEntries; i++) {
      await outbox.add(switchAt('change-$i', 1770000000000 + i * 60000));
    }

    final ids = (await parked()).cast<SwitchRequest>().map((m) => m.changeSyncId).toList();
    expect(ids, hasLength(WearOutboxStore.maxEntries));
    expect(ids.first, 'change-1', reason: 'the oldest was dropped');
    expect(ids.last, 'change-${WearOutboxStore.maxEntries}');
  });

  test('survives being read back by a new store over the same database', () async {
    // The point of using the database rather than memory: the watch app is
    // killed constantly, and a backlog that does not survive that is no backlog.
    await outbox.add(switchAt('one', 1770000000000));

    final reopened = WearOutboxStore(db);
    expect(await reopened.pending(), hasLength(1));
  });
}
