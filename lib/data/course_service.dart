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
}
