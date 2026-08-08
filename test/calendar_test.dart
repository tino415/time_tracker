// Pure-domain tests for the calendar edit view: day slicing (including blocks
// that cross midnight) and the clamping that keeps a dragged boundary from
// reordering the timeline.

import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/domain/block.dart';
import 'package:time_tracker/domain/calendar.dart';

Activity act(String id, String name) => Activity(
      syncId: id,
      name: name,
      color: '#4F8FEE',
      bookmarked: false,
      version: 1,
      dirty: false,
    );

ActivityChange chg(String id, DateTime at) => ActivityChange(
      syncId: id,
      changedAt: at,
      version: 1,
      dirty: false,
    );

Block block(String id, DateTime start, DateTime? end) => Block(
      change: chg(id, start),
      start: start,
      end: end,
      activities: [act('a', 'Alpha')],
    );

final day = DateTime(2026, 1, 5); // Mon
DateTime t(int hour, [int minute = 0]) => DateTime(2026, 1, 5, hour, minute);

void main() {
  group('sliceDay', () {
    test('keeps only the blocks touching the day, chronological', () {
      final slices = sliceDay(
        blocks: [
          block('late', t(14), t(15)),
          block('early', t(9), t(10)),
          block('other-day', DateTime(2026, 1, 3, 9), DateTime(2026, 1, 3, 10)),
        ],
        day: day,
        now: t(20),
      );

      expect(slices.map((s) => s.block.change.syncId), ['early', 'late']);
    });

    test('a block crossing midnight is clipped and flagged on both days', () {
      final overnight = block('night', DateTime(2026, 1, 4, 23), t(1));

      final first = sliceDay(blocks: [overnight], day: DateTime(2026, 1, 4), now: t(20)).single;
      expect(first.start, DateTime(2026, 1, 4, 23));
      expect(first.end, DateTime(2026, 1, 5)); // clipped at midnight
      expect(first.continuesBefore, isFalse);
      expect(first.continuesAfter, isTrue);
      // The clipped end sits at the very bottom of the axis.
      expect(first.endMinutes, 24 * 60);

      final second = sliceDay(blocks: [overnight], day: day, now: t(20)).single;
      expect(second.start, day);
      expect(second.end, t(1));
      expect(second.continuesBefore, isTrue);
      expect(second.continuesAfter, isFalse);
      expect(second.startMinutes, 0);
      expect(second.endMinutes, 60);
    });

    test('a block ending exactly at midnight belongs to the earlier day only', () {
      final b = block('b', DateTime(2026, 1, 4, 23), day);

      expect(sliceDay(blocks: [b], day: DateTime(2026, 1, 4), now: t(20)), hasLength(1));
      expect(sliceDay(blocks: [b], day: day, now: t(20)), isEmpty);
    });

    test('the open block is measured up to now', () {
      final slices = sliceDay(blocks: [block('open', t(9), null)], day: day, now: t(11, 30));

      expect(slices.single.end, t(11, 30));
      expect(slices.single.duration, const Duration(hours: 2, minutes: 30));
      expect(slices.single.continuesAfter, isFalse);
    });

    test('an open block from a previous day fills this one', () {
      final slices = sliceDay(
        blocks: [block('open', DateTime(2026, 1, 3, 9), null)],
        day: day,
        now: DateTime(2026, 1, 6, 8),
      );

      expect(slices.single.continuesBefore, isTrue);
      expect(slices.single.continuesAfter, isTrue);
      expect(slices.single.startMinutes, 0);
      expect(slices.single.endMinutes, 24 * 60);
    });
  });

  group('clampBoundary', () {
    test('an unobstructed target is left alone', () {
      expect(
        clampBoundary(desired: t(12), previous: t(9), next: t(15), notAfter: t(20)),
        t(12),
      );
    });

    test('is held off the previous boundary by minBlock', () {
      expect(
        clampBoundary(
          desired: t(8),
          previous: t(9),
          next: t(15),
          notAfter: t(20),
          minBlock: const Duration(minutes: 5),
        ),
        t(9, 5),
      );
    });

    test('is held off the next boundary by minBlock', () {
      expect(
        clampBoundary(
          desired: t(18),
          previous: t(9),
          next: t(15),
          notAfter: t(20),
          minBlock: const Duration(minutes: 5),
        ),
        t(14, 55),
      );
    });

    test('never lands in the future, and stops short of the present', () {
      // Not t(17). The running block's end is *now*, which is not a boundary of
      // its own, so it gets the same clearance a neighbour would: dragging its
      // start onto the present would leave a block of zero length — a card too
      // short to draw and a block that cannot be grabbed to undo it.
      expect(
        clampBoundary(desired: t(19), previous: t(9), notAfter: t(17)),
        t(16, 59),
      );
    });

    test('the first boundary has no lower bound', () {
      expect(
        clampBoundary(desired: DateTime(2020, 1, 1), next: t(15), notAfter: t(20)),
        DateTime(2020, 1, 1),
      );
    });

    test('refuses when the neighbours leave no room', () {
      expect(
        clampBoundary(
          desired: t(12),
          previous: t(12),
          next: t(12, 1),
          minBlock: const Duration(minutes: 5),
        ),
        isNull,
      );
    });
  });

  group('snapTime', () {
    test('rounds to the nearest step', () {
      expect(snapTime(t(9, 13), const Duration(minutes: 5)), t(9, 15));
      expect(snapTime(t(9, 12), const Duration(minutes: 5)), t(9, 10));
    });

    test('a zero step is a no-op', () {
      expect(snapTime(t(9, 13), Duration.zero), t(9, 13));
    });
  });

  group('minutesFromMidnight', () {
    test('measures against the local day', () {
      expect(minutesFromMidnight(t(0)), 0);
      expect(minutesFromMidnight(t(9, 30)), 570);
      expect(minutesFromMidnight(t(23, 59)), 1439);
    });
  });
}
