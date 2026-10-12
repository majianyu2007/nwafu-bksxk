import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nwafu_bksxk/data/edu_models.dart';
import 'package:nwafu_bksxk/data/ics.dart';
import 'package:nwafu_bksxk/data/timetable_logic.dart';

TermTimetable tt() => TermTimetable(
  term: const EduTerm(code: '2026-2027-1', name: '2026-2027学年 秋'),
  firstMonday: DateTime.utc(2026, 9, 7),
  weekCount: 4,
  periods: ClassPeriod.nwafuDefault,
  sessions: const [
    CourseSession(
      id: 'K1-3-3-1111',
      courseName: '【本】数据结构',
      courseCode: 'C001',
      classNo: '01',
      weekday: 3,
      startPeriod: 3,
      endPeriod: 4,
      weeks: [1, 2, 3, 4],
      weeksLabel: '1-4周',
      room: 'N8618',
      teacher: '张三, 李四; 王五\\赵六',
    ),
    CourseSession(
      id: 'K2-1-1-1010',
      courseName: '高等数学',
      courseCode: 'M001',
      classNo: '02',
      weekday: 1,
      startPeriod: 1,
      endPeriod: 2,
      weeks: [1, 3],
      weeksLabel: '1-3周(单)',
      room: '教学楼一号楼一层一百零一教室（多媒体阶梯教室，可容纳两百人）东侧',
    ),
    // Period 20 is not on the bell schedule: no occurrence, no event.
    CourseSession(
      id: 'bad',
      courseName: '夜课',
      courseCode: 'X',
      classNo: '1',
      weekday: 2,
      startPeriod: 20,
      endPeriod: 20,
      weeks: [1],
      weeksLabel: '1周',
    ),
  ],
  syncedAt: DateTime.utc(2026, 9, 6),
);

/// Undo RFC 5545 folding.
List<String> unfold(String ics) =>
    ics.replaceAll('\r\n ', '').split('\r\n')..removeLast();

void main() {
  final now = DateTime.utc(2026, 10, 12, 1, 2, 3);

  test('occurrencesBetween expands sessions to dated CST instants', () {
    final t = tt();
    final all = occurrencesBetween(
      t,
      DateTime.utc(2026, 9, 6, 16),
      DateTime.utc(2026, 10, 4, 16),
    );
    expect(all, hasLength(6));
    expect(all.first.session.courseName, '高等数学');
    expect(all.first.start, DateTime.utc(2026, 9, 7, 0)); // 08:00 CST
    expect(all.first.end, DateTime.utc(2026, 9, 7, 1, 40)); // 09:40 CST
    // Half-open window: excluding the very first start drops one.
    expect(
      occurrencesBetween(
        t,
        DateTime.utc(2026, 9, 7, 0, 1),
        DateTime.utc(2026, 10, 4, 16),
      ),
      hasLength(5),
    );
  });

  test('document structure, CRLF, TZID and one VEVENT per occurrence', () {
    final ics = buildIcs(tt(), accountId: '2023012345', nowUtc: now);
    expect(ics, startsWith('BEGIN:VCALENDAR\r\nVERSION:2.0\r\n'));
    expect(ics, endsWith('END:VCALENDAR\r\n'));
    expect(ics.replaceAll('\r\n', ''), isNot(contains('\n')));
    final lines = unfold(ics);
    expect(
      lines,
      containsAllInOrder([
        'BEGIN:VTIMEZONE',
        'TZID:Asia/Shanghai',
        'BEGIN:STANDARD',
        'TZOFFSETFROM:+0800',
        'TZOFFSETTO:+0800',
        'END:STANDARD',
        'END:VTIMEZONE',
      ]),
    );
    expect(lines.where((l) => l.startsWith('BEGIN:DAYLIGHT')), isEmpty);
    expect(lines.where((l) => l == 'BEGIN:VEVENT'), hasLength(6));
    expect(lines.where((l) => l == 'BEGIN:VALARM'), isEmpty);
    expect(lines, contains('DTSTART;TZID=Asia/Shanghai:20260907T080000'));
    expect(lines, contains('DTEND;TZID=Asia/Shanghai:20260909T115000'));
    expect(lines, contains('DTSTAMP:20261012T010203Z'));
    expect(lines, contains('SUMMARY:数据结构'));
    expect(lines, contains('LOCATION:N8618'));
    expect(lines, contains(r'DESCRIPTION:教师：张三\, 李四\; 王五\\赵六\n第2周 周三 3-4节'));
  });

  test('lines fold at 75 octets without splitting UTF-8', () {
    final ics = buildIcs(tt(), accountId: 'a', nowUtc: now);
    for (final physical in ics.split('\r\n')) {
      expect(utf8.encode(physical).length, lessThanOrEqualTo(75));
    }
    expect(ics, contains('\r\n '));
    expect(unfold(ics), contains('LOCATION:教学楼一号楼一层一百零一教室（多媒体阶梯教室，可容纳两百人）东侧'));
    expect(foldIcsLine('A' * 75), 'A' * 75);
    expect(foldIcsLine('A' * 76), '${'A' * 75}\r\n A');
  });

  test('UIDs are stable across builds and unique per occurrence', () {
    List<String> uids(String ics) =>
        unfold(ics).where((l) => l.startsWith('UID:')).toList();
    final a = uids(buildIcs(tt(), accountId: '2023012345', nowUtc: now));
    final b = uids(
      buildIcs(tt(), accountId: '2023012345', nowUtc: DateTime.utc(2027)),
    );
    expect(a, b);
    expect(a.toSet(), hasLength(a.length));
    expect(
      a.first,
      matches(
        RegExp(
          r'^UID:nwafu-2023012345-2026-2027-1-[0-9a-f]{8}-20260907@nwafu-bksxk$',
        ),
      ),
    );
    final o = occurrencesBetween(
      tt(),
      DateTime.utc(2026, 9, 6, 16),
      DateTime.utc(2026, 9, 7, 16),
    ).single;
    expect(
      a.first,
      'UID:${occurrenceEventKey(o, accountId: '2023012345', termCode: '2026-2027-1')}@nwafu-bksxk',
    );
  });

  test('alarm and parseable exams are included, vague exams skipped', () {
    final ics = buildIcs(
      tt(),
      accountId: 'a',
      nowUtc: now,
      alarmMinutes: 15,
      exams: const [
        ExamEntry(
          courseName: '数据结构',
          date: '2026-12-20',
          time: '2026-12-20 09:00-11:00',
          room: 'N8306',
          seat: '12',
          kind: '期末考试',
        ),
        ExamEntry(courseName: '高等数学', time: '2026年12月22日 14:30'),
        ExamEntry(courseName: '大学英语', time: '第18周 待定'),
        ExamEntry(courseName: '体育', date: '2026-12-25'),
      ],
    );
    final lines = unfold(ics);
    expect(lines.where((l) => l == 'BEGIN:VEVENT'), hasLength(8));
    expect(lines.where((l) => l == 'TRIGGER:-PT15M'), hasLength(8));
    expect(lines, contains('ACTION:DISPLAY'));
    expect(lines, contains('SUMMARY:期末考试：数据结构'));
    expect(lines, contains('DTSTART;TZID=Asia/Shanghai:20261220T090000'));
    expect(lines, contains('DTEND;TZID=Asia/Shanghai:20261220T110000'));
    expect(lines, contains('DTSTART;TZID=Asia/Shanghai:20261222T143000'));
    expect(lines, contains('DTEND;TZID=Asia/Shanghai:20261222T163000'));
    expect(lines.any((l) => l.contains('大学英语') || l.contains('体育')), isFalse);
  });
}
