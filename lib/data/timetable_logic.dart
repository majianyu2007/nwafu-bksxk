/// Pure timetable arithmetic: which teaching week a date is in, what runs on
/// a day, the current/next class, and when reminders fire. All times are
/// China Standard Time; calendar dates are UTC midnights (see
/// `academic_calendar.dart`), so device timezone and DST never shift a class.
library;

import 'academic_calendar.dart' show calendarDate, schoolDate;
import 'edu_models.dart';

/// One concrete class: a session on a dated day.
class ClassOccurrence {
  const ClassOccurrence({
    required this.session,
    required this.date,
    required this.start,
    required this.end,
  });
  final CourseSession session;

  /// The school-calendar day (UTC midnight).
  final DateTime date;

  /// Absolute instants (UTC) of the start of the first and the end of the
  /// last period.
  final DateTime start;
  final DateTime end;
}

/// Converts a school-calendar day + minutes after midnight (CST) to UTC.
DateTime schoolInstant(DateTime date, int minutes) => DateTime.utc(
  date.year,
  date.month,
  date.day,
).add(Duration(minutes: minutes - 8 * 60));

extension TermTimetableTime on TermTimetable {
  /// 1-based teaching week of [date], or null outside the term.
  int? weekOf(DateTime date) {
    final days = calendarDate(date).difference(firstMonday).inDays;
    if (days < 0 || days >= weekCount * 7) return null;
    return days ~/ 7 + 1;
  }

  /// The week to show for [now]: the current one, else week 1 before the
  /// term and the last week after it.
  int displayWeek(DateTime now) {
    final today = schoolDate(now);
    final w = weekOf(today);
    if (w != null) return w;
    return today.isBefore(firstMonday) ? 1 : weekCount;
  }

  DateTime dayOf(int week, int weekday) =>
      firstMonday.add(Duration(days: (week - 1) * 7 + weekday - 1));

  /// Sessions running in [week] on [weekday], ordered by period.
  List<CourseSession> sessionsOn(int week, int weekday) => [
    for (final s in sessions)
      if (s.weekday == weekday && s.runsInWeek(week)) s,
  ]..sort((a, b) => a.startPeriod.compareTo(b.startPeriod));

  ClassOccurrence? occurrence(CourseSession s, DateTime date) {
    final first = period(s.startPeriod, on: date);
    final last = period(s.endPeriod, on: date);
    if (first == null || last == null) return null;
    return ClassOccurrence(
      session: s,
      date: date,
      start: schoolInstant(date, first.start),
      end: schoolInstant(date, last.end),
    );
  }

  /// The classes on the school day containing [now].
  List<ClassOccurrence> classesOn(DateTime now) {
    final day = schoolDate(now);
    final week = weekOf(day);
    if (week == null) return const [];
    return [
      for (final s in sessionsOn(week, day.weekday))
        if (occurrence(s, day) case final o?) o,
    ];
  }

  /// Every class from [from] (inclusive) for [days] school days.
  List<ClassOccurrence> upcoming(DateTime from, {int days = 14}) {
    final out = <ClassOccurrence>[];
    final start = schoolDate(from);
    for (var i = 0; i < days; i++) {
      final day = start.add(Duration(days: i));
      final week = weekOf(day);
      if (week == null) continue;
      for (final s in sessionsOn(week, day.weekday)) {
        final o = occurrence(s, day);
        if (o != null && o.end.isAfter(from)) out.add(o);
      }
    }
    out.sort((a, b) => a.start.compareTo(b.start));
    return out;
  }
}

/// Every class whose start lies in [fromUtc, toUtc), in start order. The one
/// place that expands weekly sessions into dated instants (ICS export,
/// calendar sync); it goes through [TermTimetableTime.occurrence], so a
/// session whose periods are missing from the bell schedule is skipped.
List<ClassOccurrence> occurrencesBetween(
  TermTimetable t,
  DateTime fromUtc,
  DateTime toUtc,
) {
  final out = <ClassOccurrence>[];
  if (!toUtc.isAfter(fromUtc)) return out;
  final last = schoolDate(toUtc);
  for (
    var day = schoolDate(fromUtc);
    !day.isAfter(last);
    day = DateTime.utc(day.year, day.month, day.day + 1)
  ) {
    final week = t.weekOf(day);
    if (week == null) continue;
    for (final s in t.sessionsOn(week, day.weekday)) {
      final o = t.occurrence(s, day);
      if (o != null && !o.start.isBefore(fromUtc) && o.start.isBefore(toUtc)) {
        out.add(o);
      }
    }
  }
  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}

/// Where the student is in their day, for the 今日 card.
class DayStatus {
  const DayStatus({
    required this.today,
    this.current,
    this.next,
    required this.remaining,
  });
  final List<ClassOccurrence> today;
  final ClassOccurrence? current;
  final ClassOccurrence? next;

  /// Classes today that have not ended.
  final int remaining;

  static DayStatus of(TermTimetable t, DateTime now) {
    final today = t.classesOn(now);
    ClassOccurrence? current;
    for (final o in today) {
      if (!now.isBefore(o.start) && now.isBefore(o.end)) current = o;
    }
    final upcoming = t.upcoming(now, days: 8);
    final next = upcoming.where((o) => o.start.isAfter(now)).firstOrNull;
    return DayStatus(
      today: today,
      current: current,
      next: next,
      remaining: today.where((o) => o.end.isAfter(now)).length,
    );
  }
}

/// Why a reminder fires when it does; decides its wording.
enum ReminderReason {
  /// [lead] before class.
  normal,

  /// The day's first class, with the earlier first-class lead.
  firstOfDay,

  /// The previous class is in another building: fires when it ends.
  moveBuilding,
}

/// A reminder to schedule: [at] is when it fires.
class ReminderPlan {
  const ReminderPlan({
    required this.id,
    required this.at,
    required this.occurrence,
    this.reason = ReminderReason.normal,
    this.fromRoom,
  });
  final int id;
  final DateTime at;
  final ClassOccurrence occurrence;
  final ReminderReason reason;

  /// For [ReminderReason.moveBuilding]: where the previous class was.
  final String? fromRoom;
}

/// How reminders are planned. [lead] is the usual time before class;
/// [firstLead] (when set) replaces it for the day's first class, which
/// usually means leaving the dorm; [quietBefore] (minutes after midnight,
/// CST) moves a reminder that would fire earlier to that time, never past
/// the class start.
class ReminderRules {
  const ReminderRules({
    required this.lead,
    this.firstLead,
    this.skipSameRoom = true,
    this.moveBuilding = true,
    this.quietBefore = 7 * 60,
  });
  final Duration lead;
  final Duration? firstLead;

  /// No reminder for a class right after another in the same room.
  final bool skipSameRoom;

  /// Fire as the previous class ends when the next is in another building.
  final bool moveBuilding;
  final int? quietBefore;
}

/// Short building key for "is this another building": `N8618` → `N8`,
/// `理科楼A402` → `理科楼`.
String roomBuilding(String room) {
  final code = RegExp(r'^([A-Za-z]+\d)').firstMatch(room.trim());
  if (code != null) return code.group(1)!.toUpperCase();
  return room.trim().replaceFirst(RegExp(r'[A-Za-z]?\d.*$'), '');
}

/// Reminders for classes starting within [days] of [now]. Ids are stable for
/// a class slot so re-planning replaces rather than duplicates.
///
/// Per class, in order:
///  * right after another class in the same room (gap ≤ 30 min, the long break): none, the
///    student is already there ([ReminderRules.skipSameRoom]);
///  * right after a class in another building: fire when that class ends,
///    so the walk is not a surprise;
///  * the day's first class: [ReminderRules.firstLead] if set;
///  * otherwise [ReminderRules.lead].
/// A time before [ReminderRules.quietBefore] moves to it.
List<ReminderPlan> planReminders(
  TermTimetable t,
  DateTime now, {
  Duration? lead,
  ReminderRules? rules,
  int days = 7,
}) {
  final r = rules ?? ReminderRules(lead: lead ?? const Duration(minutes: 10));
  final out = <ReminderPlan>[];
  final upcoming = t.upcoming(now, days: days);
  // Every class of the days involved, to see what comes right before.
  final byDay = <DateTime, List<ClassOccurrence>>{};
  for (final o in upcoming) {
    byDay.putIfAbsent(o.date, () => t.classesOn(o.start));
  }
  for (final o in upcoming) {
    final day = byDay[o.date]!..sort((a, b) => a.start.compareTo(b.start));
    final before = day.where((p) => !p.end.isAfter(o.start)).lastOrNull;
    final gap = before == null ? null : o.start.difference(before.end);
    final adjacent = gap != null && gap <= const Duration(minutes: 30);
    final room = o.session.room;
    final prevRoom = before?.session.room ?? '';

    var reason = ReminderReason.normal;
    DateTime at;
    if (adjacent && room.isNotEmpty && room == prevRoom) {
      if (r.skipSameRoom) continue;
      at = o.start.subtract(r.lead);
    } else if (r.moveBuilding &&
        adjacent &&
        room.isNotEmpty &&
        prevRoom.isNotEmpty &&
        roomBuilding(room) != roomBuilding(prevRoom)) {
      reason = ReminderReason.moveBuilding;
      at = before!.end;
    } else if (before == null && r.firstLead != null) {
      reason = ReminderReason.firstOfDay;
      at = o.start.subtract(r.firstLead!);
    } else {
      at = o.start.subtract(r.lead);
    }
    final quiet = r.quietBefore;
    if (quiet != null) {
      final floor = schoolInstant(o.date, quiet);
      if (at.isBefore(floor)) at = floor.isBefore(o.start) ? floor : at;
    }
    if (!at.isAfter(now)) continue;
    out.add(
      ReminderPlan(
        id: reminderId(o),
        at: at,
        occurrence: o,
        reason: reason,
        fromRoom: reason == ReminderReason.moveBuilding ? prevRoom : null,
      ),
    );
  }
  return out;
}

/// A notification id in a range of its own (2^30 + …) so it never collides
/// with the immediate grab notifications, which count up from 0.
int reminderId(ClassOccurrence o) {
  var hash = 0x811c9dc5;
  for (final unit in '${o.session.id}:${o.date.toIso8601String()}'.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0x3fffffff;
  }
  return (1 << 30) | hash;
}

const kWeekdayNames = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
