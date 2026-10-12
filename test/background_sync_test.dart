import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart' show CookieJar;
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nwafu_bksxk/data/background_sync.dart';
import 'package:nwafu_bksxk/data/cas_client.dart';
import 'package:nwafu_bksxk/data/edu_models.dart';
import 'package:nwafu_bksxk/data/ehall_service.dart';
import 'package:nwafu_bksxk/data/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

const term = EduTerm(code: '2026-2027-1', name: '2026-2027学年 秋');

CourseSession s(String id, {String room = 'N8618', int day = 3}) =>
    CourseSession(
      id: id,
      courseName: '数据结构',
      courseCode: 'C001',
      classNo: '01',
      weekday: day,
      startPeriod: 3,
      endPeriod: 4,
      weeks: const [1, 2, 3, 4],
      weeksLabel: '1-4周',
      room: room,
    );

TermTimetable tt(List<CourseSession> sessions, {EduTerm t = term}) =>
    TermTimetable(
      term: t,
      firstMonday: DateTime.utc(2026, 9, 7),
      weekCount: 18,
      periods: ClassPeriod.nwafuDefault,
      sessions: sessions,
      syncedAt: DateTime.utc(2026, 9, 6),
    );

GradeBook book(Map<String, String> scores) => GradeBook(
  records: [
    for (final e in scores.entries)
      GradeRecord(
        termCode: '2025-2026-2',
        termName: '',
        courseName: e.key,
        courseCode: 'K-${e.key}',
        credit: 2,
        scoreText: e.value,
        score: double.tryParse(e.value),
      ),
  ],
  summary: const GradeSummary(),
  syncedAt: DateTime.utc(2026, 9, 1),
);

class RecordingAlerts implements EduAlerts {
  final timetable = <String>[];
  final grades = <String>[];
  @override
  Future<void> timetableUpdated(String body) async => timetable.add(body);
  @override
  Future<void> gradesUpdated(String body) async => grades.add(body);
}

class FakeEhall extends EhallService {
  FakeEhall(this.table, this.gradeBook, {this.examList = const []})
    : super(CasClient(cookieJar: CookieJar(), dio: Dio()));
  TermTimetable table;
  GradeBook gradeBook;
  List<ExamEntry> examList;
  @override
  Future<EduTerm> currentTerm() async => table.term;
  @override
  Future<TermTimetable> timetable(EduTerm term) async => table;
  @override
  Future<GradeBook> grades() async => gradeBook;
  @override
  Future<List<ExamEntry>> exams(EduTerm term) async => examList;
}

Future<Storage> freshStorage() async {
  SharedPreferences.setMockInitialValues({});
  return Storage(await SharedPreferences.getInstance());
}

void main() {
  test('first sync stores the cache but never notifies', () async {
    final storage = await freshStorage();
    final alerts = RecordingAlerts();
    final core = EduSyncCore(storage, alerts);
    final ehall = FakeEhall(tt([s('1')]), book({'高数': '90'}));
    final r = await core.refresh('u1', ehall, now: DateTime.utc(2026, 10, 1));
    expect(r.timetableDiff, isNull);
    expect(r.gradeDiff, isNull);
    expect(alerts.timetable, isEmpty);
    expect(alerts.grades, isEmpty);
    expect(storage.eduTimetable('u1', term.code), isNotNull);
    expect(storage.eduGrades('u1'), isNotNull);
    expect(storage.eduLastSync('u1'), DateTime.utc(2026, 10, 1));
    expect(readChangeLog(storage, 'u1'), isEmpty);
  });

  test(
    'a changed timetable notifies once and is logged; unchanged is silent',
    () async {
      final storage = await freshStorage();
      final alerts = RecordingAlerts();
      final core = EduSyncCore(storage, alerts);
      final ehall = FakeEhall(tt([s('1')]), book({'高数': '90'}));
      await core.refresh('u1', ehall);
      ehall.table = tt([s('1', room: 'N8306')]);
      await core.refresh('u1', ehall);
      expect(alerts.timetable, ['数据结构 周三 3-4节：教室 N8618→N8306']);
      // Same data again: no second alert, no second log entry.
      await core.refresh('u1', ehall);
      expect(alerts.timetable, hasLength(1));
      final log = readChangeLog(storage, 'u1');
      expect(log, hasLength(1));
      expect(log.single.termCode, term.code);
    },
  );

  test('new grades notify once; first-ever grade sync does not', () async {
    final storage = await freshStorage();
    final alerts = RecordingAlerts();
    final core = EduSyncCore(storage, alerts);
    final ehall = FakeEhall(tt([s('1')]), book({'高数': '90'}));
    await core.refresh('u1', ehall);
    ehall.gradeBook = book({'高数': '90', '英语': '85'});
    await core.refresh('u1', ehall);
    await core.refresh('u1', ehall);
    expect(alerts.grades, ['新成绩：英语 85']);
  });

  test('a different term is not diffed against the old term', () async {
    final storage = await freshStorage();
    final alerts = RecordingAlerts();
    final core = EduSyncCore(storage, alerts);
    await core.recordTimetable('u1', tt([s('1')]));
    await storage.setEduTimetable('u1', term.code, tt([s('1')]).encode());
    const next = EduTerm(code: '2026-2027-2', name: '春');
    final d = await core.recordTimetable('u1', tt([s('9', day: 1)], t: next));
    expect(d, isNull);
    expect(alerts.timetable, isEmpty);
  });

  test('alerts can be switched off while the log is still kept', () async {
    final storage = await freshStorage();
    await storage.setTimetableChangeAlerts(false);
    final alerts = RecordingAlerts();
    final core = EduSyncCore(storage, alerts);
    await storage.setEduTimetable('u1', term.code, tt([s('1')]).encode());
    await core.recordTimetable('u1', tt([s('1', room: 'X')]));
    expect(alerts.timetable, isEmpty);
    expect(readChangeLog(storage, 'u1'), hasLength(1));
  });

  test('the change log keeps the newest 20 entries', () async {
    final storage = await freshStorage();
    final core = EduSyncCore(storage, RecordingAlerts());
    for (var i = 0; i < 25; i++) {
      await storage.setEduTimetable(
        'u1',
        term.code,
        tt([s('1', room: 'R$i')]).encode(),
      );
      await core.recordTimetable(
        'u1',
        tt([s('1', room: 'R${i + 1}')]),
        now: DateTime.utc(2026, 10, 1).add(Duration(hours: i)),
      );
    }
    final log = readChangeLog(storage, 'u1');
    expect(log, hasLength(kChangeLogLimit));
    expect(log.first.at, DateTime.utc(2026, 10, 1, 24));
    expect(jsonDecode(storage.timetableChangeLog('u1')!), hasLength(20));
  });

  test('refreshDue honours the interval and "off"', () {
    final now = DateTime.utc(2026, 10, 12, 12);
    expect(refreshDue(null, 12, now), isTrue);
    expect(refreshDue(null, 0, now), isFalse);
    expect(refreshDue(now.subtract(const Duration(hours: 3)), 6, now), isFalse);
    expect(refreshDue(now.subtract(const Duration(hours: 6)), 6, now), isTrue);
    expect(
      refreshDue(now.subtract(const Duration(hours: 11, minutes: 55)), 12, now),
      isTrue,
    );
  });

  group('exam reminders', () {
    const exam = ExamEntry(
      courseName: '高等数学',
      date: '2026-12-20',
      time: '09:00-11:00',
      room: 'N8101',
      seat: '12',
      kind: '期末',
    );

    test('evening before at 20:00 CST and one hour before the start', () {
      final now = DateTime.utc(2026, 12, 15);
      final plans = planExamReminders(const [exam], now);
      expect(plans, hasLength(2));
      // 2026-12-19 20:00 CST = 12:00 UTC.
      expect(plans[0].at, DateTime.utc(2026, 12, 19, 12));
      expect(plans[0].title, '明天考试：高等数学（期末）');
      expect(plans[0].body, '12月20日 09:00 N8101 · 座位 12');
      // 09:00 CST - 1h = 00:00 UTC.
      expect(plans[1].at, DateTime.utc(2026, 12, 20, 0));
      expect(plans[1].title, '1 小时后考试：高等数学（期末）');
      expect(plans.every((p) => p.id >= 1 << 30), isTrue);
      expect(plans[0].id, isNot(plans[1].id));
    });

    test('past reminders, unparseable exams and far-off exams are skipped', () {
      final plans = planExamReminders(
        const [exam, ExamEntry(courseName: '无时间', date: '待定')],
        DateTime.utc(2026, 12, 19, 13), // after the evening reminder
      );
      expect(plans.single.title, startsWith('1 小时后'));
      expect(
        planExamReminders(const [exam], DateTime.utc(2026, 11, 1)),
        isEmpty,
      );
    });

    test('ids are stable across plans', () {
      final now = DateTime.utc(2026, 12, 15);
      expect(
        planExamReminders(const [exam], now).map((p) => p.id),
        planExamReminders(const [
          exam,
        ], now.add(const Duration(hours: 1))).map((p) => p.id),
      );
    });
  });
}
