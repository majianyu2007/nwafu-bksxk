import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nwafu_bksxk/data/calendar_sync.dart';
import 'package:nwafu_bksxk/data/edu_models.dart';
import 'package:nwafu_bksxk/data/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeCalendar implements CalendarAdapter {
  final calendars = <String, String>{};
  final events = <String, ({String cal, DeviceEvent e})>{};
  int _next = 0;
  final log = <String>[];
  bool grant = true;

  @override
  bool get supported => true;
  @override
  Future<bool> requestAccess() async => grant;

  @override
  Future<String> createOrFindCalendar(String name, {String? knownId}) async {
    if (knownId != null && calendars.containsKey(knownId)) return knownId;
    for (final e in calendars.entries) {
      if (e.value == name) return e.key;
    }
    final id = 'cal${_next++}';
    calendars[id] = name;
    log.add('calendar $name');
    return id;
  }

  @override
  Future<List<DeviceEvent>> listEvents(
    String calendarId,
    DateTime fromUtc,
    DateTime toUtc,
  ) async => [
    for (final v in events.values)
      if (v.cal == calendarId &&
          v.e.end.isAfter(fromUtc) &&
          v.e.start.isBefore(toUtc))
        v.e,
  ];

  DeviceEvent _toDevice(String id, CalendarEventData d) => DeviceEvent(
    id: id,
    title: d.title,
    start: d.start,
    end: d.end,
    location: d.location,
    description: d.fullDescription,
    url: d.url,
    alarmMinutes: [if (d.alarmMinutes != null) d.alarmMinutes!],
  );

  @override
  Future<String> upsert(
    String calendarId,
    CalendarEventData event, {
    String? existingId,
  }) async {
    final id = existingId ?? 'e${_next++}';
    log.add(
      existingId == null ? 'create ${event.title}' : 'update ${event.title}',
    );
    events[id] = (cal: calendarId, e: _toDevice(id, event));
    return id;
  }

  @override
  Future<void> delete(String eventId) async {
    log.add('delete ${events[eventId]?.e.title}');
    events.remove(eventId);
  }
}

CourseSession s(
  String id, {
  String name = '数据结构',
  String room = 'N8618',
  int day = 3,
  List<int> weeks = const [1, 2],
}) => CourseSession(
  id: id,
  courseName: name,
  courseCode: id,
  classNo: '01',
  weekday: day,
  startPeriod: 3,
  endPeriod: 4,
  weeks: weeks,
  weeksLabel: '',
  room: room,
);

TermTimetable tt(List<CourseSession> sessions) => TermTimetable(
  term: const EduTerm(code: '2026-2027-1', name: '秋'),
  firstMonday: DateTime.utc(2026, 9, 7),
  weekCount: 2,
  periods: ClassPeriod.nwafuDefault,
  sessions: sessions,
  syncedAt: DateTime.utc(2026, 9, 6),
);

void main() {
  late Storage storage;
  late FakeCalendar cal;
  final now = DateTime.utc(2026, 9, 1);
  const on = CalendarSyncOptions(enabled: true, alarmMinutes: 10);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = Storage(await SharedPreferences.getInstance());
    cal = FakeCalendar();
  });

  Future<CalendarSyncResult> sync(
    TermTimetable t, {
    CalendarSyncOptions options = on,
    List<ExamEntry> exams = const [],
  }) => syncTimetableToCalendar(
    adapter: cal,
    storage: storage,
    accountId: 'u1',
    timetable: t,
    exams: exams,
    options: options,
    now: now,
  );

  test(
    'creates the calendar and one event per dated class plus exams',
    () async {
      final r = await sync(
        tt([
          s('A'),
          s('B', name: '高数', day: 1, weeks: const [1]),
        ]),
        exams: const [
          ExamEntry(courseName: '高数', date: '2026-09-25', time: '09:00-11:00'),
          ExamEntry(courseName: '未定'),
        ],
      );
      expect(cal.calendars.values, [kCalendarName]);
      expect(r.created, 4); // A wk1, A wk2, B wk1, exam
      expect(
        cal.events.values.map((v) => v.e.alarmMinutes),
        everyElement([10]),
      );
      expect(storage.calendarId(), cal.calendars.keys.single);
      final index = jsonDecode(storage.calendarIndex('u1')!) as Map;
      expect(index, hasLength(4));
      expect(cal.events.values.every((v) => v.e.key != null), isTrue);
    },
  );

  test('a second identical sync changes nothing', () async {
    final t = tt([s('A')]);
    await sync(t);
    cal.log.clear();
    final r = await sync(t);
    expect(r.unchanged, 2);
    expect(r.created + r.updated + r.deleted, 0);
    expect(cal.log, isEmpty);
  });

  test('a room change updates in place; a dropped class is deleted', () async {
    await sync(tt([s('A'), s('B', name: '高数', day: 1)]));
    final ids = cal.events.keys.toSet();
    cal.log.clear();
    final r = await sync(tt([s('A', room: 'N8306')]));
    expect(r.updated, 2);
    expect(r.deleted, 2);
    expect(r.created, 0);
    expect(cal.events.keys.toSet().difference(ids), isEmpty);
    expect(cal.events.values.map((v) => v.e.location), everyElement('N8306'));
  });

  test("the user's own events in the calendar are never touched", () async {
    await sync(tt([s('A')]));
    final calId = storage.calendarId()!;
    cal.events['mine'] = (
      cal: calId,
      e: DeviceEvent(
        id: 'mine',
        title: '社团活动',
        start: DateTime.utc(2026, 9, 9, 10),
        end: DateTime.utc(2026, 9, 9, 11),
      ),
    );
    await sync(tt(const []));
    expect(cal.events.keys, ['mine']);
  });

  test('turning sync off removes only this app\'s events', () async {
    await sync(tt([s('A')]));
    final r = await sync(tt([s('A')]), options: const CalendarSyncOptions());
    expect(r.deleted, 2);
    expect(cal.events, isEmpty);
    expect(jsonDecode(storage.calendarIndex('u1')!), isEmpty);
  });

  test('duplicates of one key collapse to one event', () async {
    await sync(
      tt([
        s('A', weeks: const [1]),
      ]),
    );
    final original = cal.events.values.single.e;
    cal.events['dup'] = (
      cal: storage.calendarId()!,
      e: DeviceEvent(
        id: 'dup',
        title: original.title,
        start: original.start,
        end: original.end,
        description: original.description,
        url: original.url,
      ),
    );
    final r = await sync(
      tt([
        s('A', weeks: const [1]),
      ]),
    );
    expect(r.deleted, 1);
    expect(cal.events, hasLength(1));
    expect(cal.events.keys.single, isNot('dup'));
  });

  test('alarm option change updates every event', () async {
    await sync(tt([s('A')]));
    final r = await sync(
      tt([s('A')]),
      options: const CalendarSyncOptions(enabled: true),
    );
    expect(r.updated, 2);
    expect(
      cal.events.values.map((v) => v.e.alarmMinutes),
      everyElement(isEmpty),
    );
  });

  test('refused permission throws CalendarUnavailable', () async {
    cal.grant = false;
    expect(() => sync(tt([s('A')])), throwsA(isA<CalendarUnavailable>()));
  });

  test('key is recovered from the description when the URL is lost', () {
    final t = DateTime.utc(2026, 9, 9);
    final d = CalendarEventData(
      key: 'nwafu-u1-x',
      title: 't',
      start: t,
      end: t,
      description: '教师：张三',
    );
    final e = DeviceEvent(
      id: '1',
      title: 't',
      start: t,
      end: t,
      description: d.fullDescription,
    );
    expect(e.key, 'nwafu-u1-x');
  });
}
