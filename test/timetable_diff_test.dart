import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nwafu_bksxk/data/edu_models.dart';
import 'package:nwafu_bksxk/data/timetable_diff.dart';

CourseSession s(
  String id, {
  String name = '数据结构',
  String code = 'C001',
  String classNo = '01',
  int day = 3,
  int start = 3,
  int end = 4,
  List<int> weeks = const [1, 2, 3, 4],
  String room = 'N8618',
  String teacher = '张三',
  bool custom = false,
}) => CourseSession(
  id: id,
  courseName: name,
  courseCode: code,
  classNo: classNo,
  weekday: day,
  startPeriod: start,
  endPeriod: end,
  weeks: weeks,
  weeksLabel: '',
  room: room,
  teacher: teacher,
  custom: custom,
);

TermTimetable tt(List<CourseSession> sessions) => TermTimetable(
  term: const EduTerm(code: '2026-2027-1', name: '2026-2027学年 秋'),
  firstMonday: DateTime.utc(2026, 9, 7),
  weekCount: 18,
  periods: ClassPeriod.nwafuDefault,
  sessions: sessions,
  syncedAt: DateTime.utc(2026, 9, 6),
);

GradeRecord g(String name, String text, {String term = '2025-2026-2'}) =>
    GradeRecord(
      termCode: term,
      termName: term,
      courseName: name,
      courseCode: 'K-$name',
      credit: 3,
      scoreText: text,
      score: double.tryParse(text),
    );

GradeBook book(List<GradeRecord> r) => GradeBook(
  records: r,
  summary: const GradeSummary(),
  syncedAt: DateTime.utc(2026, 9, 1),
);

void main() {
  test('identical timetables, ids and order aside, have no diff', () {
    final a = tt([s('1'), s('2', name: '高数', code: 'M1', day: 1)]);
    final b = tt([s('x2', name: '高数', code: 'M1', day: 1), s('x1')]);
    final d = diffTimetables(a, b);
    expect(d.isEmpty, isTrue);
    expect(d.summary(), '课表无变动');
  });

  test('room change in the same slot is a field change', () {
    final d = diffTimetables(tt([s('1')]), tt([s('1', room: 'N8306')]));
    expect(d.added, isEmpty);
    expect(d.removed, isEmpty);
    expect(d.changed.single.changes.single.field, 'room');
    expect(d.summary(), '数据结构 周三 3-4节：教室 N8618→N8306');
  });

  test('teacher and weeks changes are reported together', () {
    final d = diffTimetables(
      tt([s('1')]),
      tt([
        s('1', teacher: '李四', weeks: const [1, 3, 5, 7]),
      ]),
    );
    expect(d.changed.single.changes.map((c) => c.field), ['teacher', 'weeks']);
    expect(d.summary(), '数据结构 周三 3-4节：教师 张三→李四，周次 1-4周→1-7周(单)');
  });

  test('a session in a new slot of the same course is a move', () {
    final d = diffTimetables(
      tt([s('1'), s('2', name: '高数', code: 'M1', day: 1)]),
      tt([
        s('1', day: 5, start: 1, end: 2),
        s('2', name: '高数', code: 'M1', day: 1),
      ]),
    );
    expect(d.added, isEmpty);
    expect(d.removed, isEmpty);
    final c = d.changed.single;
    expect(c.moved, isTrue);
    expect(d.summary(), '数据结构 周三 3-4节：时间 周三 3-4节→周五 1-2节');
  });

  test('new and dropped courses are added/removed; custom ignored', () {
    final d = diffTimetables(
      tt([s('1'), s('c', name: '自习', code: '', custom: true)]),
      tt([s('2', name: '高数', code: 'M1', day: 1)]),
    );
    expect(d.added.single.courseName, '高数');
    expect(d.removed.single.courseName, '数据结构');
    expect(d.changed, isEmpty);
    expect(d.summary(), '新增 高数 周一 3-4节；取消 数据结构 周三 3-4节');
  });

  test('summary truncates after max lines', () {
    final old = tt([
      for (var i = 1; i <= 5; i++) s('$i', name: 'C$i', code: 'C$i', day: i),
    ]);
    final fresh = tt([
      for (var i = 1; i <= 5; i++)
        s('$i', name: 'C$i', code: 'C$i', day: i, room: 'R$i'),
    ]);
    final d = diffTimetables(old, fresh);
    expect(d.count, 5);
    expect(d.summary(max: 2), endsWith('；等 5 处变动'));
    expect(d.summary(max: 2).split('；').length, 3);
  });

  test('diff round-trips through JSON with its timestamp', () {
    final at = DateTime.utc(2026, 10, 12, 3);
    final d = diffTimetables(
      tt([s('1'), s('2', name: '旧', code: 'O1', day: 2)]),
      tt([s('1', room: 'N8306'), s('3', name: '新', code: 'N1', day: 4)]),
      at: at,
    );
    final back = TimetableDiff.fromJson(
      jsonDecode(jsonEncode(d.toJson())) as Map<String, dynamic>,
    );
    expect(back.at, at);
    expect(back.termCode, '2026-2027-1');
    expect(back.summary(), d.summary());
    expect(back.count, 3);
  });

  test('new grades: appeared or score changed, summary in Chinese', () {
    final old = book([g('高等数学', '88'), g('大学英语', '85')]);
    final fresh = book([g('高等数学', '92'), g('大学英语', '85'), g('体育', '优秀')]);
    final d = newGrades(old, fresh);
    expect(d.added.map((r) => r.courseName), ['体育']);
    expect(d.changed.map((r) => r.courseName), ['高等数学']);
    expect(d.summary(), '新成绩：体育 优秀、高等数学 92');
    expect(newGrades(fresh, fresh).isEmpty, isTrue);
    expect(newGrades(null, fresh).added, hasLength(3));
    expect(newGrades(null, fresh).summary(max: 1), '新成绩：高等数学 92 等 3 门');
  });

  test('same course in another term is a new grade', () {
    final d = newGrades(
      book([g('高等数学', '55')]),
      book([g('高等数学', '55'), g('高等数学', '75', term: '2026-2027-1')]),
    );
    expect(d.added.single.termCode, '2026-2027-1');
  });
}
