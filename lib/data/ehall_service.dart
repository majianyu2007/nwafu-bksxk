/// The 金智 EMAP apps on ehall.nwafu.edu.cn, reached through the unified
/// identity login ([CasClient]).
///
/// Each app (`/jwapp/sys/<app>`) needs its own CAS ticket: the first visit to
/// its index page redirects through the AuthServer and comes back with
/// `?ticket=`, which sets `MOD_AUTH_CAS` / `_WEU` / `JSESSIONID`. The data
/// endpoints then answer 403 until `funauthapp/api/getAppConfig/<app>-<id>.do`
/// has been called once (the official page does this on load). An expired
/// session shows up as a 302 to the AuthServer. Responses look like
/// `{"code":"0","datas":{"<name>":{"rows":[...]}}}`.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/errors.dart';
import 'academic_calendar.dart' show calendarDate, schoolDate;
import 'cas_client.dart';
import 'degree_audit.dart';
import 'edu_models.dart';

const kEhallOrigin = 'https://ehall.nwafu.edu.cn';

/// The EMAP apps the client uses, with their ids from `getAppConfig`.
enum EmapApp {
  timetable('wdkbby', '5959167891382285'),
  grades('cjcx', '4768574631264620'),
  exams('studentWdksapApp', '4768687067472349'),
  rooms('kxjas', '4768402106681759'),
  degree('xywccx', '4980269146247992');

  const EmapApp(this.path, this.appId);
  final String path;
  final String appId;

  String get indexUrl => '$kEhallOrigin/jwapp/sys/$path/*default/index.do';
}

class EhallService {
  EhallService(this.cas);

  final CasClient cas;

  /// Browser cookies are shared with official tabs and can change independently.
  /// A web client must never save another student's data under this identity.
  String? expectedUsername;
  final _ready = <EmapApp>{};
  final _activating = <EmapApp, Future<void>>{};
  Future<bool>? _recovering;
  int _generation = 0;

  /// Called when the CAS login is gone and a fresh one is needed. Should
  /// sign in again (silently, with the saved password or passkey) and
  /// return true, or return false to surface the error.
  Future<bool> Function()? onLoginRequired;

  Dio get _dio => cas.dio;

  /// Forget activated apps, e.g. after a new login.
  void reset() {
    _generation++;
    _ready.clear();
    _activating.clear();
  }

  /// Visits the app's index (exchanging a CAS ticket) and calls its
  /// getAppConfig so the data endpoints answer. Serialized per app so parallel
  /// requests don't race through redundant CAS ticket exchanges.
  Future<void> activate(EmapApp app) {
    final existing = _activating[app];
    if (existing != null) return existing;
    final future = _doActivate(app);
    _activating[app] = future;
    return future.whenComplete(() {
      if (identical(_activating[app], future)) _activating.remove(app);
    });
  }

  Future<void> _doActivate(EmapApp app) async {
    final generation = _generation;
    final last = await cas.follow(app.indexUrl);
    if (last.realUri.host != Uri.parse(kEhallOrigin).host ||
        last.realUri.path != Uri.parse(app.indexUrl).path ||
        (last.statusCode ?? 500) >= 400) {
      throw AppError(
        AppErrorKind.sessionExpired,
        message: '统一身份认证登录已失效',
        hint: '请重新登录。',
      );
    }
    final config = await _send(
      () => _dio.get<String>(
        '$kEhallOrigin/jwapp/sys/funauthapp/api/getAppConfig/${app.path}-${app.appId}.do',
      ),
    );
    if (_expired(config)) throw _expiredError;
    try {
      final body = jsonDecode(config.data ?? '');
      if (body is! Map ||
          body['APP_ID']?.toString() != app.appId ||
          body['MODULES'] is! List ||
          (config.statusCode ?? 500) >= 400) {
        throw const FormatException('Invalid app configuration');
      }
    } on FormatException {
      throw AppError(AppErrorKind.schemaOrRedirect, message: '教务应用配置无效');
    }
    if (generation == _generation) _ready.add(app);
  }

  /// POSTs a form to an EMAP endpoint and returns `datas.<name>.rows`.
  Future<List<Map<String, dynamic>>> rows(
    EmapApp app,
    String path,
    String name, {
    Map<String, dynamic> form = const {},
  }) async {
    if (kIsWeb && expectedUsername != null) await _assertBrowserIdentity();
    final body = await _post(app, path, form);
    final datas = body['datas'];
    final block = datas is Map ? datas[name] : null;
    final list = block is Map ? block['rows'] : null;
    if (list is! List || list.any((r) => r is! Map<String, dynamic>)) {
      throw AppError(
        AppErrorKind.schemaOrRedirect,
        message: '教务系统数据结构已变化',
        hint: '未覆盖离线数据，请稍后重试或更新应用。',
      );
    }
    if (kIsWeb && expectedUsername != null) await _assertBrowserIdentity();
    return list.cast<Map<String, dynamic>>();
  }

  Future<void> _assertBrowserIdentity() async {
    final body = await _post(
      EmapApp.exams,
      'modules/wdksap/cxxsjbxx.do',
      const {},
    );
    final datas = body['datas'];
    final block = datas is Map ? datas['cxxsjbxx'] : null;
    final rows = block is Map ? block['rows'] : null;
    final row = rows is List && rows.length == 1 ? rows.single : null;
    final username = row is Map ? row['XH']?.toString().trim() : null;
    if (username == null || username.isEmpty) {
      throw AppError(
        AppErrorKind.schemaOrRedirect,
        message: '无法核验浏览器教务账号',
        hint: '未保存本次数据，请在学校官方页面重新登录。',
      );
    }
    if (username != expectedUsername) {
      reset();
      throw AppError(
        AppErrorKind.sessionExpired,
        message: '浏览器中的教务账号已切换',
        hint: '未保存其他账号的数据，请重新连接浏览器会话。',
      );
    }
  }

  Future<Map<String, dynamic>> _post(
    EmapApp app,
    String path,
    Map<String, dynamic> form, {
    bool retried = false,
  }) async {
    try {
      if (!_ready.contains(app)) await activate(app);
    } on AppError catch (e) {
      if (e.kind != AppErrorKind.sessionExpired || retried) rethrow;
      if (!await _recoverLogin(app)) throw _expiredError;
      return _post(app, path, form, retried: true);
    }
    final res = await _send(
      () => _dio.post<String>(
        '$kEhallOrigin/jwapp/sys/${app.path}/$path',
        data: form,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {'X-Requested-With': 'XMLHttpRequest'},
        ),
      ),
    );
    if (_expired(res)) {
      _ready.remove(app);
      if (retried || !await _recoverLogin(app)) throw _expiredError;
      return _post(app, path, form, retried: true);
    }
    return _decode(res);
  }

  static AppError get _expiredError => AppError(
    AppErrorKind.sessionExpired,
    message: '统一身份认证登录已失效',
    hint: '请重新登录；已同步的数据仍可离线查看。',
  );

  Future<bool> _recoverLogin(EmapApp app) {
    final existing = _recovering;
    if (existing != null) return existing;
    final future = _doRecoverLogin(app);
    _recovering = future;
    return future.whenComplete(() {
      if (identical(_recovering, future)) _recovering = null;
    });
  }

  Future<bool> _doRecoverLogin(EmapApp app) async {
    if (!await cas.hasLogin(app.indexUrl)) {
      if (!await (onLoginRequired?.call() ?? Future.value(false))) return false;
    }
    reset();
    return true;
  }

  bool _expired(Response<String> res) {
    if (res.statusCode == 302 ||
        res.statusCode == 401 ||
        res.statusCode == 403 ||
        (res.headers.value('location') ?? '').contains('authserver')) {
      return true;
    }
    final raw = res.data ?? '';
    final trimmed = raw.trimLeft();
    // Skip expensive full-body .toLowerCase() scans on 200 JSON responses
    // (freeRooms payloads can exceed 400 KB).
    if (res.statusCode == 200 &&
        (trimmed.startsWith('{') || trimmed.startsWith('['))) {
      return false;
    }
    final text = trimmed.toLowerCase();
    return text.contains('id="pwdlogin') ||
        text.contains('/authserver/login') ||
        text.contains('name="execution"');
  }

  Map<String, dynamic> _decode(Response<String> res) {
    final text = res.data ?? '';
    if ((res.statusCode ?? 500) >= 400) {
      throw AppError(AppErrorKind.serverError, message: '教务系统暂时无法响应');
    }
    try {
      final j = jsonDecode(text);
      if (j is Map<String, dynamic>) {
        if (j['code']?.toString() != '0') {
          throw AppError(
            AppErrorKind.unknown,
            message: (j['msg'] ?? j['message'] ?? '教务系统返回错误').toString(),
          );
        }
        return j;
      }
    } on FormatException {
      // fall through
    }
    throw AppError(
      AppErrorKind.schemaOrRedirect,
      message: '教务系统返回了无法识别的内容',
      hint: text.contains('<html') ? '服务器可能在维护，稍后再试。' : null,
    );
  }

  Future<Response<String>> _send(Future<Response<String>> Function() f) async {
    try {
      return await f();
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  // -------------------------------------------------------------------------
  // Timetable (我的本研课表, wdkbby)
  // -------------------------------------------------------------------------

  Future<EduTerm> currentTerm() async {
    final r = await rows(
      EmapApp.timetable,
      'modules/jshkcb/dqxnxq.do',
      'dqxnxq',
    );
    if (r.isEmpty) throw AppError(AppErrorKind.unknown, message: '未取得当前学期');
    try {
      return EduTerm.fromRow(r.first);
    } on FormatException {
      throw AppError(AppErrorKind.schemaOrRedirect, message: '教务系统当前学期数据无效');
    }
  }

  /// Every term the school knows about, newest first. Rows with a code the
  /// client cannot parse are skipped rather than failing the whole list.
  Future<List<EduTerm>> terms() async {
    final r = await rows(
      EmapApp.timetable,
      'modules/jshkcb/xnxqcx.do',
      'xnxqcx',
    );
    final terms = <EduTerm>[];
    for (final row in r) {
      try {
        terms.add(EduTerm.fromRow(row));
      } on FormatException {
        // e.g. an odd legacy code; the term picker just omits it.
      }
    }
    return terms;
  }

  Future<TermTimetable> timetable(EduTerm term) async {
    // First call activates EmapApp.timetable; the remaining 4 reads then run
    // in parallel instead of serially.
    final weeks = await rows(
      EmapApp.timetable,
      'modules/xskcb/cxxljc.do',
      'cxxljc',
      form: {'XN': term.year, 'XQ': term.half},
    );
    Future<List<Map<String, dynamic>>> fetchAdjustments() async {
      try {
        return await rows(
          EmapApp.timetable,
          'modules/xskcb/xsdkkc.do',
          'xsdkkc',
          form: {
            'XNXQDM': term.code,
            '*order': '-SQSJ',
            'querySetting': jsonEncode([
              {
                'name': 'BYBZ',
                'builder': 'notEqual',
                'linkOpt': 'AND',
                'value': '1',
              },
            ]),
          },
        );
      } on AppError {
        // 调课 is supplementary; the timetable itself already reflects it.
        return const [];
      }
    }

    final fetched = await Future.wait([
      rows(EmapApp.timetable, 'modules/jshkcb/jc.do', 'jc'),
      rows(
        EmapApp.timetable,
        'modules/xskcb/cxxszhxqkb.do',
        'cxxszhxqkb',
        form: {'XNXQDM': term.code},
      ),
      rows(
        EmapApp.timetable,
        'modules/xskcb/xswpkc.do',
        'xswpkc',
        form: {'XNXQDM': term.code},
      ),
      fetchAdjustments(),
    ]);
    final periods = fetched[0];
    final sessions = fetched[1];
    final unscheduled = fetched[2];
    final adjustments = fetched[3];

    if (weeks.isEmpty || periods.isEmpty) {
      throw AppError(
        AppErrorKind.schemaOrRedirect,
        message: '未取得学期校历或作息时间',
        hint: '未生成估算课表或提醒，请稍后重试。',
      );
    }
    final calendar = weeks.first;
    final start = DateTime.tryParse(
      (calendar['XQKSRQ'] ?? '').toString().replaceFirst(' ', 'T'),
    );
    final weekCount = int.tryParse('${calendar['ZZC'] ?? ''}');
    if (start == null || weekCount == null || weekCount < 1 || weekCount > 60) {
      throw AppError(AppErrorKind.schemaOrRedirect, message: '教务系统校历数据无效');
    }
    final firstDay = DateTime.utc(start.year, start.month, start.day);
    var firstMonday = firstDay.subtract(
      Duration(days: firstDay.weekday - DateTime.monday),
    );
    // The term start (XQKSRQ) is not always the Monday of teaching week 1
    // (orientation weeks, a start mid-week). The school's own "today is
    // week N" (dqzc.do) is authoritative, so anchor week 1 to it when today
    // lies inside this term.
    final anchored = await _weekOneFromSchool(term, firstMonday, weekCount);
    if (anchored != null) firstMonday = anchored;
    final List<ClassPeriod> parsedPeriods;
    final List<CourseSession> parsedSessions;
    try {
      parsedPeriods = periods.map(ClassPeriod.fromRow).toList()
        ..sort((a, b) => a.index.compareTo(b.index));
      parsedSessions = sessions.map(CourseSession.fromRow).toList();
      final indices = parsedPeriods.map((p) => p.index).toSet();
      if (indices.length != parsedPeriods.length ||
          parsedSessions.any(
            (s) =>
                !indices.contains(s.startPeriod) ||
                !indices.contains(s.endPeriod),
          )) {
        throw const FormatException('Unknown class period');
      }
    } on FormatException {
      throw AppError(AppErrorKind.schemaOrRedirect, message: '教务系统课表数据无效');
    }

    return TermTimetable(
      term: term,
      firstMonday: firstMonday,
      weekCount: weekCount,
      periods: parsedPeriods,
      sessions: parsedSessions,
      unscheduled: [for (final u in unscheduled) UnscheduledCourse.fromRow(u)],
      adjustments: [for (final a in adjustments) ClassAdjustment.fromRow(a)],
      syncedAt: DateTime.now(),
    );
  }

  Future<DateTime?> _weekOneFromSchool(
    EduTerm term,
    DateTime fallbackMonday,
    int weekCount,
  ) async {
    final today = schoolDate(DateTime.now());
    final end = fallbackMonday.add(Duration(days: weekCount * 7));
    // Buffer both ends by 28 days so orientation/military-training shifts at
    // term start don't skip dqzc.do during the final teaching weeks.
    if (today.isBefore(fallbackMonday.subtract(const Duration(days: 28))) ||
        !today.isBefore(end.add(const Duration(days: 28)))) {
      return null;
    }
    try {
      final r = await rows(
        EmapApp.timetable,
        'modules/jshkcb/dqzc.do',
        'dqzc',
        form: {
          'XN': term.year,
          'XQ': term.half,
          'RQ':
              '${today.year}-${today.month.toString().padLeft(2, '0')}-'
              '${today.day.toString().padLeft(2, '0')}',
        },
      );
      return weekOneMondayFrom(r.isEmpty ? null : r.first, today);
    } on AppError {
      return null;
    }
  }

  // -------------------------------------------------------------------------
  // Grades (成绩查询, cjcx)
  // -------------------------------------------------------------------------

  Future<GradeBook> grades() async {
    final records = <GradeRecord>[];
    for (var page = 1; page <= 20; page++) {
      final r = await rows(
        EmapApp.grades,
        'modules/cjcx/xscjcx.do',
        'xscjcx',
        form: {
          'querySetting': jsonEncode([
            {
              'name': 'SFYX',
              'caption': '是否有效',
              'linkOpt': 'AND',
              'builderList': 'cbl_m_List',
              'builder': 'm_value_equal',
              'value': '1',
            },
            {
              'name': 'SHOWMAXCJ',
              'caption': '显示最高成绩',
              'linkOpt': 'AND',
              'builderList': 'cbl_m_List',
              'builder': 'm_value_equal',
              'value': '0',
            },
          ]),
          '*order': '-XNXQDM,-KCH,-KXH',
          'pageSize': '100',
          'pageNumber': '$page',
        },
      );
      try {
        records.addAll(r.map(GradeRecord.fromRow));
      } on FormatException {
        throw AppError(
          AppErrorKind.schemaOrRedirect,
          message: '教务系统成绩数据格式异常',
          hint: '未覆盖离线成绩，请到学校官方页面查看。',
        );
      }
      if (r.length < 100) break;
      if (page == 20) {
        throw AppError(
          AppErrorKind.schemaOrRedirect,
          message: '成绩记录超过本次同步范围',
          hint: '未保存不完整成绩，请使用官方教务系统查看。',
        );
      }
    }
    GradeSummary summary = const GradeSummary();
    try {
      final s = await rows(
        EmapApp.grades,
        'modules/cjcx/cxxscjpm.do',
        'cxxscjpm',
      );
      if (s.isNotEmpty) summary = GradeSummary.fromRow(s.first);
    } on AppError {
      // Ranking is optional; some terms hide it.
    }
    return GradeBook(
      records: records,
      summary: summary,
      syncedAt: DateTime.now(),
    );
  }

  // -------------------------------------------------------------------------
  // Exams (考试安排, studentWdksapApp)
  // -------------------------------------------------------------------------

  Future<List<ExamEntry>> exams(EduTerm term) async {
    final r = await rows(
      EmapApp.exams,
      'WdksapController/cxxsksap.do',
      'cxxsksap',
      form: {
        'requestParamStr': jsonEncode({
          'XNXQDM': term.code,
          '*order': '-KSRQ,-KSSJMS',
        }),
      },
    );
    try {
      return [for (final row in r) ExamEntry.fromRow(row)];
    } on FormatException {
      throw AppError(
        AppErrorKind.schemaOrRedirect,
        message: '无法识别考试安排的数据结构',
        hint: '未覆盖已有考试数据，请到学校官方考试安排页面查看。',
      );
    }
  }

  /// The signed-in student's name, college, major and class. Read from the
  /// exam app's student-info endpoint, which shares the jwapp session (the
  /// portal's own `/getLoginUser` needs a separate portal ticket).
  Future<({String username, String name, String dept, String major, String className})>
  profile() async {
    final r = await rows(
      EmapApp.exams,
      'modules/wdksap/cxxsjbxx.do',
      'cxxsjbxx',
    );
    if (r.isEmpty) {
      throw AppError(
        AppErrorKind.sessionExpired,
        message: '未取得学生信息',
        hint: '请重新登录。',
      );
    }
    final s = r.first;
    final username = '${s['XH'] ?? ''}'.trim();
    if (username.isEmpty || r.length != 1) {
      throw AppError(
        AppErrorKind.schemaOrRedirect,
        message: '教务学生信息缺少唯一学号',
        hint: '无法确认所属账号，未连接或保存本次数据。',
      );
    }
    return (
      username: username,
      name: '${s['XM'] ?? ''}',
      dept: '${s['YXDM_DISPLAY'] ?? ''}',
      major: '${s['ZYDM_DISPLAY'] ?? ''}',
      className: '${s['BJDM_DISPLAY'] ?? ''}',
    );
  }

  // -------------------------------------------------------------------------
  // Free classrooms (空闲教室查询, kxjas)
  // -------------------------------------------------------------------------

  /// Rooms free on [date] (Beijing calendar day) from period [from] to [to].
  /// The official page posts flat fields (KXRQ/KSJC/JSJC), not querySetting.
  /// The server ignores paging and returns every room (~850, ~4 s), so this
  /// is one request; callers cache per day and block.
  Future<List<FreeRoom>> freeRooms(DateTime date, int from, int to) async {
    final day =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    final r = await rows(
      EmapApp.rooms,
      'modules/kxjscx/cxkxjs.do',
      'cxkxjs',
      form: {
        'KXRQ': day,
        'KSJC': '$from',
        'JSJC': '$to',
        'pageSize': '2000',
        'pageNumber': '1',
      },
    ).timeout(
      const Duration(seconds: 25),
      onTimeout: () => throw AppError(
        AppErrorKind.timeout,
        message: '空教室查询超时',
        hint: '学校服务器较慢，请稍后下拉重试。',
      ),
    );
    return [
      for (final row in r)
        if (FreeRoom.fromRow(row) case final room when room.name.isNotEmpty)
          room,
    ];
  }

  // -------------------------------------------------------------------------
  // Degree audit (学业完成查询, xywccx). Read-only: 重新计算 is never posted.
  // -------------------------------------------------------------------------

  /// Every training plan of [username] with its group tree. Selected credits
  /// (已选学分) need one request per group; they are fetched [parallel] at a
  /// time and a failure only leaves that figure blank.
  Future<DegreeAudit> degreeAudit(
    String username, {
    bool withSelected = true,
    int parallel = 4,
  }) async {
    final plans = await rows(
      EmapApp.degree,
      'modules/xywccx/grpyfacx.do',
      'grpyfacx',
      form: {'XH': username},
    );
    String? term;
    try {
      final t = await rows(
        EmapApp.degree,
        'modules/xywccx/cxdqxnxq.do',
        'cxdqxnxq',
      );
      if (t.isNotEmpty) term = EduTerm.fromRow(t.first).code;
    } on Object {
      // Without a term the groups still load; 已选学分 stays empty.
    }
    final result = <DegreePlan>[];
    for (final plan in plans) {
      final id = '${plan['PYFADM'] ?? ''}'.trim();
      if (id.isEmpty) continue;
      final base = {
        'XH': username,
        'PYFADM': id,
        'BYNJDM': '-',
        'SCLBDM': '04',
      };
      final pair = await Future.wait([
        rows(
          EmapApp.degree,
          'modules/xywccx/cxscfa.do',
          'cxscfa',
          form: base,
        ),
        rows(
          EmapApp.degree,
          'modules/xywccx/cxscfakz.do',
          'cxscfakz',
          form: {...base, 'XNXQDM': ?term},
        ),
      ]);
      final audit = pair[0];
      final groups = pair[1];
      double? selected;
      final perGroup = <String, double>{};
      if (withSelected && term != null) {
        final form = {...base, 'XNXQDM': term};
        Future<double?> credits(Map<String, String> extra) async {
          try {
            return selectedCreditsFrom(
              await rows(
                EmapApp.degree,
                'modules/xywccx/cxfakzyxxfgj.do',
                'cxfakzyxxfgj',
                form: {...extra, ...form},
              ),
            );
          } on AppError catch (e) {
            if (e.kind == AppErrorKind.sessionExpired ||
                e.kind == AppErrorKind.campusNetwork) {
              rethrow;
            }
            return null;
          }
        }

        final queue = <Map<String, dynamic>>[
          for (final g in groups)
            if ('${g['KZH'] ?? ''}'.trim().isNotEmpty) g,
        ];
        var fetchTotal = true;
        Future<void> worker() async {
          if (fetchTotal) {
            fetchTotal = false;
            selected = await credits(const {});
          }
          while (queue.isNotEmpty) {
            final g = queue.removeLast();
            final kzh = '${g['KZH'] ?? ''}'.trim();
            final v = await credits({
              'KZLXDM': '${g['KZLXDM'] ?? ''}'.trim(),
              'KZH': kzh,
            });
            if (v != null) perGroup[kzh] = v;
          }
        }

        await Future.wait([
          for (var i = 0; i < parallel.clamp(1, 8); i++) worker(),
        ]);
      }
      try {
        result.add(
          DegreePlan.fromRows(
            plan: plan,
            audit: audit.isEmpty ? null : audit.first,
            groups: groups,
            selected: selected,
            groupSelected: perGroup,
          ),
        );
      } on Object {
        throw AppError(
          AppErrorKind.schemaOrRedirect,
          message: '学业完成数据结构已变化',
          hint: '未覆盖离线数据，请到学校官方页面查看。',
        );
      }
    }
    return DegreeAudit(plans: result, syncedAt: DateTime.now());
  }
}

/// Week 1's Monday from a `dqzc.do` row (`ZC` = teaching week of [today],
/// `XN`/`XQ` echo the term). Null when the row is missing or nonsensical.
DateTime? weekOneMondayFrom(Map<String, dynamic>? row, DateTime today) {
  final week = int.tryParse('${row?['ZC'] ?? ''}');
  if (week == null || week < 1 || week > 60) return null;
  final day = calendarDate(today);
  final monday = day.subtract(Duration(days: day.weekday - 1));
  return monday.subtract(Duration(days: (week - 1) * 7));
}
