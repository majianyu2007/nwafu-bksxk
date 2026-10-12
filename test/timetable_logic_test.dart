import 'package:flutter_test/flutter_test.dart';
import 'package:nwafu_bksxk/data/edu_models.dart';
import 'package:nwafu_bksxk/data/timetable_logic.dart';

CourseSession session(String id, {int end = 2}) => CourseSession(
  id: id,
  courseName: id,
  courseCode: id,
  classNo: '1',
  weekday: 1,
  startPeriod: 1,
  endPeriod: end,
  weeks: const [1, 3],
  weeksLabel: '1,3周',
);
TermTimetable timetable(List<CourseSession> sessions) => TermTimetable(
  term: const EduTerm(code: '2026-2027-1', name: '秋'),
  firstMonday: DateTime.utc(2026, 9, 7),
  weekCount: 3,
  periods: const [
    ClassPeriod(index: 1, start: 480, end: 525),
    ClassPeriod(index: 2, start: 535, end: 580),
  ],
  sessions: sessions,
  syncedAt: DateTime.utc(2026, 9, 6),
);

void main() {
  test(
    'school-time reminders respect week bits and exclude elapsed lead times',
    () {
      final t = timetable([session('A')]);
      final plans = planReminders(
        t,
        DateTime.utc(2026, 9, 6, 23),
        lead: const Duration(minutes: 10),
        days: 21,
      );
      expect(plans.map((p) => p.at), [
        DateTime.utc(2026, 9, 6, 23, 50),
        DateTime.utc(2026, 9, 20, 23, 50),
      ]);
      expect(
        planReminders(
          t,
          DateTime.utc(2026, 9, 6, 23, 50),
          lead: const Duration(minutes: 10),
          days: 1,
        ),
        isEmpty,
      );
      expect(t.weekOf(DateTime.utc(2026, 9, 6)), isNull);
      expect(t.weekOf(DateTime.utc(2026, 9, 28)), isNull);
    },
  );
  test('overlapping courses keep distinct notification ids', () {
    final plans = planReminders(
      timetable([session('A'), session('B')]),
      DateTime.utc(2026, 9, 6, 23),
      lead: const Duration(minutes: 10),
    );
    expect(plans.map((p) => p.occurrence.session.id), ['A', 'B']);
    expect(plans[0].id, isNot(plans[1].id));
  });
  test(
    'a period neither the bell schedule nor the server knows cannot fabricate an occurrence',
    () {
      final s = session('A', end: 13);
      expect(timetable([s]).occurrence(s, DateTime.utc(2026, 9, 7)), isNull);
    },
  );

  test('summer-term codes from the live term list parse', () {
    // xnxqcx.do returns 2020-2021-7 (暑期) among the terms; rejecting it
    // used to fail the whole timetable sync.
    final t = EduTerm.fromRow({'DM': '2020-2021-7', 'MC': '2020-2021学年 暑期'});
    expect(t.half, '7');
    expect(() => EduTerm.fromRow({'DM': '2020-2021'}), throwsFormatException);
  });

  test('winter/summer bell schedule switches on May 1 and Oct 1', () {
    expect(BellSeason.of(DateTime.utc(2026, 4, 30)), BellSeason.winter);
    expect(BellSeason.of(DateTime.utc(2026, 5, 1)), BellSeason.summer);
    expect(BellSeason.of(DateTime.utc(2026, 9, 30)), BellSeason.summer);
    expect(BellSeason.of(DateTime.utc(2026, 10, 1)), BellSeason.winter);
    final t = timetable([session('A')]);
    // Period 5: 14:00 in winter, 14:30 in summer (school 作息时间表).
    expect(t.period(5, on: DateTime.utc(2026, 10, 12))!.startLabel, '14:00');
    expect(t.period(5, on: DateTime.utc(2026, 6, 1))!.startLabel, '14:30');
    expect(t.period(11, on: DateTime.utc(2026, 12, 1))!.endLabel, '21:25');
    expect(t.period(1, on: DateTime.utc(2026, 12, 1))!.startLabel, '08:00');
  });

  test('occurrences use the bell schedule of their own date', () {
    const s = CourseSession(
      id: 'P',
      courseName: 'P',
      courseCode: 'P',
      classNo: '1',
      weekday: 3,
      startPeriod: 5,
      endPeriod: 6,
      weeks: [1, 2, 3, 4],
      weeksLabel: '1-4周',
    );
    final t = TermTimetable(
      term: const EduTerm(code: '2026-2027-1', name: '秋'),
      firstMonday: DateTime.utc(2026, 9, 21),
      weekCount: 4,
      periods: ClassPeriod.nwafuSummer,
      sessions: [s],
      syncedAt: DateTime.utc(2026, 9, 1),
    );
    // Wed Sep 23 → summer 14:30 CST = 06:30Z; Wed Oct 7 → winter 14:00 = 06:00Z.
    expect(
      t.occurrence(s, DateTime.utc(2026, 9, 23))!.start,
      DateTime.utc(2026, 9, 23, 6, 30),
    );
    expect(
      t.occurrence(s, DateTime.utc(2026, 10, 7))!.start,
      DateTime.utc(2026, 10, 7, 6),
    );
  });
}
