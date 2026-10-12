/// Data from the school's 金智 EMAP apps on ehall.nwafu.edu.cn: timetable,
/// grades and exams. Field names are the EMAP originals (verified live
/// 2026-10-11); see the parsers below for what each means.
library;

import 'dart:convert';

/// A term, e.g. `2026-2027-1` / 2026-2027学年 秋.
class EduTerm {
  const EduTerm({required this.code, required this.name});
  final String code;
  final String name;

  String get year => code.length >= 9 ? code.substring(0, 9) : code;
  String get half => code.length > 10 ? code.substring(10) : '1';

  /// "2026-2027 秋" → short label for chips.
  String get shortName {
    final m = RegExp(r'(\d{4})-(\d{4})学年\s*(\S+)').firstMatch(name);
    return m == null ? name : '${m[1]}-${m[2].toString().substring(2)} ${m[3]}';
  }

  factory EduTerm.fromRow(Map<String, dynamic> r) {
    final code = (r['DM'] ?? r['XNXQDM'] ?? '').toString();
    if (!RegExp(r'^\d{4}-\d{4}-[1-9]$').hasMatch(code)) {
      throw const FormatException('Invalid academic term');
    }
    return EduTerm(
      code: code,
      name: (r['MC'] ?? r['XNXQDM_DISPLAY'] ?? code).toString(),
    );
  }

  Map<String, dynamic> toJson() => {'code': code, 'name': name};
  factory EduTerm.fromJson(Map<String, dynamic> j) =>
      EduTerm(code: j['code'] as String, name: j['name'] as String);

  @override
  bool operator ==(Object other) => other is EduTerm && other.code == code;
  @override
  int get hashCode => code.hashCode;
}

/// One class period of the bell schedule (节次), e.g. 1: 08:00–08:45.
class ClassPeriod {
  const ClassPeriod({
    required this.index,
    required this.start,
    required this.end,
  });
  final int index;

  /// Minutes after midnight, China Standard Time.
  final int start;
  final int end;

  static int _parse(String hhmm) {
    if (!RegExp(r'^\d{1,2}:\d{2}$').hasMatch(hhmm)) {
      throw const FormatException('Invalid bell time');
    }
    final p = hhmm.split(':').map(int.parse).toList();
    if (p[0] > 23 || p[1] > 59) {
      throw const FormatException('Invalid bell time');
    }
    return p[0] * 60 + p[1];
  }

  static String fmt(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

  String get startLabel => fmt(start);
  String get endLabel => fmt(end);

  factory ClassPeriod.fromRow(Map<String, dynamic> r) {
    final index = int.parse(r['DM'].toString());
    final start = _parse(r['KSSJ'].toString());
    final end = _parse(r['JSSJ'].toString());
    if (index < 1 || end <= start) {
      throw const FormatException('Invalid class period');
    }
    return ClassPeriod(index: index, start: start, end: end);
  }

  Map<String, dynamic> toJson() => {'i': index, 's': start, 'e': end};
  factory ClassPeriod.fromJson(Map<String, dynamic> j) => ClassPeriod(
    index: j['i'] as int,
    start: j['s'] as int,
    end: j['e'] as int,
  );

  /// NWAFU's 冬令作息 (Oct 1 – May 1), periods 1–11 from the school's
  /// published 作息时间表.
  static const nwafuWinter = [
    ClassPeriod(index: 1, start: 480, end: 525), // 8:00-8:45
    ClassPeriod(index: 2, start: 535, end: 580), // 8:55-9:40
    ClassPeriod(index: 3, start: 610, end: 655), // 10:10-10:55
    ClassPeriod(index: 4, start: 665, end: 710), // 11:05-11:50
    ClassPeriod(index: 5, start: 840, end: 885), // 14:00-14:45
    ClassPeriod(index: 6, start: 895, end: 940), // 14:55-15:40
    ClassPeriod(index: 7, start: 960, end: 1005), // 16:00-16:45
    ClassPeriod(index: 8, start: 1015, end: 1060), // 16:55-17:40
    ClassPeriod(index: 9, start: 1140, end: 1185), // 19:00-19:45
    ClassPeriod(index: 10, start: 1190, end: 1235), // 19:50-20:35
    ClassPeriod(index: 11, start: 1240, end: 1285), // 20:40-21:25
  ];

  /// 夏令作息 (May 1 – Oct 1): afternoon and evening shift 30 minutes later.
  static const nwafuSummer = [
    ClassPeriod(index: 1, start: 480, end: 525),
    ClassPeriod(index: 2, start: 535, end: 580),
    ClassPeriod(index: 3, start: 610, end: 655),
    ClassPeriod(index: 4, start: 665, end: 710),
    ClassPeriod(index: 5, start: 870, end: 915), // 14:30-15:15
    ClassPeriod(index: 6, start: 925, end: 970), // 15:25-16:10
    ClassPeriod(index: 7, start: 990, end: 1035), // 16:30-17:15
    ClassPeriod(index: 8, start: 1045, end: 1090), // 17:25-18:10
    ClassPeriod(index: 9, start: 1170, end: 1215), // 19:30-20:15
    ClassPeriod(index: 10, start: 1220, end: 1265), // 20:20-21:05
    ClassPeriod(index: 11, start: 1270, end: 1315), // 21:10-21:55
  ];

  /// Used before the server's table arrives (and in tests).
  static const nwafuDefault = nwafuSummer;
}

enum BellSeason {
  winter('冬令作息'),
  summer('夏令作息');

  const BellSeason(this.label);
  final String label;

  /// The season of a school-calendar [date] (Beijing date at UTC midnight):
  /// summer from May 1 up to Oct 1, winter otherwise.
  static BellSeason of(DateTime date) =>
      date.month >= 5 && date.month < 10 ? summer : winter;

  List<ClassPeriod> get table =>
      this == summer ? ClassPeriod.nwafuSummer : ClassPeriod.nwafuWinter;
}

/// One weekly meeting of a class: a weekday, a period range and the weeks it
/// runs. A course with several meetings has several sessions.
class CourseSession {
  const CourseSession({
    required this.id,
    required this.courseName,
    required this.courseCode,
    required this.classNo,
    required this.weekday,
    required this.startPeriod,
    required this.endPeriod,
    required this.weeks,
    required this.weeksLabel,
    this.room = '',
    this.teacher = '',
    this.campus = '',
    this.credit = 0,
    this.note = '',
    this.category = '',
    this.custom = false,
  });

  /// Stable id (`KBID` + meeting, or a local id for custom entries).
  final String id;
  final String courseName;
  final String courseCode;
  final String classNo;

  /// 1 = Monday … 7 = Sunday.
  final int weekday;
  final int startPeriod;
  final int endPeriod;

  /// Teaching weeks, ascending, 1-based.
  final List<int> weeks;
  final String weeksLabel;
  final String room;
  final String teacher;
  final String campus;
  final double credit;

  /// 调课 notes from the server (`BZ`), e.g. 整体调课新增:第3周…
  final String note;
  final String category;

  /// Added by the user, not synced from the school.
  final bool custom;

  /// `KCM` carries a 【本】 prefix for undergraduate courses; drop it.
  String get displayName => courseName.replaceFirst(RegExp(r'^【[^】]*】'), '');

  bool runsInWeek(int week) => weeks.contains(week);

  /// Parses a 课表 row (`cxxszhxqkb.do`). `SKZC` is a bit string where index
  /// i is week i+1.
  factory CourseSession.fromRow(Map<String, dynamic> r) {
    final bits = (r['SKZC'] ?? '').toString();
    final weeks = <int>[
      for (var i = 0; i < bits.length; i++)
        if (bits[i] == '1') i + 1,
    ];
    double credit = 0;
    final xf = r['XF'];
    if (xf is num) credit = xf.toDouble();
    if (xf is String) credit = double.tryParse(xf) ?? 0;
    final weekday = _int(r['SKXQ']);
    final start = _int(r['KSJC']);
    final end = _int(r['JSJC']);
    if (weekday < 1 ||
        weekday > 7 ||
        start < 1 ||
        end < start ||
        !RegExp(r'^[01]+$').hasMatch(bits) ||
        '${r['KCM'] ?? ''}'.trim().isEmpty) {
      throw const FormatException('Invalid course session');
    }
    return CourseSession(
      id: '${r['KBID'] ?? r['WID'] ?? r['JXBID']}-$weekday-$start-$bits',
      courseName: (r['KCM'] ?? '').toString(),
      courseCode: (r['KCH'] ?? '').toString(),
      classNo: (r['KXH'] ?? '').toString(),
      weekday: weekday,
      startPeriod: start,
      endPeriod: end,
      weeks: weeks,
      weeksLabel: (r['ZCMC'] ?? '').toString(),
      room: (r['JASMC'] ?? '').toString(),
      teacher: (r['SKJS'] ?? '').toString(),
      campus: (r['XXXQMC'] ?? r['XXXQDM_DISPLAY'] ?? '').toString(),
      credit: credit,
      note: (r['BZ'] ?? '').toString(),
      category: (r['KCXZDM_DISPLAY'] ?? r['KCLBDM_DISPLAY'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': courseName,
    'code': courseCode,
    'classNo': classNo,
    'day': weekday,
    'start': startPeriod,
    'end': endPeriod,
    'weeks': weeks,
    'weeksLabel': weeksLabel,
    'room': room,
    'teacher': teacher,
    'campus': campus,
    'credit': credit,
    'note': note,
    'category': category,
    if (custom) 'custom': true,
  };

  factory CourseSession.fromJson(Map<String, dynamic> j) => CourseSession(
    id: j['id'] as String,
    courseName: j['name'] as String,
    courseCode: (j['code'] as String?) ?? '',
    classNo: (j['classNo'] as String?) ?? '',
    weekday: j['day'] as int,
    startPeriod: j['start'] as int,
    endPeriod: j['end'] as int,
    weeks: (j['weeks'] as List).cast<int>(),
    weeksLabel: (j['weeksLabel'] as String?) ?? '',
    room: (j['room'] as String?) ?? '',
    teacher: (j['teacher'] as String?) ?? '',
    campus: (j['campus'] as String?) ?? '',
    credit: ((j['credit'] as num?) ?? 0).toDouble(),
    note: (j['note'] as String?) ?? '',
    category: (j['category'] as String?) ?? '',
    custom: (j['custom'] as bool?) ?? false,
  );
}

/// A course with no fixed slot (实习, 网课, 工程训练…): `xswpkc.do`.
class UnscheduledCourse {
  const UnscheduledCourse({
    required this.name,
    required this.weeksLabel,
    this.teacher = '',
    this.credit = 0,
    this.code = '',
  });
  final String name;
  final String weeksLabel;
  final String teacher;
  final double credit;
  final String code;

  factory UnscheduledCourse.fromRow(Map<String, dynamic> r) =>
      UnscheduledCourse(
        name: (r['KCM'] ?? '').toString(),
        weeksLabel: (r['SKZC'] ?? '').toString(),
        teacher: (r['SKJS'] ?? '').toString(),
        credit: double.tryParse('${r['XF'] ?? ''}') ?? 0,
        code: (r['KCH'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {
    'name': name,
    'weeks': weeksLabel,
    'teacher': teacher,
    'credit': credit,
    'code': code,
  };
  factory UnscheduledCourse.fromJson(Map<String, dynamic> j) =>
      UnscheduledCourse(
        name: j['name'] as String,
        weeksLabel: j['weeks'] as String,
        teacher: (j['teacher'] as String?) ?? '',
        credit: ((j['credit'] as num?) ?? 0).toDouble(),
        code: (j['code'] as String?) ?? '',
      );
}

/// A class move (调课) from `xsdkkc.do`: original slot → new slot.
class ClassAdjustment {
  const ClassAdjustment({
    required this.courseName,
    required this.fromLabel,
    required this.toLabel,
    required this.appliedAt,
  });
  final String courseName;
  final String fromLabel;
  final String toLabel;
  final String appliedAt;

  static const _days = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  static String _slot(
    Object? weeks,
    Object? day,
    Object? s,
    Object? e,
    Object? room,
    Object? teacher,
  ) {
    final d = _int(day);
    return [
      '$weeks',
      if (d >= 1 && d <= 7) _days[d],
      '第$s-$e节',
      if ('${room ?? ''}'.isNotEmpty) '$room',
      if ('${teacher ?? ''}'.isNotEmpty) '$teacher',
    ].join(' ');
  }

  factory ClassAdjustment.fromRow(Map<String, dynamic> r) => ClassAdjustment(
    courseName: (r['KCM'] ?? '').toString(),
    fromLabel: _slot(
      r['ZCMC'],
      r['SKXQ'],
      r['KSJC'],
      r['JSJC'],
      r['JASMC'],
      r['YSKJSXM'],
    ),
    toLabel: _slot(
      r['XZCMC'],
      r['XSKXQ'],
      r['XKSJC'],
      r['XJSJC'],
      r['XJASMC'],
      r['XSKJSXM'],
    ),
    appliedAt: (r['SQSJ'] ?? '').toString(),
  );

  Map<String, dynamic> toJson() => {
    'name': courseName,
    'from': fromLabel,
    'to': toLabel,
    'at': appliedAt,
  };
  factory ClassAdjustment.fromJson(Map<String, dynamic> j) => ClassAdjustment(
    courseName: j['name'] as String,
    fromLabel: j['from'] as String,
    toLabel: j['to'] as String,
    appliedAt: (j['at'] as String?) ?? '',
  );
}

/// Everything the timetable page needs for one term, stored offline.
class TermTimetable {
  TermTimetable({
    required this.term,
    required this.firstMonday,
    required this.weekCount,
    required this.periods,
    required this.sessions,
    this.unscheduled = const [],
    this.adjustments = const [],
    required this.syncedAt,
  });

  final EduTerm term;

  /// The Monday of week 1 (UTC midnight), from the server's `XQKSRQ`.
  final DateTime firstMonday;
  final int weekCount;
  final List<ClassPeriod> periods;
  final List<CourseSession> sessions;
  final List<UnscheduledCourse> unscheduled;
  final List<ClassAdjustment> adjustments;
  final DateTime syncedAt;

  /// Times of period [index]. The school runs a 冬令/夏令 bell schedule
  /// (switching on May 1 and Oct 1, Beijing time) while `jc.do` returns one
  /// fixed table, so periods 1–11 come from the season of [on] (today when
  /// null); later periods fall back to the server's table.
  ClassPeriod? period(int index, {DateTime? on}) {
    for (final p in BellSeason.of(on ?? _today()).table) {
      if (p.index == index) return p;
    }
    for (final p in periods) {
      if (p.index == index) return p;
    }
    return null;
  }

  /// Every period index known for the term, ordered.
  List<int> get periodIndices => {
    for (final p in ClassPeriod.nwafuWinter) p.index,
    for (final p in periods) p.index,
  }.toList()..sort();

  static DateTime _today() {
    final cst = DateTime.now().toUtc().add(const Duration(hours: 8));
    return DateTime.utc(cst.year, cst.month, cst.day);
  }

  TermTimetable copyWith({
    List<CourseSession>? sessions,
    DateTime? firstMonday,
  }) => TermTimetable(
    term: term,
    firstMonday: firstMonday ?? this.firstMonday,
    weekCount: weekCount,
    periods: periods,
    sessions: sessions ?? this.sessions,
    unscheduled: unscheduled,
    adjustments: adjustments,
    syncedAt: syncedAt,
  );

  String encode() => jsonEncode({
    'v': 1,
    'term': term.toJson(),
    'firstMonday': firstMonday.toIso8601String(),
    'weekCount': weekCount,
    'periods': [for (final p in periods) p.toJson()],
    'sessions': [for (final s in sessions) s.toJson()],
    'unscheduled': [for (final u in unscheduled) u.toJson()],
    'adjustments': [for (final a in adjustments) a.toJson()],
    'syncedAt': syncedAt.toIso8601String(),
  });

  static TermTimetable? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final monday = DateTime.parse(j['firstMonday'] as String);
      final count = j['weekCount'] as int;
      if (count < 1 ||
          count > 60 ||
          !monday.isUtc ||
          monday.weekday != DateTime.monday ||
          monday.hour != 0) {
        return null;
      }
      return TermTimetable(
        term: EduTerm.fromJson(j['term'] as Map<String, dynamic>),
        firstMonday: DateTime.parse(j['firstMonday'] as String),
        weekCount: j['weekCount'] as int,
        periods: [
          for (final p in j['periods'] as List)
            ClassPeriod.fromJson(p as Map<String, dynamic>),
        ],
        sessions: [
          for (final s in j['sessions'] as List)
            CourseSession.fromJson(s as Map<String, dynamic>),
        ],
        unscheduled: [
          for (final u in (j['unscheduled'] as List?) ?? const [])
            UnscheduledCourse.fromJson(u as Map<String, dynamic>),
        ],
        adjustments: [
          for (final a in (j['adjustments'] as List?) ?? const [])
            ClassAdjustment.fromJson(a as Map<String, dynamic>),
        ],
        syncedAt: DateTime.parse(j['syncedAt'] as String),
      );
    } catch (_) {
      return null;
    }
  }
}

/// One course grade (`xscjcx.do`).
class GradeRecord {
  const GradeRecord({
    required this.termCode,
    required this.termName,
    required this.courseName,
    required this.courseCode,
    required this.credit,
    required this.scoreText,
    this.score,
    this.gradePoint,
    this.nature = '',
    this.category = '',
    this.examType = '',
    this.attempt = '',
    this.passed = true,
    this.components = const {},
  });

  final String termCode;
  final String termName;
  final String courseName;
  final String courseCode;
  final double credit;

  /// What to show: the numeric score, or a level like 合格 / 优秀.
  final String scoreText;
  final double? score;
  final double? gradePoint;

  /// 课程性质: 必修 / 选修 / 任选.
  final String nature;

  /// 课程类别: 通识类选修课 / 专业教育 …
  final String category;

  /// 考试 / 考查.
  final String examType;

  /// 初修 / 重修 / 补考.
  final String attempt;
  final bool passed;

  /// Component scores (平时, 期中, 期末, 实验) when the school publishes them.
  final Map<String, String> components;

  factory GradeRecord.fromRow(Map<String, dynamic> r) {
    if ('${r['KCM'] ?? r['XSKCM'] ?? ''}'.trim().isEmpty ||
        '${r['XNXQDM'] ?? ''}'.isEmpty) {
      throw const FormatException('Invalid grade record');
    }
    double? numOf(Object? v) =>
        v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
    final level = (r['DJCJMC'] ?? '').toString();
    final score = numOf(r['ZCJ']);
    final comps = <String, String>{};
    void comp(String label, String key) {
      final v = '${r['${key}_DISPLAY'] ?? r[key] ?? ''}'.trim();
      if (v.isNotEmpty && v != 'null') comps[label] = v;
    }

    comp('平时', 'PSCJ');
    comp('期中', 'QZCJ');
    comp('期末', 'QMCJ');
    comp('实验', 'SYCJ');
    comp('实践', 'SJCJ');
    return GradeRecord(
      termCode: (r['XNXQDM'] ?? '').toString(),
      termName: (r['XNXQDM_DISPLAY'] ?? r['XNXQDM'] ?? '').toString(),
      courseName: (r['KCM'] ?? r['XSKCM'] ?? '').toString(),
      courseCode: (r['KCH'] ?? '').toString(),
      credit: numOf(r['XF']) ?? 0,
      scoreText: level.isNotEmpty
          ? level
          : (r['XSZCJMC'] ?? (score == null ? '' : _trim(score))).toString(),
      score: score,
      gradePoint: numOf(r['XFJD']),
      nature: (r['KCXZDM_DISPLAY'] ?? '').toString(),
      category: (r['KCLBDM_DISPLAY'] ?? '').toString(),
      examType: (r['KSLXDM_DISPLAY'] ?? '').toString(),
      attempt: (r['CXCKDM_DISPLAY'] ?? '').toString(),
      passed: r['SFJG'] == null
          ? score != null
                ? score >= 60
                : !const {'不合格', '不及格'}.contains(level)
          : r['SFJG'].toString() != '0',
      components: comps,
    );
  }

  Map<String, dynamic> toJson() => {
    'term': termCode,
    'termName': termName,
    'name': courseName,
    'code': courseCode,
    'credit': credit,
    'text': scoreText,
    'score': score,
    'gp': gradePoint,
    'nature': nature,
    'category': category,
    'exam': examType,
    'attempt': attempt,
    'passed': passed,
    'parts': components,
  };

  factory GradeRecord.fromJson(Map<String, dynamic> j) => GradeRecord(
    termCode: j['term'] as String,
    termName: j['termName'] as String,
    courseName: j['name'] as String,
    courseCode: (j['code'] as String?) ?? '',
    credit: ((j['credit'] as num?) ?? 0).toDouble(),
    scoreText: (j['text'] as String?) ?? '',
    score: (j['score'] as num?)?.toDouble(),
    gradePoint: (j['gp'] as num?)?.toDouble(),
    nature: (j['nature'] as String?) ?? '',
    category: (j['category'] as String?) ?? '',
    examType: (j['exam'] as String?) ?? '',
    attempt: (j['attempt'] as String?) ?? '',
    passed: (j['passed'] as bool?) ?? true,
    components: ((j['parts'] as Map?) ?? const {}).cast<String, String>(),
  );
}

/// GPA and ranking (`cxxscjpm.do`).
class GradeSummary {
  const GradeSummary({
    this.gpa = '',
    this.averageScore = '',
    this.majorRank = '',
    this.classRank = '',
  });

  /// 平均学分绩点, as the school computes it.
  final String gpa;

  /// 学分加权平均成绩 (`XFCJ`).
  final String averageScore;
  final String majorRank;
  final String classRank;

  factory GradeSummary.fromRow(Map<String, dynamic> r) => GradeSummary(
    gpa: (r['GPA'] ?? '').toString(),
    averageScore: (r['XFCJ'] ?? '').toString(),
    majorRank: (r['ZYPM'] ?? '').toString(),
    classRank: (r['BJPM'] ?? '').toString(),
  );

  Map<String, dynamic> toJson() => {
    'gpa': gpa,
    'avg': averageScore,
    'major': majorRank,
    'class': classRank,
  };
  factory GradeSummary.fromJson(Map<String, dynamic> j) => GradeSummary(
    gpa: (j['gpa'] as String?) ?? '',
    averageScore: (j['avg'] as String?) ?? '',
    majorRank: (j['major'] as String?) ?? '',
    classRank: (j['class'] as String?) ?? '',
  );
}

/// All grades plus the summary, stored offline.
class GradeBook {
  GradeBook({
    required this.records,
    required this.summary,
    required this.syncedAt,
  });
  final List<GradeRecord> records;
  final GradeSummary summary;
  final DateTime syncedAt;

  String encode() => jsonEncode({
    'records': [for (final r in records) r.toJson()],
    'summary': summary.toJson(),
    'syncedAt': syncedAt.toIso8601String(),
  });

  static GradeBook? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return GradeBook(
        records: [
          for (final r in j['records'] as List)
            GradeRecord.fromJson(r as Map<String, dynamic>),
        ],
        summary: GradeSummary.fromJson(j['summary'] as Map<String, dynamic>),
        syncedAt: DateTime.parse(j['syncedAt'] as String),
      );
    } catch (_) {
      return null;
    }
  }
}

/// One exam (`cxxsksap.do`). The row shape is the standard EMAP one; this
/// account had no exam rows when the endpoint was checked, so every field
/// is optional and parsing keeps the raw strings.
class ExamEntry {
  const ExamEntry({
    required this.courseName,
    this.date = '',
    this.time = '',
    this.room = '',
    this.seat = '',
    this.kind = '',
  });
  final String courseName;
  final String date;
  final String time;
  final String room;
  final String seat;
  final String kind;

  factory ExamEntry.fromRow(Map<String, dynamic> r) {
    String s(List<String> keys) {
      for (final k in keys) {
        final v = r[k];
        if (v != null && '$v'.trim().isNotEmpty) return '$v'.trim();
      }
      return '';
    }

    final when = s(['KSSJMS', 'KSSJ']);
    if (s(['KCM', 'KCMC']).isEmpty) {
      throw const FormatException('Invalid exam record');
    }
    return ExamEntry(
      courseName: s(['KCM', 'KCMC']),
      date: s(['KSRQ']),
      time: when,
      room: s(['JASMC', 'KSDD', 'JASDM']),
      seat: s(['ZWH']),
      kind: s(['KSMC', 'KSLXDM_DISPLAY', 'KSLX']),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': courseName,
    'date': date,
    'time': time,
    'room': room,
    'seat': seat,
    'kind': kind,
  };
  factory ExamEntry.fromJson(Map<String, dynamic> j) => ExamEntry(
    courseName: j['name'] as String,
    date: (j['date'] as String?) ?? '',
    time: (j['time'] as String?) ?? '',
    room: (j['room'] as String?) ?? '',
    seat: (j['seat'] as String?) ?? '',
    kind: (j['kind'] as String?) ?? '',
  );
}

int _int(Object? v, {int fallback = 0}) =>
    v is int ? v : int.tryParse('${v ?? ''}') ?? fallback;

String _trim(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

/// One free classroom from 空闲教室查询 (`kxjas/cxkxjs.do`).
class FreeRoom {
  const FreeRoom({
    required this.name,
    required this.building,
    required this.campus,
    required this.seats,
    required this.freeTimes,
  });

  factory FreeRoom.fromRow(Map<String, dynamic> r) => FreeRoom(
    name: '${r['JASMC'] ?? ''}'.trim(),
    building: '${r['JXLDM_DISPLAY'] ?? ''}'.trim(),
    campus: '${r['XXXQDM_DISPLAY'] ?? ''}'.trim(),
    seats: r['SKZWS'] is num ? (r['SKZWS'] as num).toInt() : null,
    freeTimes: '${r['KXSJ'] ?? ''}'.trim(),
  );

  final String name;
  final String building;
  final String campus;

  /// 上课座位数, when the school lists it.
  final int? seats;

  /// e.g. `08:00-08:45,08:55-09:40`.
  final String freeTimes;
}

/// Grades as CSV (UTF-8 with BOM so Excel opens the Chinese correctly).
String gradesCsv(List<GradeRecord> records) {
  String cell(Object? v) {
    final s = '${v ?? ''}';
    return s.contains(RegExp(r'[",\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
  }

  String num(double? v) => v == null
      ? ''
      : v == v.roundToDouble()
      ? v.toStringAsFixed(0)
      : '$v';
  final b = StringBuffer('﻿学期,课程名称,课程号,学分,成绩,绩点,课程性质,课程类别,考核方式,修读\r\n');
  for (final r in records) {
    b.write([
      r.termName,
      r.courseName,
      r.courseCode,
      num(r.credit),
      r.scoreText,
      num(r.gradePoint),
      r.nature,
      r.category,
      r.examType,
      r.attempt,
    ].map(cell).join(','));
    b.write('\r\n');
  }
  return b.toString();
}
