/// Domain models mapped from the BKSXK JSON responses.
///
/// Field names follow the runtime field summary in docs/api.runtime.md. The API
/// returns most numeric/boolean values as strings ("1"/"0"), so helpers below
/// normalise them. Unknown/absent fields degrade to sensible defaults rather
/// than throwing — the server's shape varies by batch and course kind.
library;

/// Reads a value as a trimmed string, treating null as ''.
String _s(dynamic v) => v == null ? '' : v.toString().trim();

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
    this.raw = const {},
  });

  /// electiveBatchCode / xklcdm — the value threaded through nearly every call.
  final String code;
  final String name;
  final String batchType;
  final bool canSelect;
  final String beginTime;
  final String endTime;
  final String tacticCode;
  final Map<String, dynamic> raw;

  factory ElectiveBatch.fromJson(Map<String, dynamic> j) => ElectiveBatch(
        code: _s(j['electiveBatchCode'] ?? j['code'] ?? j['xklcdm']),
        name: _s(j['name'] ?? j['electiveBatchName'] ?? j['batchName']),
        batchType: _s(j['batchType'] ?? j['electiveBatchType']),
        canSelect: _flag(j['canSelect']),
        beginTime: _s(j['beginTime']),
        endTime: _s(j['endTime']),
        tacticCode: _s(j['tacticCode']),
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
    this.raw = const {},
  });

  final String studentCode;
  final String name;

  /// campus code used in querySetting + addParam. Distinct from campusName.
  final String campus;
  final String collegeName;
  final String majorName;
  final String grade;
  final Map<String, dynamic> raw;

  factory StudentInfo.fromJson(Map<String, dynamic> j) => StudentInfo(
        studentCode: _s(j['code'] ?? j['studentCode'] ?? j['number'] ?? j['xh']),
        name: _s(j['name'] ?? j['studentName']),
        campus: _s(j['campus'] ?? j['campusCode']),
        collegeName: _s(j['collegeName']),
        majorName: _s(j['majorName']),
        grade: _s(j['grade']),
        raw: j,
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
        teacherName: _s(j['teacherName']),
        teachingPlace: _s(j['teachingPlace']),
        classCapacity: _i(j['classCapacity']),
        numberOfSelected: _i(j['numberOfSelected']),
        isFull: _flag(j['isFull']),
        isConflict: _flag(j['isConflict']),
        conflictDesc: _s(j['conflictDesc']),
        isChoose: _flag(j['isChoose']),
        chooseVolunteer: _s(j['chooseVolunteer']),
        hasTest: _flag(j['hasTest']),
        testTeachingClassId: _s(j['testTeachingClassID'] ?? j['testTeachingClassId']),
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
        raw: raw,
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
