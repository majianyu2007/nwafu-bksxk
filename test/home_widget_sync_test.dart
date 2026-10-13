import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nwafu_bksxk/data/edu_models.dart';
import 'package:nwafu_bksxk/data/home_widget_sync.dart';

CourseSession session(
  String id, {
  required int day,
  required int from,
  required int to,
}) => CourseSession(
  id: id,
  courseName: '【本】课程$id',
  courseCode: 'C$id',
  classNo: '01',
  weekday: day,
  startPeriod: from,
  endPeriod: to,
  weeks: const [1, 2],
  weeksLabel: '1-2周',
  room: 'N$id',
  teacher: '王强',
);

TermTimetable timetable(List<CourseSession> s) => TermTimetable(
  term: const EduTerm(code: '2026-2027-1', name: '2026-2027学年 秋'),
  firstMonday: DateTime.utc(2026, 10, 5),
  weekCount: 2,
  periods: ClassPeriod.nwafuWinter,
  sessions: s,
  syncedAt: DateTime.utc(2026, 10, 1),
);

void main() {
  test('signed out: a message and no days', () {
    final p = widgetPayload(null, DateTime.utc(2026, 10, 14, 2));
    expect(p['v'], 2);
    expect(p['message'], isNotEmpty);
    expect(p['days'], isEmpty);
  });

  test('a week of CST days with dated classes, ordered by period', () {
    final t = timetable([
      session('B', day: 3, from: 3, to: 4),
      session('A', day: 3, from: 1, to: 2),
      session('C', day: 4, from: 1, to: 1),
    ]);
    // 2026-10-14 01:00 CST is still Wednesday (Oct 13 17:00 UTC).
    final now = DateTime.utc(2026, 10, 13, 17);
    final p = jsonDecode(widgetPayloadJson(t, now)) as Map<String, dynamic>;
    expect(p['message'], '');
    expect(p['term'], '2026-27 秋');
    final days = (p['days'] as List).cast<Map<String, dynamic>>();
    expect(days, hasLength(kWidgetDays));
    expect(days.first['date'], '2026-10-14');
    expect(days.first['week'], 2);
    expect(days.first['weekday'], 3);
    final today = (days.first['classes'] as List).cast<Map<String, dynamic>>();
    expect(today.map((c) => c['name']), ['课程A', '课程B']);
    expect(today.first['sec'], '1-2节');
    expect(today.first['room'], 'NA');
    // Winter bell: period 1 starts 08:00 CST = 00:00 UTC.
    expect(
      today.first['start'],
      DateTime.utc(2026, 10, 14).millisecondsSinceEpoch,
    );
    expect(today.first['time'], startsWith('08:00-'));
    final thu = (days[1]['classes'] as List).cast<Map<String, dynamic>>();
    expect(thu.single['sec'], '1节');
    // Past the term's end (week 2 ends Sunday Oct 18) days have no week.
    expect(days.last['date'], '2026-10-20');
    expect(days.last['week'], isNull);
    expect(days.last['classes'], isEmpty);
  });
}
