/// Public-info queries: the home-page aggregate (notices, common problems,
/// contact), system parameters, online-user count, the credit summary, the
/// volunteer-grade dictionary and the textbook decline reasons.
///
/// These endpoints are read-only and shared across the app, so they live in
/// their own service rather than crowding [CourseService].
library;

import '../core/constants.dart';
import 'api_client.dart';
import 'models.dart';
import 'param_builders.dart';

class InfoService {
  InfoService(this._client);

  final ApiClient _client;

  /// The home-page aggregate (publicinfo.do): notices, common problems, the
  /// 教务处 contact block and the 停止说明 text, in one call as the official
  /// index page loads them.
  Future<PublicInfo> fetchPublicInfo() async {
    final res = await _client.getJson(
      Api.publicInfo,
      auth: false,
      query: {'pageSize': '10', 'pageNumber': '1'},
    );
    if (!res.ok || res.data is! Map) return PublicInfo.empty;
    return PublicInfo.fromJson((res.data as Map).cast<String, dynamic>());
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

  /// The deployment's system parameters (sysparam.do): tab names and display
  /// switches. Public; the official page loads it right after login.
  Future<SysParams> fetchSysParams() async {
    final res = await _client.getJson(Api.sysParam, auth: false);
    if (!res.ok || res.data is! Map) return SysParams.empty;
    return SysParams.fromJson((res.data as Map).cast<String, dynamic>());
  }

  /// The filter dictionaries (dictionary.do → dictionaryList): XGXKLB (通识
  /// 类别), KKDW (开课单位), KCXZ (课程性质), KCLB (课程类别), TJCYY (教材
  /// 不订购原因). Each is a list of {code, name}.
  Future<Map<String, List<DictEntry>>> fetchDictionary() async {
    final res = await _client.getJson(Api.dictionary, auth: false);
    final data = res.data;
    if (!res.ok || data is! Map) return const {};
    final dict = data['dictionaryList'];
    if (dict is! Map) return const {};
    final out = <String, List<DictEntry>>{};
    for (final e in dict.entries) {
      final list = e.value;
      if (list is! List) continue;
      out[e.key.toString()] = list
          .whereType<Map>()
          .map((m) => DictEntry.fromJson(m.cast<String, dynamic>()))
          .where((d) => d.code.isNotEmpty)
          .toList();
    }
    return out;
  }

  /// Fetches the volunteer-grade dictionary (publicinfo/volunteer.do). Used to
  /// label the `chooseVolunteer` field on teaching classes.
  Future<List<VolunteerGrade>> fetchVolunteerGrades() async {
    final res = await _client.getJson(Api.volunteerGrade);
    if (!res.ok) return [];
    return res.dataList
        .whereType<Map>()
        .map((e) => VolunteerGrade.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  /// Fetches the textbook decline reasons (dictionary.do → TJCYY), e.g.
  /// 01 从高年级借用到正版教材 / 02 从其他途径已购买正版教材.
  Future<List<TextbookReason>> fetchTextbookReasons() async {
    final dict = await fetchDictionary();
    return [
      for (final d in dict['TJCYY'] ?? const <DictEntry>[])
        TextbookReason(code: d.code, name: d.name),
    ];
  }

  /// Fetches the current online-user count (onlineUsers.do). The official
  /// index page shows it next to the login box.
  Future<OnlineUserStats> fetchOnlineUsers() async {
    final res = await _client.getJson(Api.onlineUsers, auth: false);
    if (!res.ok || res.data is! Map) return OnlineUserStats.empty;
    return OnlineUserStats.fromJson((res.data as Map).cast<String, dynamic>());
  }

  /// Fetches the student's selection-credit summary (student/xkxf.do).
  ///
  /// [batchType] is the round's `batchType`, sent as `xklclx` exactly as the
  /// official index page does.
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
