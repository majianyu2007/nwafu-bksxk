/// Course querying: paged list retrieval, selected courses, capacity refresh,
/// and the test-course lookup needed to resolve experiment classes before a grab.
library;

import '../core/constants.dart';
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
  /// rows with tcList; QXKC returns flat teaching-class rows wrapped as single-
  /// class CourseRows so the UI can treat them uniformly.
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
    var pageSize = firstPageSize;
    var total = -1;

    while (pageNumber < maxPages) {
      final form = buildCourseQuery(
        studentCode: studentCode,
        campus: campus,
        electiveBatchCode: batchCode,
        kind: kind,
        queryContent: queryContent,
        pageSize: pageSize,
        pageNumber: pageNumber,
      );
      final res = await _client.postForm(kind.endpoint, form);
      if (!res.ok) break;
      total = res.totalCount;
      final pageRows = res.dataList.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
      if (pageRows.isEmpty) break;

      for (final row in pageRows) {
        rows.add(_asCourseRow(kind, row));
      }
      if (rows.length >= total) break;
      // After the first big page, keep the same size and advance.
      pageNumber++;
      pageSize = firstPageSize;
    }
    return rows;
  }

  /// QXKC rows are teaching classes; wrap each as a one-class course row.
  CourseRow _asCourseRow(CourseKind kind, Map<String, dynamic> row) {
    if (kind == CourseKind.qxkc) {
      final tc = TeachingClass.fromJson(row);
      return CourseRow(
        courseNumber: tc.courseNumber,
        courseName: tc.courseName,
        credit: (row['credit'] ?? '').toString(),
        courseNatureName: (row['courseNatureName'] ?? '').toString(),
        departmentName: (row['departmentName'] ?? '').toString(),
        number: 1,
        selected: tc.isChoose,
        teachingClasses: [tc],
        raw: row,
      );
    }
    return CourseRow.fromJson(row);
  }

  /// The student's currently-selected courses (with drop metadata).
  Future<List<TeachingClass>> fetchSelected({
    required String studentCode,
    required String batchCode,
  }) async {
    final res = await _client.getJson(
      Api.courseResult,
      query: buildSelectedCourseParam(studentCode: studentCode, electiveBatchCode: batchCode),
    );
    if (!res.ok) return [];
    return res.dataList
        .whereType<Map>()
        .map((e) => TeachingClass.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  /// Refreshes live capacity for one teaching class. Returns the updated class,
  /// or the input unchanged if the server had nothing new.
  Future<TeachingClass> refreshCapacity(TeachingClass tc, String studentCode) async {
    if (tc.capacitySuffix.isEmpty) return tc;
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
    final data = (res.data as Map).cast<String, dynamic>();
    final fresh = TeachingClass.fromJson({...tc.raw, ...data});
    return fresh;
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
    return res.dataList.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }

  /// Runs the pre-selection eligibility check (canchoose.do).
  Future<ApiResult> canChoose({
    required TeachingClass tc,
    required String studentCode,
    required String batchCode,
  }) {
    return _client.getJson(
      Api.canChoose,
      query: buildCanChooseQuery(
        studentCode: studentCode,
        teachingClassId: tc.teachingClassId,
        electiveBatchCode: batchCode,
        timestamp: ApiClient.nowStamp(),
      ),
    );
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

  /// Unsuccessful selections (unsuccessful.do): courses the student tried to
  /// grab this round but did not get. Pass [isRead] to fetch the unread set.
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

  /// Queue position info (queryStudentQueue.do): where the student sits in the
  /// wait queue for full classes they tried to grab.
  Future<List<QueueEntry>> fetchStudentQueue({
    required String studentCode,
    required String batchCode,
  }) async {
    final res = await _client.getJson(
      Api.studentQueue,
      query: buildStudentQueueQuery(
        studentCode: studentCode,
        electiveBatchCode: batchCode,
      ),
    );
    if (!res.ok) return [];
    return res.dataList
        .whereType<Map>()
        .map((e) => QueueEntry.fromJson(e.cast<String, dynamic>()))
        .toList();
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
    final data = (res.data as Map).cast<String, dynamic>();
    // Merge so we don't lose list-row fields the detail endpoint omits.
    return TeachingClass.fromJson({...tc.raw, ...data});
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
}
