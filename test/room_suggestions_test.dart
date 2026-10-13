import 'package:flutter_test/flutter_test.dart';
import 'package:nwafu_bksxk/data/edu_models.dart';
import 'package:nwafu_bksxk/data/room_suggestions.dart';
import 'package:nwafu_bksxk/data/timetable_logic.dart';

FreeRoom room(String name, {String building = '', int seats = 60}) =>
    FreeRoom(
      name: name,
      building: building,
      campus: '北校区',
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

  test('a 3-4 class makes 1-2 a pre-class slot with its own room first', () {
    final java = cls('Java', 'N8618', 3, 4);
    final out = suggestRooms(
      timetable: term,
      date: tuesday,
      classes: [term.occurrence(java, tuesday)!],
      free: {
        kRoomBlocks[0]: [
          room('S1101'),
          room('N8402', seats: 120),
          room('N8618'),
          room('N9101'),
        ],
      },
      now: early,
    );
    final before = out.firstWhere((s) => s.kind == SuggestionKind.beforeClass);
    expect(before.block, kRoomBlocks[0]);
    expect(before.sameRoom?.name, 'N8618');
    expect(before.reason, contains('N8618'));
    // Same room, then same building (N8), then same side (N), then the rest.
    expect(before.rooms.map((r) => r.name), [
      'N8618',
      'N8402',
      'N9101',
      'S1101',
    ]);
  });

  test('blocks with a class or already over are never suggested', () {
    final a = cls('A', 'N8618', 1, 2);
    final b = cls('B', 'N8618', 5, 6);
    // 12:30 CST: 1-2 and 3-4 are over.
    final noon = DateTime.utc(2026, 10, 13, 4, 30);
    final out = suggestRooms(
      timetable: term,
      date: tuesday,
      classes: [term.occurrence(a, tuesday)!, term.occurrence(b, tuesday)!],
      free: {for (final blk in kRoomBlocks) blk: [room('N8101')]},
      now: noon,
    );
    for (final s in out) {
      expect(s.block, isNot(kRoomBlocks[0]));
      expect(s.block, isNot(kRoomBlocks[1]));
      expect(s.block, isNot(kRoomBlocks[2]));
    }
    expect(out.any((s) => s.kind == SuggestionKind.afterClass), isTrue);
  });

  test('a day off still offers the current block', () {
    final out = suggestRooms(
      timetable: term,
      date: tuesday,
      classes: const [],
      free: {kRoomBlocks[0]: [room('N8101')]},
      now: early,
    );
    expect(out.single.kind, SuggestionKind.now);
  });

  test('a gap between classes gets 课前 and 课后, sports grounds left out', () {
    final a = cls('A', 'N9113', 3, 4);
    final b = cls('B', 'N8T02', 9, 10);
    final out = suggestRooms(
      timetable: term,
      date: tuesday,
      classes: [term.occurrence(a, tuesday)!, term.occurrence(b, tuesday)!],
      free: {
        for (final blk in kRoomBlocks)
          blk: [room('N9101'), room('体育场', seats: 1000)],
      },
      now: early,
    );
    final after = out.firstWhere((s) => s.kind == SuggestionKind.afterClass);
    expect(after.block, kRoomBlocks[2]);
    expect(after.reason, contains('第 3-4 节在 N9113'));
    final before = out.firstWhere(
      (s) => s.kind == SuggestionKind.beforeClass && s.block == kRoomBlocks[3],
    );
    expect(before.reason, startsWith('第 9-10 节'));
    for (final s in out) {
      expect(s.rooms.map((r) => r.name), isNot(contains('体育场')));
    }
  });

  test('building keys group rooms', () {
    expect(buildingKey('N8618'), 'N8');
    expect(buildingKey('n9402'), 'N9');
    expect(buildingKey('理科楼A402'), '理科楼A402');
  });
}
