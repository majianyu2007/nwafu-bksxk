/// One-way sync of the timetable (and exams) into a dedicated device
/// calendar ("西农课表"). The device side is behind [CalendarAdapter] so the
/// reconciliation is unit-tested with a fake; `calendar_sync_device.dart`
/// is the real one (Android/iOS), the stub reports "unsupported".
///
/// Every event this app writes carries a stable key ([occurrenceEventKey] /
/// [calendarEventKey]) in its URL and as the last description line, so the
/// next sync finds it again; a key → event id index is kept in storage as a
/// fallback for platforms that drop the URL. Events in the calendar without
/// a key (added by the user) are never touched.
library;

import 'dart:convert';

import 'edu_models.dart';
import 'ics.dart';
import 'storage.dart';
import 'timetable_diff.dart' show slotLabel;
import 'timetable_logic.dart';

import 'calendar_sync_stub.dart'
    if (dart.library.io) 'calendar_sync_device.dart'
    as impl;

const kCalendarName = '西农课表';
const _urlPrefix = 'nwafu-bksxk://event/';
const _descPrefix = '#nwafu-key:';

/// An event as the app wants it to be.
class CalendarEventData {
  const CalendarEventData({
    required this.key,
    required this.title,
    required this.start,
    required this.end,
    this.location = '',
    this.description = '',
    this.alarmMinutes,
  });
  final String key;
  final String title;

  /// UTC instants.
  final DateTime start;
  final DateTime end;
  final String location;
  final String description;

  /// Minutes before start; null = no alarm.
  final int? alarmMinutes;

  String get url => '$_urlPrefix$key';

  /// The description written to the device, key line included.
  String get fullDescription =>
      [if (description.isNotEmpty) description, '$_descPrefix$key'].join('\n');
}

/// An event as read back from the device.
class DeviceEvent {
  const DeviceEvent({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    this.location = '',
    this.description = '',
    this.url = '',
    this.alarmMinutes = const [],
  });
  final String id;
  final String title;
  final DateTime start;
  final DateTime end;
  final String location;
  final String description;
  final String url;
  final List<int> alarmMinutes;

  /// The app's key, from the URL or the description's key line.
  String? get key {
    if (url.startsWith(_urlPrefix)) return url.substring(_urlPrefix.length);
    for (final line in description.split('\n').reversed) {
      final t = line.trim();
      if (t.startsWith(_descPrefix)) return t.substring(_descPrefix.length);
    }
    return null;
  }
}

class CalendarUnavailable implements Exception {
  const CalendarUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}

/// What a device calendar must offer.
abstract class CalendarAdapter {
  bool get supported;

  /// Asks for full calendar access; false when refused.
  Future<bool> requestAccess();

  /// The id of the calendar named [name], created when missing. [knownId]
  /// is the id saved last time and is preferred while it still exists.
  Future<String> createOrFindCalendar(String name, {String? knownId});

  Future<List<DeviceEvent>> listEvents(
    String calendarId,
    DateTime fromUtc,
    DateTime toUtc,
  );

  /// Creates the event, or updates [existingId]; returns the event id.
  Future<String> upsert(
    String calendarId,
    CalendarEventData event, {
    String? existingId,
  });

  Future<void> delete(String eventId);
}

/// The platform adapter (unsupported on web, Windows, Linux and macOS).
CalendarAdapter deviceCalendarAdapter() => impl.createDeviceCalendarAdapter();

class CalendarSyncOptions {
  const CalendarSyncOptions({
    this.enabled = false,
    this.alarmMinutes = -1,
    this.includeExams = true,
    this.range = 'term',
  });
  final bool enabled;

  /// -1 = none.
  final int alarmMinutes;
  final bool includeExams;

  /// `term` or `4w`.
  final String range;

  static CalendarSyncOptions read(Storage s) => CalendarSyncOptions(
    enabled: s.calendarSyncEnabled(),
    alarmMinutes: s.calendarAlarmMinutes(),
    includeExams: s.calendarIncludeExams(),
    range: s.calendarRange(),
  );
}

/// The window events are written for: the whole term, or from today's
/// school-day start for four weeks.
({DateTime from, DateTime to}) calendarWindow(
  TermTimetable t,
  String range,
  DateTime now,
) {
  final termStart = schoolInstant(t.firstMonday, 0);
  final termEnd = schoolInstant(
    t.firstMonday.add(Duration(days: t.weekCount * 7)),
    0,
  );
  if (range == '4w') {
    final today = schoolInstant(schoolDayOf(now), 0);
    return (from: today, to: today.add(const Duration(days: 28)));
  }
  return (from: termStart, to: termEnd);
}

DateTime schoolDayOf(DateTime now) {
  final l = now.toUtc().add(const Duration(hours: 8));
  return DateTime.utc(l.year, l.month, l.day);
}

/// The events the calendar should hold for [t] within [from, to).
List<CalendarEventData> buildCalendarEvents(
  TermTimetable t, {
  required String accountId,
  required DateTime from,
  required DateTime to,
  List<ExamEntry> exams = const [],
  int? alarmMinutes,
  DateTime? examsTo,
}) {
  final alarm = alarmMinutes != null && alarmMinutes >= 0 ? alarmMinutes : null;
  final out = <CalendarEventData>[];
  for (final o in occurrencesBetween(t, from, to)) {
    final s = o.session;
    final week = t.weekOf(o.date);
    out.add(
      CalendarEventData(
        key: occurrenceEventKey(o, accountId: accountId, termCode: t.term.code),
        title: s.displayName,
        start: o.start,
        end: o.end,
        location: s.room.trim(),
        description: [
          if (s.teacher.trim().isNotEmpty) '教师：${s.teacher.trim()}',
          [if (week != null) '第$week周', slotLabel(s)].join(' '),
          if (s.note.trim().isNotEmpty) s.note.trim(),
        ].join('\n'),
        alarmMinutes: alarm,
      ),
    );
  }
  for (final e in exams) {
    final slot = examSlot(e);
    if (slot == null ||
        slot.start.isBefore(from) ||
        !slot.start.isBefore(examsTo ?? to)) {
      continue;
    }
    out.add(
      CalendarEventData(
        key: calendarEventKey(
          accountId: accountId,
          termCode: t.term.code,
          sessionId: 'exam:${e.courseName}:${e.kind}',
          date: slot.date,
        ),
        title: '${e.kind.isEmpty ? '考试' : e.kind}：${e.courseName}',
        start: slot.start,
        end: slot.end,
        location: e.room,
        description: [
          if (e.seat.isNotEmpty) '座位号：${e.seat}',
          if (e.time.isNotEmpty) e.time,
        ].join('\n'),
        alarmMinutes: alarm,
      ),
    );
  }
  return out;
}

class CalendarSyncResult {
  const CalendarSyncResult({
    this.created = 0,
    this.updated = 0,
    this.deleted = 0,
    this.unchanged = 0,
  });
  final int created;
  final int updated;
  final int deleted;
  final int unchanged;

  String summary() => '新增 $created · 更新 $updated · 删除 $deleted · 未变 $unchanged';
}

bool _same(DeviceEvent d, CalendarEventData w) {
  int sec(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;
  final alarms = d.alarmMinutes;
  final wantAlarm = w.alarmMinutes;
  final alarmOk = wantAlarm == null
      ? alarms.isEmpty
      : alarms.length == 1 && alarms.first == wantAlarm;
  return d.title == w.title &&
      sec(d.start) == sec(w.start) &&
      sec(d.end) == sec(w.end) &&
      d.location.trim() == w.location.trim() &&
      d.description.trim() == w.fullDescription.trim() &&
      alarmOk;
}

/// Makes the calendar match [wanted] within [from, to): creates missing
/// events, updates differing ones, deletes this app's events in the window
/// that are no longer wanted (and duplicates of one key). [index] is the
/// stored key → id map; it is updated in place.
Future<CalendarSyncResult> reconcileCalendar(
  CalendarAdapter adapter,
  String calendarId,
  List<CalendarEventData> wanted, {
  required DateTime from,
  required DateTime to,
  required Map<String, String> index,
}) async {
  final existing = await adapter.listEvents(calendarId, from, to);
  final byKey = <String, DeviceEvent>{};
  final byId = {for (final e in existing) e.id: e};
  final extras = <DeviceEvent>[];
  for (final e in existing) {
    final key = e.key;
    if (key == null) continue; // user's own event
    if (byKey.containsKey(key)) {
      // Prefer the one the index points at; drop the other.
      if (index[key] == e.id) {
        extras.add(byKey[key]!);
        byKey[key] = e;
      } else {
        extras.add(e);
      }
    } else {
      byKey[key] = e;
    }
  }
  // Events whose URL/description the platform lost but the index knows.
  for (final entry in index.entries) {
    final e = byId[entry.value];
    if (e != null && e.key == null) byKey.putIfAbsent(entry.key, () => e);
  }

  var created = 0, updated = 0, deleted = 0, unchanged = 0;
  final wantedKeys = <String>{};
  for (final w in wanted) {
    if (!wantedKeys.add(w.key)) continue;
    final cur = byKey[w.key];
    if (cur != null && _same(cur, w)) {
      unchanged++;
      index[w.key] = cur.id;
      continue;
    }
    if (cur != null) {
      try {
        index[w.key] = await adapter.upsert(calendarId, w, existingId: cur.id);
        updated++;
        continue;
      } catch (_) {
        // Fall through to a fresh event; the stale one is removed below.
        extras.add(cur);
      }
    }
    index[w.key] = await adapter.upsert(calendarId, w);
    created++;
  }
  for (final e in [
    ...extras,
    for (final entry in byKey.entries)
      if (!wantedKeys.contains(entry.key)) entry.value,
  ]) {
    try {
      await adapter.delete(e.id);
      deleted++;
    } catch (_) {}
    index.removeWhere((k, v) => v == e.id && !wantedKeys.contains(k));
  }
  return CalendarSyncResult(
    created: created,
    updated: updated,
    deleted: deleted,
    unchanged: unchanged,
  );
}

/// The full sync for one identity: picks the window, builds the events,
/// ensures the calendar exists and reconciles. When the options are off,
/// removes this app's events in the term window instead.
Future<CalendarSyncResult> syncTimetableToCalendar({
  required CalendarAdapter adapter,
  required Storage storage,
  required String accountId,
  required TermTimetable timetable,
  List<ExamEntry> exams = const [],
  CalendarSyncOptions? options,
  DateTime? now,
}) async {
  if (!adapter.supported) {
    throw const CalendarUnavailable('当前平台不支持系统日历同步');
  }
  final o = options ?? CalendarSyncOptions.read(storage);
  if (!await adapter.requestAccess()) {
    throw const CalendarUnavailable('未获得日历权限');
  }
  final calendarId = await adapter.createOrFindCalendar(
    kCalendarName,
    knownId: storage.calendarId(),
  );
  if (calendarId != storage.calendarId()) {
    await storage.setCalendarId(calendarId);
  }
  final at = (now ?? DateTime.now()).toUtc();
  final window = calendarWindow(timetable, o.range, at);
  // Look past the window to the term end so shrinking the range (term →
  // 4 weeks) also removes the later events; past ones are kept.
  final termWindow = calendarWindow(timetable, 'term', at);
  final listTo = termWindow.to.isAfter(window.to) ? termWindow.to : window.to;
  final listFrom = o.range == '4w' ? window.from : termWindow.from;
  final wanted = o.enabled
      ? buildCalendarEvents(
          timetable,
          accountId: accountId,
          from: window.from,
          to: window.to,
          exams: o.includeExams ? exams : const [],
          alarmMinutes: o.alarmMinutes,
          // Exam weeks may follow the teaching weeks.
          examsTo: o.range == '4w'
              ? window.to
              : window.to.add(const Duration(days: 42)),
        )
      : const <CalendarEventData>[];
  final index = _readIndex(storage, accountId);
  final result = await reconcileCalendar(
    adapter,
    calendarId,
    wanted,
    from: listFrom,
    to: listTo.add(const Duration(days: 42)),
    index: index,
  );
  await storage.setCalendarIndex(accountId, jsonEncode(index));
  return result;
}

Map<String, String> _readIndex(Storage storage, String accountId) {
  final raw = storage.calendarIndex(accountId);
  if (raw == null) return {};
  try {
    return (jsonDecode(raw) as Map).map((k, v) => MapEntry('$k', '$v'));
  } catch (_) {
    return {};
  }
}
