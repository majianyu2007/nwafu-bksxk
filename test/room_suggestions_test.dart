import 'package:flutter_test/flutter_test.dart';
import 'package:nwafu_bksxk/data/edu_models.dart';
import 'package:nwafu_bksxk/data/room_suggestions.dart';
import 'package:nwafu_bksxk/data/timetable_logic.dart';

FreeRoom room(
  String name, {
  String building = '北8',
  String campus = '北校区',
  int seats = 60,
}) => FreeRoom(
  name: name,
  building: building,
  campus: campus,
  seats: seats,
  freeTimes: '',
);

CourseSession cls(String name, String room, int start, int end) =>
    CourseSession(
      id: name,
      courseName: name,
      courseCode: name,
      classNo: '1',
      weekday: 2,
      startPeriod: start,
      endPeriod: end,
      weeks: const [1],
      weeksLabel: '1周',
      room: room,
    );

final term = TermTimetable(
  term: const EduTerm(code: '2026-2027-1', name: '秋'),
  firstMonday: DateTime.utc(2026, 10, 12),
  weekCount: 1,
  periods: ClassPeriod.nwafuSummer,
  sessions: const [],
  syncedAt: DateTime.utc(2026, 10, 1),
);

void main() {
  final tuesday = DateTime.utc(2026, 10, 13);
  // 07:30 CST, before anything starts.
  final early = DateTime.utc(2026, 10, 12, 23, 30);

  List<RoomSuggestion> run(
    List<CourseSession> sessions,
    Map<RoomBlock, List<FreeRoom>> free, {
    DateTime? now,
  }) => suggestRooms(
    timetable: term,
    date: tuesday,
    classes: [for (final s in sessions) term.occurrence(s, tuesday)!],
    free: free,
    now: now ?? early,
  );

  test('早十的课: 1-2 suggests its own room first, then its building', () {
    final out = run(
      [cls('Java', 'N8618', 3, 4)],
      {
        kRoomBlocks[0]: [
          room('S1101', building: '南1', campus: '南校区'),
          room('N9101', building: '北9'),
          room('N8402', seats: 120),
          room('N8618'),
        ],
      },
    );
    final before = out.firstWhere((s) => s.kind == SuggestionKind.beforeClass);
    expect(before.blocks, [kRoomBlocks[0]]);
    expect(before.sameRoom?.name, 'N8618');
    expect(before.anchorRoom, 'N8618');
    // Other buildings are never suggested.
    expect(before.rooms.map((r) => r.room.name), ['N8618', 'N8402']);
    expect(before.building, '北8');
  });

  test('a gap between classes is one stretch; whole-stretch rooms first', () {
    final out = run(
      [cls('A', 'N9113', 1, 2), cls('B', '理科楼A402', 9, 10)],
      {
        kRoomBlocks[1]: [
          room('N9201', building: '北9'),
          room('理科楼A305', building: '理科楼'),
        ],
        kRoomBlocks[2]: [
          room('N9201', building: '北9'),
          room('理科楼A305', building: '理科楼'),
        ],
        kRoomBlocks[3]: [
          room('理科楼A305', building: '理科楼'),
          room('理科楼A402', building: '理科楼'),
        ],
      },
    );
    final gap = out.single;
    expect(gap.kind, SuggestionKind.between);
    expect(gap.blocks, kRoomBlocks.sublist(1, 4));
    // A305 is free for all of 3-8, so it beats rooms free for part of it.
    expect(gap.rooms.first.room.name, '理科楼A305');
    expect(gap.rooms.first.freeIn.length, 3);
    expect(gap.anchorRoom, '理科楼A402');
    // Only 理科楼 rooms: N9201 is in another building.
    expect(gap.rooms.map((r) => r.room.name), isNot(contains('N9201')));
  });

  test('past blocks and non-study rooms are left out', () {
    // 12:30 CST: the morning is over.
    final noon = DateTime.utc(2026, 10, 13, 4, 30);
    final out = run(
      [cls('A', 'N8618', 1, 2), cls('B', 'N8618', 9, 10)],
      {
        for (final b in kRoomBlocks)
          b: [
            room('N8101'),
            room('体育场', building: '体育场馆(N)', seats: 1000),
            room('计算机机房103-A', building: '信息机房'),
          ],
      },
      now: noon,
    );
    for (final s in out) {
      expect(s.blocks, isNot(contains(kRoomBlocks[0])));
      expect(s.blocks, isNot(contains(kRoomBlocks[1])));
      expect(s.rooms.map((r) => r.room.name), ['N8101']);
    }
  });

  test('nothing free in the building means no suggestion rooms', () {
    final out = run(
      [cls('Java', '计算机机房103-A', 3, 4)],
      {
        kRoomBlocks[0]: [room('N3101', building: '北3')],
      },
    );
    final s = out.single;
    expect(s.rooms, isEmpty);
  });

  test('a day off suggests the next block', () {
    final out = run(const [], {
      kRoomBlocks[0]: [room('N8101')],
    });
    expect(out.single.kind, SuggestionKind.freeDay);
  });

  test('timetable rooms map to school buildings', () {
    final dir = RoomDirectory([
      [room('N8402'), room('理科楼A305', building: '理科楼')],
    ]);
    expect(dir.buildingOf('N8618'), '北8');
    expect(dir.buildingOf(' N8618 '), '北8');
    expect(dir.buildingOf('理科楼A402'), '理科楼');
    expect(buildingKey('n9402'), 'N9');
  });

  test('morning-only class still suggests afternoon blocks after 16:00', () {
    final lateAfternoon = DateTime.utc(2026, 10, 13, 8, 0); // 16:00 CST Tue
    final out = run(
      [cls('早八课', 'N8101', 1, 2)],
      {
        for (final b in kRoomBlocks) b: [room('N8101')],
      },
      now: lateAfternoon,
    );
    expect(out, isNotEmpty);
    expect(out.single.blocks, contains(kRoomBlocks[3])); // 7-8 节 still active
  });

  test('consecutiveFreeRun counts unbroken streak from anchor block', () {
    final freeNames = {
      kRoomBlocks[0]: {'N8101'},
      kRoomBlocks[1]: {'N8101', 'N8102'},
      kRoomBlocks[2]: {'N8101'},
      kRoomBlocks[3]: <String>{},
      kRoomBlocks[4]: {'N8101'},
    };
    final r1 = consecutiveFreeRun('N8101', kRoomBlocks[0], freeNames);
    expect(r1.count, 3);
    expect(r1.lastBlock, kRoomBlocks[2]);
    final r2 = consecutiveFreeRun('N8102', kRoomBlocks[1], freeNames);
    expect(r2.count, 1);
    expect(r2.lastBlock, kRoomBlocks[1]);
  });
}
