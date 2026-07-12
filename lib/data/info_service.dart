/// Public-info queries: announcements, common problems, online-user count,
/// selection-credit summary, and the volunteer-grade dictionary.
///
/// These endpoints are read-only and shared across the app — notices on the
/// home page, credit info beside the batch selector, online-user load in
/// diagnostics — so they live in their own service rather than crowding
/// [CourseService].
library;

import '../core/constants.dart';
import 'api_client.dart';
import 'models.dart';
import 'param_builders.dart';

class InfoService {
  InfoService(this._client);

  final ApiClient _client;

  /// Fetches the announcement list (notice.do). Paged by the server; the home
  /// page only wants the first page, so the default [pageSize] is small.
  Future<List<Notice>> fetchNotices({
    int pageSize = 10,
    int pageNumber = 0,
  }) async {
    final res = await _client.getJson(
      Api.noticeList,
      query: buildNoticeListQuery(
        timestamp: ApiClient.nowStamp(),
        pageSize: pageSize,
        pageNumber: pageNumber,
      ),
    );
    if (!res.ok) return [];
    return res.dataList
        .whereType<Map>()
        .map((e) => Notice.fromJson(e.cast<String, dynamic>()))
        .where((n) => n.title.isNotEmpty)
        .toList();
  }

  /// Fetches a single notice by id (notice/view.do). Returns null when the
  /// server has no body for [wid].
  Future<Notice?> fetchNoticeDetail(String wid) async {
    final res = await _client.getJson(
      Api.noticeView,
      query: buildNoticeViewQuery(wid: wid, timestamp: ApiClient.nowStamp()),
    );
    if (!res.ok || res.data is! Map) return null;
    return Notice.fromJson((res.data as Map).cast<String, dynamic>());
  }

  /// Fetches the common-problem list (problem.do).
  Future<List<ProblemEntry>> fetchProblems() async {
    final res = await _client.getJson(
      Api.problemList,
      query: buildProblemListQuery(ApiClient.nowStamp()),
    );
    if (!res.ok) return [];
    return res.dataList
        .whereType<Map>()
        .map((e) => ProblemEntry.fromJson(e.cast<String, dynamic>()))
        .where((p) => p.title.isNotEmpty)
        .toList();
  }

  /// Fetches the volunteer-grade dictionary (publicinfo/volunteer.do). Used to
  /// label the `chooseVolunteer` field on teaching classes.
  Future<List<VolunteerGrade>> fetchVolunteerGrades() async {
    final res = await _client.getJson(
      Api.volunteerGrade,
      query: buildVolunteerGradeQuery(ApiClient.nowStamp()),
    );
    if (!res.ok) return [];
    return res.dataList
        .whereType<Map>()
        .map((e) => VolunteerGrade.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  /// Fetches the current online-user count (onlineUsers.do). Used by the
  /// diagnostics page to explain slowness during a rush.
  Future<OnlineUserStats> fetchOnlineUsers() async {
    final res = await _client.getJson(
      Api.onlineUsers,
      query: buildOnlineUsersQuery(ApiClient.nowStamp()),
    );
    if (!res.ok || res.data is! Map) return OnlineUserStats.empty;
    return OnlineUserStats.fromJson((res.data as Map).cast<String, dynamic>());
  }

  /// Fetches the student's selection-credit summary (student/xkxf.do).
  ///
  /// [batchType] is the `electiveBatchType` from the active [ElectiveBatch] —
  /// threaded through as `xklclx` per docs/api.notes.md. When the server does
  /// not require it (some deployments) the empty default is sent and the call
  /// still succeeds.
  Future<CreditInfo> fetchCreditInfo({
    required String studentCode,
    required String electiveBatchCode,
    String batchType = '',
  }) async {
    final res = await _client.postForm(
      Api.creditInfo,
      buildCreditInfoParam(
        studentCode: studentCode,
        electiveBatchCode: electiveBatchCode,
        xklclx: batchType,
      ),
    );
    if (!res.ok || res.data is! Map) return CreditInfo.empty;
    return CreditInfo.fromJson((res.data as Map).cast<String, dynamic>());
  }
}