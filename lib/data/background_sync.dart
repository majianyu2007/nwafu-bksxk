/// The "fetch + diff + store + notify" step shared by the in-app refresh
/// (Riverpod controllers) and the OS background refresh (workmanager). No
/// Flutter widget or Riverpod imports, so the background isolate can use it.
///
/// Rules:
/// - A timetable is diffed only against the cached copy of the same term; a
///   first sync (no cache) never notifies.
/// - Grades are diffed against the cached book; no cached book = no alert.
/// - Each detected timetable change is kept in a per-account log (last 20).
library;

import 'dart:convert';

import 'edu_models.dart';
import 'ehall_service.dart';
import 'ics.dart' show ExamSlot, examSlot;
import 'storage.dart';
import 'timetable_diff.dart';
import 'timetable_logic.dart' show schoolInstant;

/// Where change alerts go. [NotificationService] implements this; tests
/// use a recorder.
abstract class EduAlerts {
  Future<void> timetableUpdated(String body);
  Future<void> gradesUpdated(String body);
}

const kChangeLogLimit = 20;

/// Reads the stored change log (newest first). Damaged entries are skipped.
List<TimetableDiff> readChangeLog(Storage storage, String accountId) {
  final raw = storage.timetableChangeLog(accountId);
  if (raw == null) return const [];
  try {
    return [
      for (final e in jsonDecode(raw) as List)
        if (_tryDiff(e) case final d?) d,
    ];
  } catch (_) {
    return const [];
  }
}

TimetableDiff? _tryDiff(Object? e) {
  try {
    return TimetableDiff.fromJson(e as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
}

class EduSyncCore {
  EduSyncCore(this.storage, this.alerts);
  final Storage storage;
  final EduAlerts alerts;

  /// Compares [fresh] with the cached copy of its term; records and
  /// announces a non-empty diff. Call before writing [fresh] to the cache.
  Future<TimetableDiff?> recordTimetable(
    String accountId,
    TermTimetable fresh, {
    DateTime? now,
  }) async {
    final old = TermTimetable.decode(
      storage.eduTimetable(accountId, fresh.term.code),
    );
    if (old == null || old.term.code != fresh.term.code) return null;
    final diff = diffTimetables(
      old,
      fresh,
      at: (now ?? DateTime.now()).toUtc(),
    );
    if (diff.isEmpty) return null;
    final log = [diff, ...readChangeLog(storage, accountId)];
    await storage.setTimetableChangeLog(
      accountId,
      jsonEncode([for (final d in log.take(kChangeLogLimit)) d.toJson()]),
    );
    if (storage.timetableChangeAlerts()) {
      try {
        await alerts.timetableUpdated(diff.summary());
      } catch (_) {
        // Alerts are best-effort; the log is already saved.
      }
    }
    return diff;
  }

  /// Compares [fresh] with the cached grade book and announces new grades.
  /// Call before writing [fresh] to the cache.
  Future<GradeDiff?> recordGrades(String accountId, GradeBook fresh) async {
    final old = GradeBook.decode(storage.eduGrades(accountId));
    if (old == null) return null;
    final diff = newGrades(old, fresh);
    if (diff.isEmpty) return null;
    if (storage.gradeAlerts()) {
      try {
        await alerts.gradesUpdated(diff.summary());
      } catch (_) {}
    }
    return diff;
  }

  /// The whole refresh for one identity, for the background task: current
  /// term → timetable → grades → exams, each diffed, cached and announced.
  /// Grade/exam failures do not undo a stored timetable. Throws when the
  /// timetable itself cannot be fetched.
  Future<EduRefreshResult> refresh(
    String accountId,
    EhallService ehall, {
    DateTime? now,
  }) async {
    final at = (now ?? DateTime.now()).toUtc();
    final term = await ehall.currentTerm();
    final fresh = await ehall.timetable(term);
    final tDiff = await recordTimetable(accountId, fresh, now: at);
    await storage.setEduTimetable(accountId, term.code, fresh.encode());
    await storage.setEduCurrentTerm(accountId, jsonEncode(term.toJson()));
    await storage.setEduLastSync(accountId, at);

    GradeDiff? gDiff;
    try {
      final book = await ehall.grades();
      gDiff = await recordGrades(accountId, book);
      await storage.setEduGrades(accountId, book.encode());
    } catch (_) {}

    List<ExamEntry>? exams;
    try {
      exams = await ehall.exams(term);
      await storage.setEduExams(
        accountId,
        term.code,
        jsonEncode([for (final e in exams) e.toJson()]),
      );
    } catch (_) {}

    return EduRefreshResult(
      timetable: fresh,
      timetableDiff: tDiff,
      gradeDiff: gDiff,
      exams: exams,
    );
  }
}

class EduRefreshResult {
  const EduRefreshResult({
    required this.timetable,
    this.timetableDiff,
    this.gradeDiff,
    this.exams,
  });
  final TermTimetable timetable;
  final TimetableDiff? timetableDiff;
  final GradeDiff? gradeDiff;
  final List<ExamEntry>? exams;
}

/// Whether a refresh is due: [hours] 0 = never.
bool refreshDue(DateTime? lastSync, int hours, DateTime now) {
  if (hours <= 0) return false;
  if (lastSync == null) return true;
  // A little slack so a 12 h periodic task that wakes at 11h58m still runs.
  return now.difference(lastSync) >= Duration(hours: hours, minutes: -10);
}

/// Cached exams of one term (empty on missing or damaged cache).
List<ExamEntry> cachedExams(Storage storage, String accountId, String term) {
  final raw = storage.eduExams(accountId, term);
  if (raw == null) return const [];
  try {
    return [
      for (final e in jsonDecode(raw) as List)
        ExamEntry.fromJson(e as Map<String, dynamic>),
    ];
  } catch (_) {
    return const [];
  }
}

// ---------------------------------------------------------------------------
// Exam reminders
// ---------------------------------------------------------------------------

class ExamReminderPlan {
  const ExamReminderPlan({
    required this.id,
    required this.at,
    required this.slot,
    required this.title,
    required this.body,
  });
  final int id;
  final DateTime at;
  final ExamSlot slot;
  final String title;
  final String body;
}

/// Two reminders per exam that [examSlot] can date: 20:00 CST the evening
/// before, and one hour before the start. Only future instants within
/// [days] of [now] are returned. Ids live in the reminder range (≥ 2^30).
List<ExamReminderPlan> planExamReminders(
  List<ExamEntry> exams,
  DateTime now, {
  int days = 14,
}) {
  final horizon = now.add(Duration(days: days));
  final out = <ExamReminderPlan>[];
  for (final e in exams) {
    final slot = examSlot(e);
    if (slot == null || !slot.start.isAfter(now)) continue;
    final name = e.kind.isEmpty ? e.courseName : '${e.courseName}（${e.kind}）';
    final hhmm = _hhmm(slot.start);
    final where = [
      if (e.room.isNotEmpty) e.room,
      if (e.seat.isNotEmpty) '座位 ${e.seat}',
    ].join(' · ');
    final evening = schoolInstant(
      slot.date.subtract(const Duration(days: 1)),
      20 * 60,
    );
    final candidates = [
      (
        tag: 'eve',
        at: evening,
        title: '明天考试：$name',
        body: [_md(slot.start), hhmm, if (where.isNotEmpty) where].join(' '),
      ),
      (
        tag: '1h',
        at: slot.start.subtract(const Duration(hours: 1)),
        title: '1 小时后考试：$name',
        body: [hhmm, if (where.isNotEmpty) where].join(' '),
      ),
    ];
    for (final c in candidates) {
      if (!c.at.isAfter(now) || c.at.isAfter(horizon)) continue;
      out.add(
        ExamReminderPlan(
          id: examReminderId(e, slot, c.tag),
          at: c.at,
          slot: slot,
          title: c.title,
          body: c.body,
        ),
      );
    }
  }
  out.sort((a, b) => a.at.compareTo(b.at));
  return out;
}

int examReminderId(ExamEntry e, ExamSlot slot, String tag) {
  var hash = 0x811c9dc5;
  final s =
      'exam:${e.courseName}:${e.kind}:${slot.start.toIso8601String()}:$tag';
  for (final unit in s.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0x3fffffff;
  }
  return (1 << 30) | hash;
}

String _two(int v) => v.toString().padLeft(2, '0');
String _hhmm(DateTime utc) {
  final l = utc.toUtc().add(const Duration(hours: 8));
  return '${_two(l.hour)}:${_two(l.minute)}';
}

String _md(DateTime utc) {
  final l = utc.toUtc().add(const Duration(hours: 8));
  return '${l.month}月${l.day}日';
}
