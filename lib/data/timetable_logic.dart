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

/// A reminder to schedule: [at] is when it fires.
class ReminderPlan {
  const ReminderPlan({
    required this.id,
    required this.at,
    required this.occurrence,
  });
  final int id;
  final DateTime at;
  final ClassOccurrence occurrence;
}

/// Reminders for classes starting within [horizon] of [now], [lead] before
/// each. Ids are stable for a given class slot so re-planning replaces
/// rather than duplicates. Back-to-back periods of one course share one
/// reminder because they are one session.
List<ReminderPlan> planReminders(
  TermTimetable t,
  DateTime now, {
  required Duration lead,
  int days = 7,
}) {
  final out = <ReminderPlan>[];
  for (final o in t.upcoming(now, days: days)) {
    final at = o.start.subtract(lead);
    if (!at.isAfter(now)) continue;
    out.add(ReminderPlan(id: reminderId(o), at: at, occurrence: o));
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
