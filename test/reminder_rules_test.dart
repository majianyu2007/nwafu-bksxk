import 'package:flutter_test/flutter_test.dart';
import 'package:nwafu_bksxk/data/edu_models.dart';
import 'package:nwafu_bksxk/data/timetable_logic.dart';

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

TermTimetable term(List<CourseSession> sessions) => TermTimetable(
  term: const EduTerm(code: '2026-2027-1', name: '秋'),
  firstMonday: DateTime.utc(2026, 10, 12),
  weekCount: 1,
  // 冬令: 1 08:00, 2 08:55-09:40, 3 10:10, 4 11:05-11:50
  periods: ClassPeriod.nwafuWinter,
  sessions: sessions,
  syncedAt: DateTime.utc(2026, 10, 1),
);

void main() {
  // Monday 20:00 CST.
  final now = DateTime.utc(2026, 10, 12, 12);

  List<ReminderPlan> plan(List<CourseSession> s, ReminderRules r) =>
      planReminders(term(s), now, rules: r, days: 3);

  String hm(DateTime t) {
    final c = t.add(const Duration(hours: 8));
    return '${c.hour}:${c.minute.toString().padLeft(2, '0')}';
  }

  test('the first class of the day uses its own lead', () {
    final out = plan(
      [cls('A', 'N8618', 1, 2), cls('B', 'N9101', 5, 6)],
      const ReminderRules(
        lead: Duration(minutes: 10),
        firstLead: Duration(minutes: 40),
      ),
    );
    expect(out.first.reason, ReminderReason.firstOfDay);
    expect(hm(out.first.at), '7:20');
    expect(out.last.reason, ReminderReason.normal);
  });

  test('a class right after another in the same room gets no reminder', () {
    final out = plan(
      [cls('A', 'N8618', 1, 2), cls('B', 'N8618', 3, 4)],
      const ReminderRules(lead: Duration(minutes: 10)),
    );
    expect(out.map((p) => p.occurrence.session.id), ['A']);
  });

  test('another building fires as the previous class ends', () {
    final out = plan(
      [cls('A', 'N8618', 1, 2), cls('B', '理科楼A402', 3, 4)],
      const ReminderRules(lead: Duration(minutes: 10)),
    );
    final b = out.firstWhere((p) => p.occurrence.session.id == 'B');
    expect(b.reason, ReminderReason.moveBuilding);
    expect(b.fromRoom, 'N8618');
    expect(hm(b.at), '9:40');
  });

  test('same building, next room: a normal reminder', () {
    final out = plan(
      [cls('A', 'N8618', 1, 2), cls('B', 'N8402', 3, 4)],
      const ReminderRules(lead: Duration(minutes: 10)),
    );
    final b = out.firstWhere((p) => p.occurrence.session.id == 'B');
    expect(b.reason, ReminderReason.normal);
    expect(hm(b.at), '10:00');
  });

  test('quiet hours move an early reminder to 07:00', () {
    final out = plan(
      [cls('A', 'N8618', 1, 2)],
      const ReminderRules(
        lead: Duration(minutes: 10),
        firstLead: Duration(minutes: 90),
      ),
    );
    expect(hm(out.single.at), '7:00');
  });

  test('room building keys', () {
    expect(roomBuilding('N8618'), 'N8');
    expect(roomBuilding('理科楼A402'), '理科楼');
    expect(roomBuilding('计算机机房103-A'), '计算机机房');
  });
}
