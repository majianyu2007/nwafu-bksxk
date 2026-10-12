/// What changed between two syncs of a timetable or a grade book, for the
/// "课表有变动" / "新成绩" notifications and the stored change log.
library;

import 'edu_models.dart';
import 'timetable_logic.dart' show kWeekdayNames;
import 'week_syntax.dart';

/// One field-level change of a session that exists in both syncs.
class FieldChange {
  const FieldChange({
    required this.field,
    required this.before,
    required this.after,
  });

  /// `room`, `teacher`, `weeks` or `time`.
  final String field;
  final String before;
  final String after;

  String get label => switch (field) {
    'room' => '教室',
    'teacher' => '教师',
    'weeks' => '周次',
    'time' => '时间',
    _ => field,
  };

  Map<String, dynamic> toJson() => {'f': field, 'b': before, 'a': after};
  factory FieldChange.fromJson(Map<String, dynamic> j) => FieldChange(
    field: j['f'] as String,
    before: j['b'] as String,
    after: j['a'] as String,
  );
}

/// A session present in both syncs whose details differ.
class SessionChange {
  const SessionChange({
    required this.before,
    required this.after,
    required this.changes,
  });
  final CourseSession before;
  final CourseSession after;
  final List<FieldChange> changes;

  bool get moved => changes.any((c) => c.field == 'time');

  Map<String, dynamic> toJson() => {
    'before': before.toJson(),
    'after': after.toJson(),
    'changes': [for (final c in changes) c.toJson()],
  };
  factory SessionChange.fromJson(Map<String, dynamic> j) => SessionChange(
    before: CourseSession.fromJson(j['before'] as Map<String, dynamic>),
    after: CourseSession.fromJson(j['after'] as Map<String, dynamic>),
    changes: [
      for (final c in j['changes'] as List)
        FieldChange.fromJson(c as Map<String, dynamic>),
    ],
  );
}

/// `周三 3-4节` (or `周三 3节`).
String slotLabel(CourseSession s) {
  final day = s.weekday >= 1 && s.weekday <= 7
      ? kWeekdayNames[s.weekday - 1]
      : '周?';
  final periods = s.startPeriod == s.endPeriod
      ? '${s.startPeriod}'
      : '${s.startPeriod}-${s.endPeriod}';
  return '$day $periods节';
}

String _weeksText(CourseSession s) =>
    s.weeks.isEmpty ? s.weeksLabel : formatWeeks(s.weeks);

class TimetableDiff {
  TimetableDiff({
    this.added = const [],
    this.removed = const [],
    this.changed = const [],
    DateTime? at,
    this.termCode = '',
  }) : at = at ?? DateTime.now().toUtc();

  final List<CourseSession> added;
  final List<CourseSession> removed;
  final List<SessionChange> changed;

  /// When the change was detected (UTC).
  final DateTime at;
  final String termCode;

  bool get isEmpty => added.isEmpty && removed.isEmpty && changed.isEmpty;
  int get count => added.length + removed.length + changed.length;

  /// One line per change, e.g. `数据结构 周三 3-4节：教室 N8618→N8306`.
  List<String> lines() => [
    for (final c in changed)
      '${c.after.displayName} ${slotLabel(c.before)}：'
          '${c.changes.map((f) => '${f.label} ${f.before}→${f.after}').join('，')}',
    for (final s in added) '新增 ${s.displayName} ${slotLabel(s)}',
    for (final s in removed) '取消 ${s.displayName} ${slotLabel(s)}',
  ];

  /// At most [max] lines joined by `；`, then `等 N 处变动`.
  String summary({int max = 3}) {
    final all = lines();
    if (all.isEmpty) return '课表无变动';
    final shown = all.take(max).join('；');
    return all.length > max ? '$shown；等 ${all.length} 处变动' : shown;
  }

  Map<String, dynamic> toJson() => {
    'at': at.toIso8601String(),
    'term': termCode,
    'added': [for (final s in added) s.toJson()],
    'removed': [for (final s in removed) s.toJson()],
    'changed': [for (final c in changed) c.toJson()],
  };

  factory TimetableDiff.fromJson(Map<String, dynamic> j) => TimetableDiff(
    at: DateTime.parse(j['at'] as String),
    termCode: (j['term'] as String?) ?? '',
    added: [
      for (final s in (j['added'] as List?) ?? const [])
        CourseSession.fromJson(s as Map<String, dynamic>),
    ],
    removed: [
      for (final s in (j['removed'] as List?) ?? const [])
        CourseSession.fromJson(s as Map<String, dynamic>),
    ],
    changed: [
      for (final c in (j['changed'] as List?) ?? const [])
        SessionChange.fromJson(c as Map<String, dynamic>),
    ],
  );
}

String _courseKey(CourseSession s) =>
    '${s.courseCode.isEmpty ? s.courseName : s.courseCode}|${s.classNo}';

String _slotKey(CourseSession s) =>
    '${_courseKey(s)}|${s.weekday}|${s.startPeriod}|${s.endPeriod}';

List<FieldChange> _fieldChanges(CourseSession a, CourseSession b) => [
  if (a.weekday != b.weekday ||
      a.startPeriod != b.startPeriod ||
      a.endPeriod != b.endPeriod)
    FieldChange(field: 'time', before: slotLabel(a), after: slotLabel(b)),
  if (a.room.trim() != b.room.trim())
    FieldChange(field: 'room', before: a.room.trim(), after: b.room.trim()),
  if (a.teacher.trim() != b.teacher.trim())
    FieldChange(
      field: 'teacher',
      before: a.teacher.trim(),
      after: b.teacher.trim(),
    ),
  if (!_sameWeeks(a.weeks, b.weeks))
    FieldChange(field: 'weeks', before: _weeksText(a), after: _weeksText(b)),
];

bool _sameWeeks(List<int> a, List<int> b) {
  final x = a.toSet(), y = b.toSet();
  return x.length == y.length && x.containsAll(y);
}

/// Compares two syncs of one term, ignoring the user's custom sessions.
///
/// Sessions are matched first by course code + class number + weekday +
/// period range (so a room or teacher change is a change, not a remove+add).
/// Leftovers of the same course + class are then paired up as moves, in
/// slot order. What is still unpaired is added or removed.
TimetableDiff diffTimetables(
  TermTimetable old,
  TermTimetable fresh, {
  DateTime? at,
}) {
  int bySlot(CourseSession a, CourseSession b) {
    final d = a.weekday.compareTo(b.weekday);
    if (d != 0) return d;
    final p = a.startPeriod.compareTo(b.startPeriod);
    return p != 0
        ? p
        : (a.weeks.firstOrNull ?? 0).compareTo(b.weeks.firstOrNull ?? 0);
  }

  final before = [
    for (final s in old.sessions)
      if (!s.custom) s,
  ]..sort(bySlot);
  final after = [
    for (final s in fresh.sessions)
      if (!s.custom) s,
  ]..sort(bySlot);

  final changed = <SessionChange>[];
  final leftAfter = <CourseSession>[];
  final pool = <String, List<CourseSession>>{};
  for (final s in before) {
    (pool[_slotKey(s)] ??= []).add(s);
  }

  // Pass 1: same slot. Several sessions in one slot (split week ranges) are
  // paired preferring identical weeks.
  for (final s in after) {
    final list = pool[_slotKey(s)];
    if (list == null || list.isEmpty) {
      leftAfter.add(s);
      continue;
    }
    final i = list.indexWhere((o) => _sameWeeks(o.weeks, s.weeks));
    final o = list.removeAt(i < 0 ? 0 : i);
    final f = _fieldChanges(o, s);
    if (f.isNotEmpty) {
      changed.add(SessionChange(before: o, after: s, changes: f));
    }
  }
  final leftBefore = [for (final l in pool.values) ...l]..sort(bySlot);

  // Pass 2: same course, different slot = moved.
  final added = <CourseSession>[];
  for (final s in leftAfter) {
    final i = leftBefore.indexWhere((o) => _courseKey(o) == _courseKey(s));
    if (i < 0) {
      added.add(s);
      continue;
    }
    final o = leftBefore.removeAt(i);
    changed.add(
      SessionChange(before: o, after: s, changes: _fieldChanges(o, s)),
    );
  }

  changed.sort((a, b) => bySlot(a.before, b.before));
  return TimetableDiff(
    added: added,
    removed: leftBefore,
    changed: changed,
    at: at,
    termCode: fresh.term.code,
  );
}

/// Grades that newly appeared or whose score changed since the last sync.
class GradeDiff {
  const GradeDiff({this.added = const [], this.changed = const []});

  /// Records not in the previous book.
  final List<GradeRecord> added;

  /// Records whose score text or numeric score changed (new values).
  final List<GradeRecord> changed;

  List<GradeRecord> get all => [...added, ...changed];
  bool get isEmpty => added.isEmpty && changed.isEmpty;

  /// `新成绩：高等数学 92、大学英语 85` (at most [max], then `等 N 门`).
  String summary({int max = 3}) {
    final rows = all;
    if (rows.isEmpty) return '';
    final shown = rows
        .take(max)
        .map(
          (r) =>
              '${r.courseName.replaceFirst(RegExp(r'^【[^】]*】'), '')} ${r.scoreText}'
                  .trim(),
        )
        .join('、');
    return '新成绩：$shown${rows.length > max ? ' 等 ${rows.length} 门' : ''}';
  }
}

String _gradeKey(GradeRecord r) =>
    '${r.termCode}|${r.courseCode}|${r.courseName}';

/// Compares [fresh] with [old]. With no previous book every record is
/// "new"; callers that do not want a notification on first sync should
/// skip the call when [old] is null.
GradeDiff newGrades(GradeBook? old, GradeBook fresh) {
  final prev = <String, GradeRecord>{
    for (final r in old?.records ?? const <GradeRecord>[]) _gradeKey(r): r,
  };
  final added = <GradeRecord>[];
  final changed = <GradeRecord>[];
  for (final r in fresh.records) {
    final o = prev[_gradeKey(r)];
    if (o == null) {
      added.add(r);
    } else if (o.scoreText != r.scoreText || o.score != r.score) {
      changed.add(r);
    }
  }
  return GradeDiff(added: added, changed: changed);
}
