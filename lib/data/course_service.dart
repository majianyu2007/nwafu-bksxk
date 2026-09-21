/// Course querying: paged list retrieval, selected courses, capacity refresh,
/// and the test-course lookup needed to resolve experiment classes before a grab.
library;

import '../core/constants.dart';
import '../core/errors.dart';
import 'api_client.dart';
import 'models.dart';
import 'param_builders.dart';

class CourseService {
  CourseService(this._client);

  final ApiClient _client;

  /// Fetches a full course list for [kind], big-page-first with pagination
  /// fallback (per docs/api.notes.md 分页与完整列表).
  ///
  /// Summary kinds (programCourse/recommendedCourse/publicCourse) return course
  /// rows with tcList; publicCourse and queryCourse return flat teaching-class
  /// rows, wrapped as single-class CourseRows and grouped per course.
  Future<List<CourseRow>> fetchCourses({
    required CourseKind kind,
    required String studentCode,
    required String campus,
    required String batchCode,
    String queryContent = '',
    int firstPageSize = 1000,
    int maxPages = 50,
  }) async {
    final rows = <CourseRow>[];
    var pageNumber = 0;
    var total = -1;

    while (pageNumber < maxPages) {
      final form = buildCourseQuery(
        studentCode: studentCode,
        campus: campus,
        electiveBatchCode: batchCode,
        kind: kind,
        queryContent: queryContent,
        pageSize: firstPageSize,
        pageNumber: pageNumber,
      );
      final res = await _client.postForm(kind.endpoint, form);
      if (!res.ok) {
        // A closed category answers code 0 with a precise reason, e.g.
        // "查询结果:通识类选修课选课未开放"; show that rather than an empty list.
        if (pageNumber == 0 && res.msg.isNotEmpty) {
          throw AppError.fromBusiness(res.code, res.msg);
        }
        break;
      }
      total = res.totalCount;
      final pageRows = res.dataList
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
      if (pageRows.isEmpty) break;

      for (final row in pageRows) {
        rows.add(_asCourseRow(kind, row));
      }
      if (rows.length >= total) break;
      pageNumber++;
    }
    return groupFlatRows(rows);
  }

  /// One bounded server page of whole-school teaching-class records.
  /// Keep these ungrouped: totalCount and page offsets count classes, not
  /// courses. Grouping before persistence would lose all but the first raw row.
  Future<({List<CourseRow> rows, int totalCount})> fetchCatalogPage({
    required String studentCode,
    required String campus,
    required String batchCode,
    String queryContent = '',
    int pageSize = 20,
    int pageNumber = 0,
  }) async {
    final form = buildCourseQuery(
      studentCode: studentCode,
      campus: campus,
      electiveBatchCode: batchCode,
      kind: CourseKind.qxkc,
      queryContent: queryContent,
      pageSize: pageSize,
      pageNumber: pageNumber,
    );
    final res = await _client.postForm(CourseKind.qxkc.endpoint, form);
    if (!res.ok) {
      throw AppError.fromBusiness(
          res.code, res.msg.isEmpty ? '全校课程目录暂时无法读取，请稍后重试' : res.msg);
    }
    return (
      rows: catalogRowsFromJson(res.dataList
          .whereType<Map>()
          .map((row) => row.cast<String, dynamic>())),
      totalCount: res.totalCount,
    );
  }

  static List<CourseRow> catalogRowsFromJson(
          Iterable<Map<String, dynamic>> rows) =>
      [for (final row in rows) _asCourseRow(CourseKind.qxkc, row)];

  /// Some endpoints return course rows with a `tcList`; others (publicCourse
  /// for XGXK, queryCourse for QXKC) return one flat row per teaching class.
  /// Flat rows are wrapped as single-class courses here and merged per course
  /// number by [groupFlatRows] afterwards.
  static CourseRow _asCourseRow(CourseKind kind, Map<String, dynamic> row) {
    final flat = !row.containsKey('tcList') && row['teachingClassID'] != null;
    if (flat) {
      final tc = TeachingClass.fromJson(row);
      return CourseRow(
        courseNumber: tc.courseNumber,
        courseName: tc.courseName,
        credit: (row['credit'] ?? '').toString(),
        courseNatureName: (row['courseNatureName'] ?? '').toString(),
        departmentName: (row['departmentName'] ?? '').toString(),
        number: 1,
        selected: tc.isHeld,
        teachingClasses: [tc],
        raw: row,
      );
    }
    return CourseRow.fromJson(row);
  }

  /// Merges consecutive single-class rows that share a course number into one
  /// course with all its classes (the official page shows flat lists, but a
  /// course-per-card view needs them grouped). Rows that already carry a
  /// tcList pass through untouched; order of first appearance is kept.
  static List<CourseRow> groupFlatRows(List<CourseRow> rows) {
    final out = <CourseRow>[];
    final index = <String, int>{};
    for (final row in rows) {
      final isFlat = row.number == 1 &&
          row.teachingClasses.length == 1 &&
          !row.raw.containsKey('tcList');
      final key = row.courseNumber;
      if (!isFlat || key.isEmpty) {
        out.add(row);
        continue;
      }
      final at = index[key];
      if (at == null) {
        index[key] = out.length;
        out.add(row);
        continue;
      }
      final prev = out[at];
      final classes = [...prev.teachingClasses, ...row.teachingClasses];
      out[at] = CourseRow(
        courseNumber: prev.courseNumber,
        courseName: prev.courseName,
        credit: prev.credit,
        courseNatureName: prev.courseNatureName,
        departmentName: prev.departmentName,
        number: classes.length,
        selected: prev.selected || row.selected,
        teachingClasses: classes,
        raw: prev.raw,
      );
    }
    return out;
  }

  /// The student's currently-selected courses (with drop metadata).
  ///
  /// 正选 rounds answer on courseResult.do. 预选 rounds return nothing there;
  /// the filed volunteers live on volunteerResult.do (course rows with a
  /// tcList, experiment classes flagged isTest) and publicCourseResult.do
  /// (flat 通识 rows), which the official selectedvolunteer page reads both of.
  Future<List<TeachingClass>> fetchSelected({
    required String studentCode,
    required String batchCode,
    bool volunteerRound = false,
  }) async {
    final query = buildSelectedCourseParam(
        studentCode: studentCode, electiveBatchCode: batchCode);
    if (!volunteerRound) {
      final res = await _client.getJson(Api.courseResult, query: query);
      if (!res.ok) return [];
      return _classesOf(res.dataList);
    }
    final results = await Future.wait([
      _client.getJson(Api.volunteerResult, query: query),
      _client.getJson(Api.publicCourseResult, query: query),
    ]);
    final out = <TeachingClass>[];
    final seen = <String>{};
    for (final res in results) {
      if (!res.ok) continue;
      for (final tc in _classesOf(res.dataList)) {
        if (tc.isTestClass) continue;
        if (seen.add(tc.teachingClassId)) out.add(tc);
      }
    }
    return out;
  }

  /// Flattens rows that are either teaching classes or courses with tcList.
  static List<TeachingClass> _classesOf(List<dynamic> rows) {
    final out = <TeachingClass>[];
    for (final row in rows.whereType<Map>()) {
      final m = row.cast<String, dynamic>();
      final tcs = m['tcList'];
      if (tcs is List) {
        for (final t in tcs.whereType<Map>()) {
          // Carry course-level names down so a class row reads like the others.
          final tm = t.cast<String, dynamic>();
          out.add(TeachingClass.fromJson({
            'courseName': m['courseName'],
            'courseNumber': m['courseNumber'],
            'courseNatureName': m['courseNatureName'],
            'departmentName': m['departmentName'],
            'credit': m['credit'],
            ...tm,
          }));
        }
      } else {
        out.add(TeachingClass.fromJson(m));
      }
    }
    return out;
  }

  /// Refreshes live capacity for one teaching class. Returns the updated class,
  /// or the input unchanged if the server had nothing new.
  ///
  /// capacitySuffix is an empty string on this deployment (the official page
  /// still sends it, empty), so it is never a reason to skip the poll; only a
  /// missing class id is. The sparse payload is overlaid by
  /// [TeachingClass.mergeCapacity] so no field is blanked by a null.
  Future<TeachingClass> refreshCapacity(
      TeachingClass tc, String studentCode) async {
    if (tc.teachingClassId.isEmpty) return tc;
    final res = await _client.getJson(
      Api.capacity,
      query: buildCapacityQuery(
        teachingClassId: tc.teachingClassId,
        studentCode: studentCode,
        capacitySuffix: tc.capacitySuffix,
        timestamp: ApiClient.nowStamp(),
      ),
    );
    if (!res.ok || res.data is! Map) return tc;
    return tc.mergeCapacity((res.data as Map).cast<String, dynamic>());
  }

  /// Looks up experiment/test classes for a class that has hasTest==1.
  /// Returns the raw map list; the UI presents them for selection.
  Future<List<Map<String, dynamic>>> fetchTestCourses({
    required TeachingClass tc,
    required String studentCode,
    required String batchCode,
    required String campus,
    required CourseKind kind,
  }) async {
    final res = await _client.postForm(Api.testCourse, {
      'jxbid': tc.teachingClassId,
      'electiveBatchCode': batchCode,
      'studentCode': studentCode,
      'isMajor': kind.isMajor,
      'teachingClassType': kind.code,
      'campus': campus,
      'checkCapacity': '0',
      'checkConflict': '0',
    });
    if (!res.ok) return [];
    return res.dataList
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  /// Volunteer grades this course still accepts for the student (预选 rounds,
  /// course/volunteer.do). Empty means 志愿已满 on the official page.
  Future<List<VolunteerGrade>> fetchCourseVolunteerGrades({
    required TeachingClass tc,
    required String studentCode,
    required String batchCode,
    required CourseKind kind,
  }) async {
    final res = await _client.getJson(
      Api.courseVolunteer,
      query: buildCourseVolunteerParam(
        studentCode: studentCode,
        electiveBatchCode: batchCode,
        courseNumber: tc.courseNumber,
        teachingClassType: kind.code,
        teachingClassId: tc.teachingClassId,
      ),
    );
    if (!res.ok) return const [];
    return res.dataList
        .whereType<Map>()
        .map((e) => VolunteerGrade.fromJson(e.cast<String, dynamic>()))
        .where((g) => g.grade.isNotEmpty)
        .toList();
  }

  // ---- Schedule (teachingTime / noArranged) ----

  /// Fetches the student's arranged schedule (teachingTime.do) for [batchCode].
  /// Rows are teaching-class-shaped; see [ScheduleEntry].
  Future<List<ScheduleEntry>> fetchSchedule({
    required String studentCode,
    required String batchCode,
  }) async {
    final res = await _client.getJson(
      Api.teachingTime,
      query: buildScheduleQuery(
        studentCode: studentCode,
        electiveBatchCode: batchCode,
        timestamp: ApiClient.nowStamp(),
      ),
    );
    if (!res.ok) return [];
    return res.dataList
        .whereType<Map>()
        .map((e) => ScheduleEntry.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  /// Fetches courses whose time/place has not been arranged yet
  /// (noArranged.do). Pairs with [fetchSchedule] for the full "我的课表".
  Future<List<ScheduleEntry>> fetchUnarranged({
    required String studentCode,
    required String batchCode,
  }) async {
    final res = await _client.getJson(
      Api.noArranged,
      query: buildScheduleQuery(
        studentCode: studentCode,
        electiveBatchCode: batchCode,
        timestamp: ApiClient.nowStamp(),
      ),
    );
    if (!res.ok) return [];
    return res.dataList
        .whereType<Map>()
        .map((e) => ScheduleEntry.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  // ---- Selection records ----

  /// Drop log (returnResults.do): who dropped which class, when, from which IP.
  Future<List<DropLogEntry>> fetchReturnResults({
    required String studentCode,
    required String batchCode,
  }) async {
    final res = await _client.getJson(
      Api.returnResults,
      query: buildReturnResultsQuery(
        studentCode: studentCode,
        electiveBatchCode: batchCode,
        timestamp: ApiClient.nowStamp(),
      ),
    );
    if (!res.ok) return [];
    return res.dataList
        .whereType<Map>()
        .map((e) => DropLogEntry.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  /// Unsuccessful selections (unsuccessful.do, 落选课程). [isRead] false
  /// returns only rows the student has not acknowledged (what the official
  /// grab page pops up after login); true returns the whole list (the
  /// sidebar's 落选课程 panel).
  Future<List<UnsuccessfulEntry>> fetchUnsuccessful({
    required String studentCode,
    required String batchCode,
    bool isRead = false,
  }) async {
    final res = await _client.getJson(
      Api.unsuccessful,
      query: buildUnsuccessfulQuery(
        studentCode: studentCode,
        electiveBatchCode: batchCode,
        isRead: isRead,
      ),
    );
    if (!res.ok) return [];
    return res.dataList
        .whereType<Map>()
        .map((e) => UnsuccessfulEntry.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  /// Acknowledges 落选 rows (submit/unsuccessful.do), exactly what the official
  /// popup's 确认 button posts: the rows' wids joined by commas. After this
  /// the server stops returning them for isRead=0, so the popup is shown once.
  Future<bool> acknowledgeUnsuccessful({
    required String studentCode,
    required List<String> wids,
  }) async {
    if (wids.isEmpty) return true;
    final res = await _client.getJson(
      Api.submitUnsuccessful,
      addTimestamp: false,
      query: buildSubmitUnsuccessfulQuery(studentCode: studentCode, wids: wids),
    );
    return res.ok;
  }

  /// The server's own answer to "can I select this class?" (util/canchoose.do):
  /// a list of reasons such as 通识类选修课选课:可以选课 or 该轮次中没有找到
  /// 教学班信息. The official whole-school list opens this in its 检查 popup.
  Future<List<String>> fetchCanChooseReasons({
    required String studentCode,
    required String teachingClassId,
    required String batchCode,
  }) async {
    final res = await _client.getJson(
      Api.canChoose,
      addTimestamp: false,
      query: buildCanChooseQuery(
        studentCode: studentCode,
        teachingClassId: teachingClassId,
        electiveBatchCode: batchCode,
        timestamp: ApiClient.nowStamp(),
      ),
    );
    if (!res.ok) {
      throw AppError.fromBusiness(res.code, res.msg);
    }
    final data = res.data;
    final list = data is Map ? data['reasonList'] : null;
    if (list is! List) return const [];
    return list.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
  }

  // ---- Live detail (queryjxb / querykcxx) ----

  /// Fetches the full teaching-class detail (queryjxb.do). The locally held
  /// [TeachingClass] already carries most fields; this returns the server's
  /// authoritative row so the detail sheet can show anything the list row
  /// omitted. Returns null when the server has nothing beyond what we have.
  Future<TeachingClass?> fetchTeachingClassDetail({
    required TeachingClass tc,
    required String batchCode,
  }) async {
    final res = await _client.getJson(
      Api.teachingClassDetail,
      query: buildTeachingClassDetailQuery(
        teachingClassId: tc.teachingClassId,
        electiveBatchCode: batchCode,
      ),
    );
    if (!res.ok || res.data is! Map) return null;
    // Overlay so list-row fields (capacity, conflict, selection state) the
    // detail endpoint returns as null survive.
    return tc.mergeDetail((res.data as Map).cast<String, dynamic>());
  }

  /// Fetches course-level detail (querykcxx.do) as the raw map. The shape is
  /// course-level (credit, hours, syllabus URL, department, etc.) and varies
  /// by course kind, so the caller reads fields straight from the map.
  Future<Map<String, dynamic>?> fetchCourseDetail(String courseNumber) async {
    final res = await _client.getJson(
      Api.courseDetail,
      query: buildCourseDetailQuery(courseNumber),
    );
    if (!res.ok || res.data is! Map) return null;
    return (res.data as Map).cast<String, dynamic>();
  }

  /// Fetches the textbook options for a teaching class (queryxsjxbbook.do).
  /// Returns the raw rows; [TextbookOption.fromJson] wraps them.
  Future<List<TextbookOption>> fetchTextbookOptions({
    required String studentCode,
    required String batchCode,
    required String teachingClassId,
  }) async {
    final res = await _client.postForm(
      Api.textbookQuery,
      buildTextbookQuery(
        studentCode: studentCode,
        electiveBatchCode: batchCode,
        teachingClassId: teachingClassId,
      ),
    );
    if (!res.ok) return [];
    return res.dataList
        .whereType<Map>()
        .map((e) => TextbookOption.fromJson(e.cast<String, dynamic>()))
        .where((t) => t.bookCode.isNotEmpty)
        .toList();
  }

  // ---- Textbook (write ops, explicit user action only) ----

  /// Orders the textbooks of a selected class (textbook/addbook.do), what the
  /// official 已选课程 panel's 订购教材 does. Only offered when the round's
  /// canSelectBook is "1" and the row's hasBook is "1".
  Future<ApiResult> orderTextbooks({
    required String studentCode,
    required String batchCode,
    required String teachingClassId,
  }) =>
      _client.postForm(
        Api.textbookAdd,
        buildTextbookOrderParam(
          studentCode: studentCode,
          electiveBatchCode: batchCode,
          teachingClassId: teachingClassId,
        ),
      );

  /// Modifies (czlx "1") or cancels (czlx "0") a class's textbook order
  /// (textbook/modifybook.do) with a jcxx string built by
  /// [buildBookSelection]; the official 退订教材 dialog posts the same.
  Future<ApiResult> modifyTextbooks({
    required String studentCode,
    required String batchCode,
    required String teachingClassId,
    required String jcxx,
    bool cancel = false,
  }) =>
      _client.postForm(
        Api.textbookModify,
        buildTextbookModifyParam(
          studentCode: studentCode,
          electiveBatchCode: batchCode,
          teachingClassId: teachingClassId,
          jcxx: jcxx,
          cancelAll: cancel,
        ),
      );
}
