/// Domain models mapped from the BKSXK JSON responses.
///
/// Field names follow the runtime field summary in docs/api.runtime.md. The API
/// returns most numeric/boolean values as strings ("1"/"0"), so helpers below
/// normalise them. Unknown/absent fields degrade to sensible defaults rather
/// than throwing — the server's shape varies by batch and course kind.
library;

import 'dart:convert';

import '../core/constants.dart';

/// Reads a value as a trimmed string, treating null as ''.
String _s(dynamic v) => v == null ? '' : v.toString().trim();

/// Drops null entries so a sparse payload overlaid on a fuller row (capacity
/// polls, detail lookups) never blanks fields the sparse one omits.
Map<String, dynamic> _nonNull(Map<String, dynamic> m) => {
      for (final e in m.entries)
        if (e.value != null) e.key: e.value
    };

/// Renders the server's teacher field for display. Whole-school rows and
/// detail lookups return "姓名(职称)|工号|,姓名(职称)|工号|"; list rows return a
/// plain name. The official page keeps the title and drops the id; repeats
/// (one per time slot) collapse to a single entry.
String teacherDisplayName(dynamic v) {
  final s = _s(v);
  if (!s.contains('|')) return s;
  final names = <String>[];
  for (final part in s.split(',')) {
    final name = part.split('|').first.trim();
    if (name.isNotEmpty && !names.contains(name)) names.add(name);
  }
  return names.join('、');
}

/// Reads an int from a string/num field, defaulting to [fallback].
int _i(dynamic v, [int fallback = 0]) {
  if (v == null) return fallback;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString().trim()) ?? fallback;
}

/// True when a "1"/"0" style flag is "1" (also tolerates true/1).
bool _flag(dynamic v) {
  final s = _s(v);
  return s == '1' || s == 'true';
}

/// A selectable course batch (选课轮次). Never hard-code these — always read
/// from the server after login, since visibility depends on account + time.
class ElectiveBatch {
  ElectiveBatch({
    required this.code,
    required this.name,
    required this.batchType,
    required this.canSelect,
    this.beginTime = '',
    this.endTime = '',
    this.tacticCode = '',
    this.noSelectReason = '',
    this.canSelectBook = false,
    this.raw = const {},
  });

  /// electiveBatchCode / xklcdm — the value threaded through nearly every call.
  final String code;
  final String name;
  final String batchType;

  /// Whether this student may select in the round right now. batch.do leaves
  /// this null; the student profile's electiveBatchList carries the real value
  /// (see mergeBatchAvailability in auth_service.dart).
  final bool canSelect;
  final String beginTime;
  final String endTime;
  final String tacticCode;

  /// Why the student may not select in this round, e.g. 不在选课轮次范围内.
  /// Empty when selectable or unknown.
  final String noSelectReason;

  /// Whether textbook ordering is open in this round. The official page only
  /// asks for a textbook decision (and sends needBook) when this is "1".
  final bool canSelectBook;
  final Map<String, dynamic> raw;

  /// 选后不可退 rounds carry tacticCode "02"; the official page disables 退选.
  bool get allowsDrop => tacticCode != '02';

  /// typeCode "01" = 预选 (volunteer ranking, curriculavariable page): every
  /// add carries a chooseVolunteer grade. "02" = 正选/抢课 (grablessons page).
  bool get isVolunteerRound => _s(raw['typeCode']) == '01';
  String get typeName => _s(raw['typeName']);

  /// The official page only shows the round notice (and posts xklcqr.do)
  /// when needConfirm is "1" and the student has not confirmed yet.
  bool get needsNoticeConfirmation =>
      _flag(raw['needConfirm']) && !_flag(raw['isConfirmed']);

  /// Whether the round shows [kind]'s tab (the round's display* flags).
  /// An absent flag counts as visible so an unexpected payload hides nothing.
  bool showsKind(CourseKind kind) {
    final key = switch (kind) {
      CourseKind.tjkc => 'displayTJKC',
      CourseKind.fankc => 'displayFANKC',
      CourseKind.fawkc => 'displayFAWKC',
      CourseKind.xgxk => 'displayXGXK',
      CourseKind.cxkc => 'displayCXKC',
      CourseKind.tykc => 'displayTYKC',
      CourseKind.fxkc => 'displayFX',
      CourseKind.qxkc => 'displayALLKC',
    };
    final v = raw[key];
    return v == null || _flag(v);
  }

  factory ElectiveBatch.fromJson(Map<String, dynamic> j) => ElectiveBatch(
        code: _s(j['electiveBatchCode'] ?? j['code'] ?? j['xklcdm']),
        name: _s(j['name'] ?? j['electiveBatchName'] ?? j['batchName']),
        batchType: _s(j['batchType'] ?? j['electiveBatchType']),
        canSelect: _flag(j['canSelect']),
        beginTime: _s(j['beginTime']),
        endTime: _s(j['endTime']),
        tacticCode: _s(j['tacticCode']),
        noSelectReason: _s(j['noSelectReason']),
        canSelectBook: _flag(j['canSelectBook']),
        raw: j,
      );
}

/// The logged-in student's identity + context needed to build requests.
class StudentInfo {
  StudentInfo({
    required this.studentCode,
    required this.name,
    required this.campus,
    this.collegeName = '',
    this.majorName = '',
    this.grade = '',
    this.schoolClassName = '',
    this.raw = const {},
  });

  final String studentCode;
  final String name;

  /// campus code used in querySetting + addParam. Distinct from campusName.
  final String campus;
  final String collegeName;
  final String majorName;
  final String grade;
  final String schoolClassName;
  final Map<String, dynamic> raw;

  /// Campus display name (campusName), e.g. 北校区.
  String get campusName => _s(raw['campusName']);

  factory StudentInfo.fromJson(Map<String, dynamic> j) => StudentInfo(
        studentCode:
            _s(j['code'] ?? j['studentCode'] ?? j['number'] ?? j['xh']),
        name: _s(j['name'] ?? j['studentName']),
        campus: _s(j['campus'] ?? j['campusCode']),
        collegeName: _s(j['collegeName'] ?? j['college']),
        // majorName is null on this deployment; departmentName carries the
        // major (e.g. 软件工程) and is what the official sidebar shows.
        majorName: _s(j['majorName'] ??
            j['major'] ??
            j['majorDirectionName'] ??
            j['departmentName']),
        grade: _s(j['grade']),
        schoolClassName: _s(j['schoolClassName'] ?? j['schoolClass']),
        raw: j,
      );

  /// Returns a copy with any non-null fields from [other] filled in. Used to
  /// merge the richer xkxf.do payload (which carries name/college/major/
  /// grade) into a StudentInfo built from the sparser student/<code>.do data.
  StudentInfo copyWith({
    String? name,
    String? campus,
    String? collegeName,
    String? majorName,
    String? grade,
    String? schoolClassName,
    Map<String, dynamic>? raw,
  }) =>
      StudentInfo(
        studentCode: studentCode,
        name: name ?? this.name,
        campus: campus ?? this.campus,
        collegeName: collegeName ?? this.collegeName,
        majorName: majorName ?? this.majorName,
        grade: grade ?? this.grade,
        schoolClassName: schoolClassName ?? this.schoolClassName,
        raw: raw == null ? this.raw : {...this.raw, ...raw},
      );

  /// Fills blanks from a [CreditInfo] payload. The credit-info endpoint
  /// (student/xkxf.do) returns name/college/major/grade/campus that the
  /// student/<code>.do profile omits, so we merge by best-effort.
  StudentInfo mergeFromCredit(CreditInfo c) => copyWith(
        name: name.isEmpty ? c.raw['name']?.toString() : null,
        campus: campus.isEmpty ? (c.raw['campus']?.toString()) : null,
        collegeName: collegeName.isEmpty ? c.collegeName : null,
        majorName: majorName.isEmpty ? c.majorName : null,
        grade: grade.isEmpty ? c.grade : null,
        schoolClassName: schoolClassName.isEmpty ? c.schoolClassName : null,
        raw: c.raw,
      );
}

/// A course summary row (from programCourse/recommendedCourse/publicCourse).
/// Its teaching classes live in [teachingClasses] (the response `tcList`).
class CourseRow {
  CourseRow({
    required this.courseNumber,
    required this.courseName,
    required this.credit,
    required this.courseNatureName,
    required this.departmentName,
    required this.number,
    required this.selected,
    required this.teachingClasses,
    this.raw = const {},
  });

  final String courseNumber;
  final String courseName;
  final String credit;
  final String courseNatureName;
  final String departmentName;

  /// Count of teaching classes reported by the server.
  final int number;

  /// Whether the student has already selected within this course.
  final bool selected;
  final List<TeachingClass> teachingClasses;
  final Map<String, dynamic> raw;

  /// 通识类别 (publicCourseTypeName), e.g. 学科前沿与科技创新-2025版; '' when
  /// the category has none. Read from the row or its first class.
  String get publicCourseType {
    final own = _s(raw['publicCourseTypeName']);
    if (own.isNotEmpty) return own;
    for (final tc in teachingClasses) {
      final v = _s(tc.raw['publicCourseTypeName']);
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  factory CourseRow.fromJson(Map<String, dynamic> j) {
    final tc = (j['tcList'] as List?) ?? const [];
    return CourseRow(
      courseNumber: _s(j['courseNumber']),
      courseName: _s(j['courseName']),
      credit: _s(j['credit']),
      courseNatureName: _s(j['courseNatureName']),
      departmentName: _s(j['departmentName']),
      number: _i(j['number']),
      selected: _flag(j['selected']),
      teachingClasses: tc
          .whereType<Map>()
          .map((e) => TeachingClass.fromJson(e.cast<String, dynamic>()))
          .toList(),
      raw: j,
    );
  }
}

/// A teaching class (教学班) — the unit you actually select. Carries every flag
/// the grab logic depends on: capacity, conflict, test-class, and textbook.
class TeachingClass {
  TeachingClass({
    required this.teachingClassId,
    required this.courseNumber,
    required this.courseName,
    required this.courseIndex,
    required this.teacherName,
    required this.teachingPlace,
    required this.classCapacity,
    required this.numberOfSelected,
    required this.isFull,
    required this.isConflict,
    required this.conflictDesc,
    required this.isChoose,
    required this.chooseVolunteer,
    required this.hasTest,
    required this.testTeachingClassId,
    required this.hasBook,
    required this.needOrderBook,
    required this.needBook,
    required this.capacitySuffix,
    required this.campus,
    required this.electiveBatchCode,
    required this.engpName,
    this.raw = const {},
  });

  final String teachingClassId;
  final String courseNumber;
  final String courseName;
  final String courseIndex;
  final String teacherName;
  final String teachingPlace;

  final int classCapacity;
  final int numberOfSelected;

  /// True when the server marks the class full. We also treat
  /// numberOfSelected >= classCapacity as full defensively (see [remaining]).
  final bool isFull;

  final bool isConflict;
  final String conflictDesc;

  /// Whether the student currently holds this class.
  final bool isChoose;
  final String chooseVolunteer;

  /// hasTest == "1": must resolve a test/experiment class before submitting.
  final bool hasTest;
  final String testTeachingClassId;

  /// hasBook == "1" with textbook ordering open: must supply needBook.
  final bool hasBook;
  final bool needOrderBook;

  /// The raw needBook flag/string from the row (not the submission string).
  final String needBook;

  /// Suffix param required by the capacity-refresh endpoint.
  final String capacitySuffix;
  final String campus;
  final String electiveBatchCode;

  /// Group/direction label (e.g. English/PE track).
  final String engpName;
  final Map<String, dynamic> raw;

  /// Remaining seats, clamped at 0. Uses both the flag and the counts because
  /// some rows report isFull late.
  int get remaining {
    final byCount = classCapacity - numberOfSelected;
    final r = byCount < 0 ? 0 : byCount;
    return isFull ? 0 : r;
  }

  /// True when there is at least one open seat and no conflict blocking us.
  bool get isGrabbable => remaining > 0 && !isConflict;

  /// 预选 rounds: how many students already listed this class as their first
  /// choice. The official page shows "已报第一志愿 N 人" and marks the class
  /// 人数已满 once it reaches the capacity.
  int get firstVolunteers => _i(raw['numberOfFirstVolunteer']);

  /// The volunteer grade this student currently holds on the class ("1" =
  /// 第一志愿), '' when not selected in a 预选 round.
  String get heldVolunteerGrade => chooseVolunteer;

  /// Whether the server gave us any capacity figures at all. Whole-school
  /// (QXKC) rows carry null capacity/selected, so "0/0" there means unknown,
  /// not full.
  bool get hasCapacityInfo =>
      raw['classCapacity'] != null || raw['numberOfSelected'] != null;

  /// courseResult.do rows say whether this selection may be dropped in the
  /// current round; absent means the server did not say (allow).
  bool get canDelete => raw['canDelete'] == null || _flag(raw['canDelete']);

  /// Teacher names with titles from the detail lookup's teacherNameList
  /// ("武春芳(副教授)|2008117206|"), or '' when unavailable.
  String get teacherWithTitle => teacherDisplayName(raw['teacherNameList']);

  /// Classes the teaching class is recommended for (recommendSchoolClass).
  String get recommendSchoolClass => _s(raw['recommendSchoolClass']);

  /// Overlays a capacity.do payload. That endpoint returns a class-shaped
  /// object with nearly every field null except the counts, and never sets
  /// isFull, so: keep every field the payload leaves null, take the counts,
  /// and derive fullness from them the way the official page does.
  TeachingClass mergeCapacity(Map<String, dynamic> data) {
    final fresh = _nonNull(data);
    if (fresh.isEmpty) return this;
    final capacity = fresh.containsKey('classCapacity')
        ? _i(fresh['classCapacity'], classCapacity)
        : classCapacity;
    final selected = fresh.containsKey('numberOfSelected')
        ? _i(fresh['numberOfSelected'], numberOfSelected)
        : numberOfSelected;
    final full = fresh.containsKey('isFull')
        ? _flag(fresh['isFull'])
        : (capacity > 0 ? selected >= capacity : isFull);
    return withCapacity(
      classCapacity: capacity,
      numberOfSelected: selected,
      isFull: full,
      raw: {
        ...raw,
        ...fresh,
        'classCapacity': '$capacity',
        'numberOfSelected': '$selected',
        'isFull': full ? '1' : '0',
      },
    );
  }

  /// Overlays a queryjxb.do payload: richer text fields win, but nulls (the
  /// detail endpoint omits capacity, conflict and selection state) never
  /// erase what the list row already knew.
  TeachingClass mergeDetail(Map<String, dynamic> data) =>
      TeachingClass.fromJson({...raw, ..._nonNull(data)});

  // --- Detail-only convenience reads (straight from [raw], no ctor churn) ---

  /// Course credit, e.g. "1.5".
  String get credit => _s(raw['credit']);

  /// Class hours, e.g. "32".
  String get hours => _s(raw['hours']);

  /// Exam time text, when the server provides it.
  String get examTime => _s(raw['examTime']);

  /// Exam type/mode label.
  String get examType => _s(raw['examType']);

  /// Course type name (e.g. 公共必修课).
  String get courseTypeName =>
      _s(raw['courseTypeName'] ?? raw['courseNatureName']);

  /// Teaching method label.
  String get teachingMethod => _s(raw['teachingMethod']);

  /// True when the class is taught (partly) online: the server labels these
  /// 面授讲课+SPOC/MOOC or similar.
  bool get isOnline {
    final m = teachingMethod.toUpperCase();
    return m.contains('MOOC') ||
        m.contains('SPOC') ||
        m.contains('网络') ||
        m.contains('线上');
  }

  /// Term label.
  String get schoolTerm => _s(raw['schoolTerm']);

  /// Selection-limit descriptions (班级/年级/专业限制) from limitKindList.
  ///
  /// Rows carry limitDesc/name on some deployments; here they are null and
  /// only limitType ("1" = allowed) + limitValue (e.g. a grade) are set, so
  /// values are grouped as "允许：2025、2024".
  List<String> get limits {
    final list = raw['limitKindList'];
    if (list is! List) return const [];
    final described = <String>[];
    final allowed = <String>[];
    final denied = <String>[];
    for (final e in list.whereType<Map>()) {
      final desc = _s(e['limitDesc'] ?? e['name']);
      final value = _s(e['limitValue']);
      if (desc.isNotEmpty) {
        described.add(desc);
      } else if (value.isNotEmpty) {
        (_s(e['limitType']) == '1' ? allowed : denied).add(value);
      }
    }
    return [
      ...described,
      if (allowed.isNotEmpty) '允许：${allowed.join('、')}',
      if (denied.isNotEmpty) '不允许：${denied.join('、')}',
    ];
  }

  /// Card title mirroring the site: "[index-track]teacher".
  String get displayTitle {
    final parts = <String>[];
    if (courseIndex.isNotEmpty) parts.add(courseIndex);
    if (engpName.isNotEmpty) parts.add(engpName);
    final prefix = parts.isEmpty ? '' : '[${parts.join('-')}]';
    return '$prefix$teacherName';
  }

  factory TeachingClass.fromJson(Map<String, dynamic> j) => TeachingClass(
        teachingClassId: _s(j['teachingClassID'] ?? j['teachingClassId']),
        courseNumber: _s(j['courseNumber']),
        courseName: _s(j['courseName']),
        courseIndex: _s(j['courseIndex']),
        teacherName: teacherDisplayName(j['teacherName']),
        teachingPlace: _s(j['teachingPlace']),
        classCapacity: _i(j['classCapacity']),
        numberOfSelected: _i(j['numberOfSelected']),
        isFull: _flag(j['isFull']),
        isConflict: _flag(j['isConflict']),
        conflictDesc: _s(j['conflictDesc']),
        isChoose: _flag(j['isChoose']),
        chooseVolunteer: _s(j['chooseVolunteer']),
        hasTest: _flag(j['hasTest']),
        testTeachingClassId:
            _s(j['testTeachingClassID'] ?? j['testTeachingClassId']),
        hasBook: _flag(j['hasBook']),
        needOrderBook: _flag(j['needOrderBook']),
        needBook: _s(j['needBook']),
        capacitySuffix: _s(j['capacitySuffix']),
        campus: _s(j['campus']),
        electiveBatchCode: _s(j['electiveBatchCode']),
        engpName: _s(j['engpName']),
        raw: j,
      );

  /// Returns a copy with refreshed capacity fields (used after a capacity poll).
  TeachingClass withCapacity({
    int? classCapacity,
    int? numberOfSelected,
    bool? isFull,
    Map<String, dynamic>? raw,
  }) =>
      TeachingClass(
        teachingClassId: teachingClassId,
        courseNumber: courseNumber,
        courseName: courseName,
        courseIndex: courseIndex,
        teacherName: teacherName,
        teachingPlace: teachingPlace,
        classCapacity: classCapacity ?? this.classCapacity,
        numberOfSelected: numberOfSelected ?? this.numberOfSelected,
        isFull: isFull ?? this.isFull,
        isConflict: isConflict,
        conflictDesc: conflictDesc,
        isChoose: isChoose,
        chooseVolunteer: chooseVolunteer,
        hasTest: hasTest,
        testTeachingClassId: testTeachingClassId,
        hasBook: hasBook,
        needOrderBook: needOrderBook,
        needBook: needBook,
        capacitySuffix: capacitySuffix,
        campus: campus,
        electiveBatchCode: electiveBatchCode,
        engpName: engpName,
        raw: raw ?? this.raw,
      );
}

/// Normalised envelope for the common `{code,msg,data,dataList,totalCount}` body.
class ApiResult {
  ApiResult({
    required this.code,
    required this.msg,
    required this.data,
    required this.dataList,
    required this.totalCount,
    this.keyExpired = false,
    this.raw = const {},
  });

  /// "1" means success for most business endpoints.
  final String code;
  final String msg;
  final dynamic data;
  final List<dynamic> dataList;
  final int totalCount;

  /// Server flag that the token/session expired — triggers silent re-login.
  final bool keyExpired;
  final Map<String, dynamic> raw;

  bool get ok => code == '1';

  factory ApiResult.fromJson(Map<String, dynamic> j) => ApiResult(
        code: _s(j['code']),
        msg: _s(j['msg']),
        data: j['data'],
        dataList: (j['dataList'] as List?) ?? const [],
        totalCount: _i(j['totalCount']),
        keyExpired: _flag(j['keyExpired']),
        raw: j,
      );
}

// ---- New models for the previously-unwired api-branch endpoints ----

/// A notice/announcement row (publicinfo/notice.do).
class Notice {
  Notice({
    required this.wid,
    required this.title,
    this.publishTime = '',
    this.timeDescription = '',
    this.filename = '',
    this.content = '',
    this.raw = const {},
  });

  final String wid;
  final String title;
  final String publishTime;
  final String timeDescription;
  final String filename;
  final String content;
  final Map<String, dynamic> raw;

  bool get hasAttachment => filename.isNotEmpty;

  factory Notice.fromJson(Map<String, dynamic> j) => Notice(
        wid: _s(j['wid']),
        title: _s(j['title']),
        publishTime: _s(j['publishTime']),
        timeDescription: _s(j['timeDescription']),
        filename: _s(j['filename']),
        content: _s(j['content']),
        raw: j,
      );
}

/// A common-problem entry (publicinfo/problem.do). Same shape as [Notice] plus
/// a serial number for ordered display.
class ProblemEntry {
  ProblemEntry({
    required this.wid,
    required this.title,
    this.serialNumber = '',
    this.publishTime = '',
    this.timeDescription = '',
    this.content = '',
    this.raw = const {},
  });

  final String wid;
  final String title;
  final String serialNumber;
  final String publishTime;
  final String timeDescription;
  final String content;
  final Map<String, dynamic> raw;

  factory ProblemEntry.fromJson(Map<String, dynamic> j) => ProblemEntry(
        wid: _s(j['wid']),
        title: _s(j['title']),
        serialNumber: _s(j['serialNumber']),
        publishTime: _s(j['publishTime']),
        timeDescription: _s(j['timeDescription']),
        content: _s(j['content']),
        raw: j,
      );
}

/// A volunteer-grade dictionary row (publicinfo/volunteer.do). Used to label
/// the `chooseVolunteer` field on a teaching class.
class VolunteerGrade {
  VolunteerGrade({required this.grade, required this.name, this.inUse = true});
  final String grade;
  final String name;
  final bool inUse;

  factory VolunteerGrade.fromJson(Map<String, dynamic> j) => VolunteerGrade(
        grade: _s(j['grade']),
        name: _s(j['name']),
        inUse: _flag(j['isUse']),
      );
}

/// Student selection credit summary (student/xkxf.do `data`).
///
/// The server returns a flat object; we surface the few fields a student
/// actually reads while planning a round. Unknown/absent degrade to '' / 0.
class CreditInfo {
  const CreditInfo({
    this.totalCredit = 0,
    this.getCredit = 0,
    this.needCredit = 0,
    this.limitElective = '',
    this.campusName = '',
    this.collegeName = '',
    this.majorName = '',
    this.grade = '',
    this.schoolClassName = '',
    this.electiveIsOpen = false,
    this.noSelectReason = '',
    this.raw = const {},
  });

  final double totalCredit;
  final double getCredit;
  final double needCredit;
  final String limitElective;
  final String campusName;
  final String collegeName;
  final String majorName;
  final String grade;
  final String schoolClassName;
  final bool electiveIsOpen;
  final String noSelectReason;
  final Map<String, dynamic> raw;

  /// Credits selected in this round. The server's field is named needCredit
  /// but the official page labels it 已选学分 (totalCredit = 总学分, getCredit =
  /// 已获学分); there is no "still needed" figure.
  double get selectedCredit => needCredit;

  factory CreditInfo.fromJson(Map<String, dynamic> j) {
    double toDouble(dynamic v, [double fallback = 0]) {
      if (v is num) return v.toDouble();
      final s = _s(v);
      return double.tryParse(s) ?? fallback;
    }

    return CreditInfo(
      totalCredit: toDouble(j['totalCredit']),
      getCredit: toDouble(j['getCredit']),
      needCredit: toDouble(j['needCredit']),
      limitElective: _s(j['limitElective']),
      campusName: _s(j['campusName']),
      collegeName: _s(j['collegeName']),
      majorName: _s(j['majorName'] ?? j['departmentName']),
      grade: _s(j['grade']),
      schoolClassName: _s(j['schoolClassName']),
      electiveIsOpen: _flag(j['electiveIsOpen']),
      noSelectReason: _s(j['noSelectReason']),
      raw: j,
    );
  }

  /// Empty placeholder used before the first successful load.
  static const empty = CreditInfo();
}

/// A schedule row from teachingTime.do / noArranged.do.
///
/// The response is a list of teaching-class-shaped rows. We keep the raw map
/// and expose the few fields the schedule grid needs.
class ScheduleEntry {
  ScheduleEntry({this.raw = const {}}) {
    _tc = TeachingClass.fromJson(raw);
  }

  final Map<String, dynamic> raw;
  late final TeachingClass _tc;

  String get courseName => _tc.courseName;
  String get courseNumber => _tc.courseNumber;
  String get teacherName => _tc.teacherName;
  String get teachingPlace => _tc.teachingPlace;
  String get credit => _tc.credit;
  String get hours => _tc.hours;
  String get courseIndex => _tc.courseIndex;
  String get examTime => _tc.examTime;
  String get schoolTerm => _tc.schoolTerm;
  String get courseNatureName => _s(raw['courseNatureName']);
  String get courseTypeName => _tc.courseTypeName;
  String get displayTitle => _tc.displayTitle;
  String get teachingClassId => _tc.teachingClassId;

  /// True when this row came from noArranged.do (time/place not yet published).
  bool get isUnarranged => teachingPlace.isEmpty;

  // teachingTime.do returns one row per (class, weekday, week pattern):
  // dayOfWeek "1".."7", beginSection/endSection "1".."11", weekName like
  // "1-3周,6-11周", and `week` as a bit string (index i = week i+1, length
  // varies), with teachingPlace holding only the room.

  /// 1 = Monday … 7 = Sunday; 0 when absent.
  int get dayOfWeek => _i(raw['dayOfWeek']);
  int get beginSection => _i(raw['beginSection']);
  int get endSection => _i(raw['endSection'], beginSection);
  String get weekName => _s(raw['weekName']);
  String get startTime => _s(raw['startTime']);
  String get endTime => _s(raw['endTime']);

  /// Week numbers this slot is taught in, decoded from the `week` bit string.
  List<int> get weeks {
    final bits = _s(raw['week']);
    return [
      for (var i = 0; i < bits.length; i++)
        if (bits[i] == '1') i + 1
    ];
  }

  /// True when the row carries a usable weekday + section span.
  bool get hasSlot => dayOfWeek >= 1 && dayOfWeek <= 7 && beginSection >= 1;

  static const _dayNames = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  /// "周一 第5-6节", or '' without a slot.
  String get slotLabel {
    if (!hasSlot) return '';
    final sections = endSection > beginSection
        ? '第$beginSection-$endSection节'
        : '第$beginSection节';
    return '${_dayNames[dayOfWeek]} $sections';
  }

  factory ScheduleEntry.fromJson(Map<String, dynamic> j) =>
      ScheduleEntry(raw: j);
}

/// A drop-log row from returnResults.do. Carries who/when/ip metadata.
class DropLogEntry {
  DropLogEntry({this.raw = const {}});
  final Map<String, dynamic> raw;

  String get courseName => _s(raw['courseName']);
  String get courseNumber => _s(raw['courseNumber']);
  String get teachingClassId =>
      _s(raw['teachingClassID'] ?? raw['teachingClassId']);
  String get teacherName => teacherDisplayName(raw['teacherName']);
  String get deleteOperateTime => _s(raw['deleteOperateTime']);
  String get deleteOperateTypeName => _s(raw['deleteOperateTypeName']);
  String get deleteOperatePersonName => _s(raw['deleteOperatePersonName']);
  String get operateIP => _s(raw['operateIP']);
  String get selectStatus => _s(raw['selectStatus']);

  factory DropLogEntry.fromJson(Map<String, dynamic> j) => DropLogEntry(raw: j);
}

/// An unsuccessful-selection row from unsuccessful.do.
class UnsuccessfulEntry {
  UnsuccessfulEntry({this.raw = const {}});
  final Map<String, dynamic> raw;

  String get wid => _s(raw['wid']);
  String get courseName => _s(raw['courseName']);
  String get courseNumber => _s(raw['courseNumber']);
  String get teachingClassId =>
      _s(raw['teachingClassID'] ?? raw['teachingClassId']);
  String get teacherName => teacherDisplayName(raw['teacherName']);
  String get reason => _s(raw['reason'] ?? raw['unsuccessfulReason']);

  factory UnsuccessfulEntry.fromJson(Map<String, dynamic> j) =>
      UnsuccessfulEntry(raw: j);
}

/// A queue-position row from queryStudentQueue.do.
class QueueEntry {
  QueueEntry({this.raw = const {}});
  final Map<String, dynamic> raw;

  String get courseName => _s(raw['courseName']);
  String get teachingClassId =>
      _s(raw['teachingClassID'] ?? raw['teachingClassId']);
  String get inQueue => _s(raw['inQuene'] ?? raw['inQueue']);
  String get queueIndex => _s(raw['queueIndex'] ?? raw['queueNo']);

  factory QueueEntry.fromJson(Map<String, dynamic> j) => QueueEntry(raw: j);
}

/// Online-user stats from onlineUsers.do. The server returns a data object
/// whose fields vary by deployment; we surface the common count plus the raw.
class OnlineUserStats {
  const OnlineUserStats({this.count = 0, this.raw = const {}});
  final int count;
  final Map<String, dynamic> raw;

  factory OnlineUserStats.fromJson(Map<String, dynamic> j) {
    // The endpoint usually returns `data` as a map with a numeric field; we
    // scan the most common names and fall back to 0.
    int pick(List<String> keys) {
      for (final k in keys) {
        final v = j[k];
        if (v == null) continue;
        if (v is num) return v.toInt();
        final n = int.tryParse(_s(v));
        if (n != null) return n;
      }
      return 0;
    }

    return OnlineUserStats(
      count:
          pick(['onlineUserCount', 'onlineUsers', 'count', 'number', 'total']),
      raw: j,
    );
  }

  static const empty = OnlineUserStats();
}

/// One textbook option row from textbook/queryxsjxbbook.do.
///
/// The same shape drives both the per-book order/decline decision the user
/// makes before grabbing and the post-grab textbook modification flow.
class TextbookOption {
  TextbookOption({
    required this.bookCode,
    this.bookName = '',
    this.isbn = '',
    this.price = '',
    this.press = '',
    this.author = '',
    this.orderable = true,
    this.reasonCodes = const [],
    this.raw = const {},
  });

  final String bookCode;
  final String bookName;
  final String isbn;
  final String price;
  final String press;
  final String author;

  /// False when the server says ordering is closed for this book.
  final bool orderable;

  /// Decline-reason codes the user may pick when not ordering. Rows carry no
  /// reasons on this deployment; they come from the TJCYY dictionary (see
  /// InfoService.fetchTextbookReasons) and are attached with [copyWith].
  final List<TextbookReason> reasonCodes;
  final Map<String, dynamic> raw;

  /// Already ordered (SFDG == "1").
  bool get ordered => _flag(raw['SFDG']);

  /// The decline reason recorded so far (WDGYY), if any.
  String get declineReasonCode => _s(raw['WDGYY']);

  TextbookOption copyWith({List<TextbookReason>? reasonCodes}) =>
      TextbookOption(
        bookCode: bookCode,
        bookName: bookName,
        isbn: isbn,
        price: price,
        press: press,
        author: author,
        orderable: orderable,
        reasonCodes: reasonCodes ?? this.reasonCodes,
        raw: raw,
      );

  /// queryxsjxbbook.do returns each row as `{"wid": "<JSON string>"}` whose
  /// keys are ZZZ (author), ISBN, WDGYY (decline reason code), SM (title),
  /// JCBH (book code), JXBID (class) and SFDG ("1" when already ordered) —
  /// the official page does JSON.parse(row.wid). Flat rows are accepted too.
  factory TextbookOption.fromJson(Map<String, dynamic> j) {
    var m = j;
    final wid = j['wid'];
    if (wid is String && wid.trimLeft().startsWith('{')) {
      try {
        final parsed = jsonDecode(wid);
        if (parsed is Map) m = {...j, ...parsed.cast<String, dynamic>()};
      } catch (_) {
        // Not JSON after all; fall through to the flat-row keys.
      }
    }
    final packed =
        m['wid'] is String && (m['wid'] as String).trimLeft().startsWith('{');
    final reasons =
        (m['reasonList'] ?? m['reasonCodeList']) as List? ?? const [];
    return TextbookOption(
      bookCode: _s(m['JCBH'] ??
          m['bookCode'] ??
          m['jcbm'] ??
          (packed ? null : m['wid'])),
      bookName: _s(m['SM'] ?? m['bookName'] ?? m['jcmc']),
      isbn: _s(m['ISBN'] ?? m['isbn'] ?? m['jisbn']),
      price: _s(m['DJ'] ?? m['price'] ?? m['dj']),
      press: _s(m['CBS'] ?? m['press'] ?? m['cbs']),
      author: _s(m['ZZZ'] ?? m['author'] ?? m['zz']),
      orderable: !_flag(m['orderClosed'] ?? m['cannotOrder']),
      reasonCodes: reasons
          .whereType<Map>()
          .map((e) => TextbookReason.fromJson(e.cast<String, dynamic>()))
          .toList(),
      raw: m,
    );
  }
}

/// A decline reason for a textbook (resonable default codes per the site).
class TextbookReason {
  TextbookReason({required this.code, required this.name});
  final String code;
  final String name;

  factory TextbookReason.fromJson(Map<String, dynamic> j) => TextbookReason(
      code: _s(j['code'] ?? j['reasonCode']),
      name: _s(j['name'] ?? j['reasonName']));
}
