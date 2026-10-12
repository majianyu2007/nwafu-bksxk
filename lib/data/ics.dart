/// iCalendar (RFC 5545) export of a term timetable, for importing into any
/// calendar app. One VEVENT per dated class so 单双周 and 调课 survive
/// calendar apps with weak RRULE support; times are local to Asia/Shanghai
/// with an embedded VTIMEZONE.
library;

import 'dart:convert';

import 'edu_models.dart';
import 'timetable_diff.dart' show slotLabel;
import 'timetable_logic.dart';

const _cst = Duration(hours: 8);
const _domain = 'nwafu-bksxk';

/// The stable identity of one exported event, shared by the ICS `UID` and
/// the system-calendar sync (which stores it to find its own events again).
/// Same account + term + session + date always gives the same key.
String calendarEventKey({
  required String accountId,
  required String termCode,
  required String sessionId,
  required DateTime date,
}) =>
    'nwafu-${_safe(accountId)}-${_safe(termCode)}-'
    '${_fnv(sessionId)}-${_ymd(date)}';

/// [calendarEventKey] for a dated class.
String occurrenceEventKey(
  ClassOccurrence o, {
  required String accountId,
  required String termCode,
}) => calendarEventKey(
  accountId: accountId,
  termCode: termCode,
  sessionId: o.session.id,
  date: o.date,
);

/// A dated exam, when [ExamEntry] has a parseable date and start time.
class ExamSlot {
  const ExamSlot({required this.exam, required this.start, required this.end});
  final ExamEntry exam;

  /// UTC instants.
  final DateTime start;
  final DateTime end;

  /// School-calendar day (UTC midnight).
  DateTime get date {
    final l = start.add(_cst);
    return DateTime.utc(l.year, l.month, l.day);
  }
}

/// Reads the date from `date` (or `time`) as `2026-12-20`, `2026/12/20` or
/// `2026年12月20日`, and the time from `time` as `09:00-11:00` (or a lone
/// start, assumed to last two hours). Anything else is null: an exam with
/// no reliable instant is not exported.
ExamSlot? examSlot(ExamEntry e) {
  final dateRe = RegExp(r'(\d{4})\s*[-/年.]\s*(\d{1,2})\s*[-/月.]\s*(\d{1,2})');
  final d = dateRe.firstMatch(e.date) ?? dateRe.firstMatch(e.time);
  if (d == null) return null;
  final y = int.parse(d[1]!), mo = int.parse(d[2]!), da = int.parse(d[3]!);
  final day = DateTime.utc(y, mo, da);
  if (day.month != mo || day.day != da) return null;
  final rest = e.time.replaceFirst(dateRe, ' ');
  final t = RegExp(
    r'(\d{1,2})[:：](\d{2})(?:\s*[-–—~～至]\s*(\d{1,2})[:：](\d{2}))?',
  ).firstMatch(rest);
  if (t == null) return null;
  int mins(String h, String m) => int.parse(h) * 60 + int.parse(m);
  final s = mins(t[1]!, t[2]!);
  final en = t[3] == null ? s + 120 : mins(t[3]!, t[4]!);
  if (s >= 24 * 60 || en <= s || int.parse(t[2]!) > 59) return null;
  return ExamSlot(
    exam: e,
    start: schoolInstant(day, s),
    end: schoolInstant(day, en),
  );
}

/// Builds a `.ics` document for [t]: every class from week 1 to the last
/// week, plus [exams] that have a parseable date and time. [alarmMinutes]
/// adds a display alarm that many minutes before each event. [nowUtc] is
/// the DTSTAMP (defaults to now); pass it for reproducible output.
String buildIcs(
  TermTimetable t, {
  required String accountId,
  int? alarmMinutes,
  List<ExamEntry> exams = const [],
  DateTime? nowUtc,
}) {
  final stamp = _utcStamp((nowUtc ?? DateTime.now()).toUtc());
  final lines = <String>[
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//nwafu-bksxk//timetable//ZH',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'X-WR-CALNAME:${_esc('课表 ${t.term.name}')}',
    'X-WR-TIMEZONE:Asia/Shanghai',
    'BEGIN:VTIMEZONE',
    'TZID:Asia/Shanghai',
    'BEGIN:STANDARD',
    'DTSTART:19700101T000000',
    'TZOFFSETFROM:+0800',
    'TZOFFSETTO:+0800',
    'TZNAME:CST',
    'END:STANDARD',
    'END:VTIMEZONE',
  ];

  void event({
    required String uid,
    required DateTime start,
    required DateTime end,
    required String summary,
    required String location,
    required String description,
  }) {
    lines
      ..add('BEGIN:VEVENT')
      ..add('UID:$uid')
      ..add('DTSTAMP:$stamp')
      ..add('DTSTART;TZID=Asia/Shanghai:${_local(start)}')
      ..add('DTEND;TZID=Asia/Shanghai:${_local(end)}')
      ..add('SUMMARY:${_esc(summary)}');
    if (location.isNotEmpty) lines.add('LOCATION:${_esc(location)}');
    if (description.isNotEmpty) lines.add('DESCRIPTION:${_esc(description)}');
    if (alarmMinutes != null && alarmMinutes >= 0) {
      lines
        ..add('BEGIN:VALARM')
        ..add('ACTION:DISPLAY')
        ..add('DESCRIPTION:${_esc(summary)}')
        ..add('TRIGGER:-PT${alarmMinutes}M')
        ..add('END:VALARM');
    }
    lines.add('END:VEVENT');
  }

  final termStart = schoolInstant(t.firstMonday, 0);
  final termEnd = schoolInstant(
    t.firstMonday.add(Duration(days: t.weekCount * 7)),
    0,
  );
  for (final o in occurrencesBetween(t, termStart, termEnd)) {
    final s = o.session;
    final week = t.weekOf(o.date);
    event(
      uid:
          '${occurrenceEventKey(o, accountId: accountId, termCode: t.term.code)}@$_domain',
      start: o.start,
      end: o.end,
      summary: s.displayName,
      location: s.room.trim(),
      description: [
        if (s.teacher.trim().isNotEmpty) '教师：${s.teacher.trim()}',
        [if (week != null) '第$week周', slotLabel(s)].join(' '),
        if (s.note.trim().isNotEmpty) s.note.trim(),
      ].join('\n'),
    );
  }

  for (final e in exams) {
    final slot = examSlot(e);
    if (slot == null) continue;
    final key = calendarEventKey(
      accountId: accountId,
      termCode: t.term.code,
      sessionId: 'exam:${e.courseName}:${e.kind}',
      date: slot.date,
    );
    event(
      uid: '$key@$_domain',
      start: slot.start,
      end: slot.end,
      summary: '${e.kind.isEmpty ? '考试' : e.kind}：${e.courseName}',
      location: e.room,
      description: [
        if (e.seat.isNotEmpty) '座位号：${e.seat}',
        if (e.time.isNotEmpty) e.time,
      ].join('\n'),
    );
  }

  lines.add('END:VCALENDAR');
  return '${lines.map(foldIcsLine).join('\r\n')}\r\n';
}

/// RFC 5545 §3.3.11 TEXT escaping.
String _esc(String s) => s
    .replaceAll('\\', '\\\\')
    .replaceAll(';', '\\;')
    .replaceAll(',', '\\,')
    .replaceAll('\r\n', '\\n')
    .replaceAll('\n', '\\n')
    .replaceAll('\r', '\\n');

/// Exposed for tests. RFC 5545 §3.1: lines longer than 75 octets are split
/// with CRLF + one space, never inside a UTF-8 sequence.
String foldIcsLine(String line) {
  final bytes = utf8.encode(line);
  if (bytes.length <= 75) return line;
  final out = StringBuffer();
  var budget = 75;
  var used = 0;
  for (final rune in line.runes) {
    final ch = String.fromCharCode(rune);
    final n = utf8.encode(ch).length;
    if (used + n > budget) {
      out.write('\r\n ');
      budget = 74; // the leading space counts
      used = 0;
    }
    out.write(ch);
    used += n;
  }
  return out.toString();
}

String _two(int v) => v.toString().padLeft(2, '0');
String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}${_two(d.month)}${_two(d.day)}';

String _local(DateTime utc) {
  final l = utc.toUtc().add(_cst);
  return '${_ymd(l)}T${_two(l.hour)}${_two(l.minute)}${_two(l.second)}';
}

String _utcStamp(DateTime utc) =>
    '${_ymd(utc)}T${_two(utc.hour)}${_two(utc.minute)}${_two(utc.second)}Z';

String _safe(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');

/// 32-bit FNV-1a, hex.
String _fnv(String s) {
  var h = 0x811c9dc5;
  for (final b in utf8.encode(s)) {
    h ^= b;
    // h * 0x01000193 split so every intermediate stays below 2^53: the
    // result is identical on native and web (where ints are doubles).
    h = (((h << 24) & 0xffffffff) + h * 0x193) & 0xffffffff;
  }
  return h.toRadixString(16).padLeft(8, '0');
}
