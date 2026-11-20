/// The school portals behind the unified identity: 一网通办
/// (newehall.nwafu.edu.cn) for unread messages and to-dos, and the ehall
/// portal's 新闻通知 card for notices.
///
/// Both are CAS services like the EMAP apps. Visiting `<host>/login` goes
/// through the AuthServer with the stored CASTGC and comes back with a
/// ticket that sets the host's own session (newehall: `MOD_AUTH_CAS` /
/// `asessionid`). A dead session shows up differently per endpoint (checked
/// 2026-10-13 without a session):
///  - `jsonp/...` answers 200 `{"result":"failed","data":"请登录!",
///    "hasLogin":false}`, or a success with `hasLogin:false` and empty data;
///  - `taskcenterapp/...` answers 302 to the AuthServer;
///  - ehall `execCardMethod` answers `{"errcode":"999","errmsg":"无权限调用"}`.
///
/// Shapes from a logged-in browser on 2026-10-13: getUnreadMessageCount →
/// `data.totalSize`; getTaskTodoAndDoneCount → `datas.todoCount/doneCount`;
/// the news card → `data.datas.data[]` with title/channelName/pubTime/url.
/// The message list (`jsonp/getTagsMessages`, `data.children[]`) and the
/// to-do list (`getTaskRestful.do`, `datas.queryTodoTask.taskData[]`) had no
/// rows on the accounts checked, so their items are read defensively.
///
/// Supported natively and on web when the companion bridge is >= 1.4.2.
library;

import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/errors.dart';
import '../core/web_env.dart';
import 'cas_client.dart';

const kNewEhallOrigin = 'https://newehall.nwafu.edu.cn';
const kEhallPortalOrigin = 'https://ehall.nwafu.edu.cn';
final _kNewEhallUri = Uri.parse(kNewEhallOrigin);
final _kEhallPortalUri = Uri.parse(kEhallPortalOrigin);
final _portalAuthServerHost = Uri.parse(kAuthServer).host;
const _portalReAuthMarker = Object();

/// The two portal sessions this service opens.
enum PortalHost {
  newehall(kNewEhallOrigin, 'newehall.nwafu.edu.cn'),
  ehall(kEhallPortalOrigin, 'ehall.nwafu.edu.cn');

  const PortalHost(this.origin, this.host);
  final String origin;
  final String host;
  String get loginUrl => '$origin/login';
}

/// One message, to-do or notice, whatever its source called the fields.
class PortalItem {
  const PortalItem({
    required this.title,
    this.summary = '',
    this.time = '',
    this.source = '',
    this.url,
    this.unread = false,
  });

  final String title;
  final String summary;

  /// As the server wrote it ("2026/10/13", "2026-10-13 09:00").
  final String time;

  /// Channel / category / sender.
  final String source;

  /// Where tapping goes (http/https only), if the item has a link.
  final Uri? url;
  final bool unread;

  static const _titleKeys = [
    'title',
    'TITLE',
    'msgTitle',
    'messageTitle',
    'subject',
    'taskName',
    'TASK_NAME',
    'processName',
    'PROCESS_NAME',
    'appName',
    'name',
  ];
  static const _summaryKeys = [
    'summary',
    'abstractVal',
    'content',
    'contents',
    'msgContent',
    'messageContent',
    'CONTENT',
    'desc',
    'description',
    'nodeName',
    'NODE_NAME',
  ];
  static const _timeKeys = [
    'pubTime',
    'publishTime',
    'sendTime',
    'createTime',
    'CREATE_TIME',
    'startTime',
    'START_TIME',
    'arriveTime',
    'updateTime',
    'time',
    'TIME',
    'createDate',
  ];
  static const _sourceKeys = [
    'channelName',
    'typeName',
    'tagName',
    'sourceName',
    'SOURCE_NAME',
    'appName',
    'sender',
    'senderName',
    'author',
    'initiatorName',
    'CREATOR_NAME',
  ];
  static const _urlKeys = [
    'url',
    'URL',
    'linkUrl',
    'pcUrl',
    'pcLink',
    'link',
    'href',
    'detailUrl',
    'taskUrl',
    'PC_URL',
    'mobileUrl',
  ];

  static final _dateOnlyRe = RegExp(r'^[\d\-\s:.T]+$');
  static final _hexIdRe = RegExp(r'^[0-9a-fA-F\-]{16,}$');
  static final _htmlTagRe = RegExp(r'<[^>]*>');
  static final _htmlEntityRe =
      RegExp(r'&(?:#(\d+)|#x([0-9a-fA-F]+)|([a-zA-Z0-9]+));');
  static final _multiSpaceRe = RegExp(r'\s+');
  static const _namedEntities = {
    'nbsp': ' ',
    'amp': '&',
    'lt': '<',
    'gt': '>',
    'quot': '"',
    'apos': "'",
    'ldquo': '“',
    'rdquo': '”',
    'lsquo': '‘',
    'rsquo': '’',
    'mdash': '—',
    'ndash': '–',
    'hellip': '…',
  };

  /// Reads any row shape. Missing fields stay empty; a row with no
  /// recognisable title falls back to its first longer text value so it is
  /// still shown rather than dropped.
  factory PortalItem.fromRow(Map<String, dynamic> row, {Uri? base}) {
    var title = _plain(_pick(row, _titleKeys));
    final summary = _plain(_pick(row, _summaryKeys));
    if (title.isEmpty) title = summary;
    if (title.isEmpty) {
      for (final v in row.values) {
        if (v is String) {
          final p = _plain(v);
          if (p.length >= 4 &&
              !p.startsWith('http') &&
              !_dateOnlyRe.hasMatch(p) &&
              !_hexIdRe.hasMatch(p)) {
            title = p;
            break;
          }
        }
      }
    }
    final read = row['read'] ?? row['isRead'] ?? row['readStatus'];
    var source = _plain(_pick(row, _sourceKeys));
    if (source.endsWith('/')) source = source.substring(0, source.length - 1);
    return PortalItem(
      title: title.isEmpty ? '（无标题）' : title,
      summary: summary == title ? '' : summary,
      time: _pick(row, _timeKeys),
      source: source,
      url: safePortalLink(_pick(row, _urlKeys), base: base),
      unread: read == false || read == 0 || read == '0',
    );
  }

  static String _pick(Map<String, dynamic> row, List<String> keys) {
    for (final k in keys) {
      final v = row[k];
      if (v is String || v is num) {
        final s = '$v'.trim();
        if (s.isNotEmpty && s != 'null') return s;
      }
    }
    return '';
  }

  /// Strips HTML tags, decodes HTML entities in a single pass (preventing
  /// double-decoding like `&amp;lt;` -> `<`), and squeezes whitespace.
  static String _plain(String s) {
    if (s.isEmpty) return '';
    var out = s.replaceAll(_htmlTagRe, ' ');
    if (out.contains('&')) {
      out = out.replaceAllMapped(_htmlEntityRe, (m) {
        final dec = m[1];
        if (dec != null) {
          final cp = int.tryParse(dec);
          return _validCodePoint(cp) ? String.fromCharCode(cp!) : '';
        }
        final hex = m[2];
        if (hex != null) {
          final cp = int.tryParse(hex, radix: 16);
          return _validCodePoint(cp) ? String.fromCharCode(cp!) : '';
        }
        return _namedEntities[m[3]] ?? m[0]!;
      });
    }
    return out.replaceAll(_multiSpaceRe, ' ').trim();
  }

  static bool _validCodePoint(int? cp) =>
      cp != null &&
      cp > 0 &&
      cp <= 0x10FFFF &&
      (cp < 0xD800 || cp > 0xDFFF);
}

/// An http(s) link from a row, resolved against [base] when relative.
/// Anything else (javascript:, mailto:, garbage) is dropped.
Uri? safePortalLink(String raw, {Uri? base}) {
  if (raw.isEmpty) return null;
  final parsed = Uri.tryParse(raw.trim());
  if (parsed == null) return null;
  final uri = parsed.hasScheme ? parsed : base?.resolveUri(parsed);
  if (uri == null ||
      (uri.scheme != 'https' && uri.scheme != 'http') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return uri;
}

/// What the 消息 page shows. Each section loads on its own; a failed one
/// leaves its list empty and its error set.
class PortalInbox {
  const PortalInbox({
    this.unread,
    this.todo,
    this.done,
    this.todos = const [],
    this.messages = const [],
    this.notices = const [],
    this.errors = const {},
    required this.fetchedAt,
  });

  final int? unread;
  final int? todo;
  final int? done;
  final List<PortalItem> todos;
  final List<PortalItem> messages;
  final List<PortalItem> notices;

  /// Section name (`counts`, `todos`, `messages`, `notices`) → what failed.
  final Map<String, AppError> errors;
  final DateTime fetchedAt;
}

class PortalService {
  PortalService(this.cas, {Random? random}) : _random = random ?? Random();

  final CasClient cas;
  final Random _random;
  final _ready = <PortalHost>{};
  final _opening = <PortalHost, Future<void>>{};
  Future<bool>? _recovering;
  int _generation = 0;

  /// Same contract as `EhallService.onLoginRequired`: sign in again silently
  /// and return true, or return false to surface the error.
  Future<bool> Function()? onLoginRequired;

  Dio get _dio => cas.dio;

  void reset() {
    _generation++;
    _ready.clear();
    _opening.clear();
  }

  static void _requireSessionSupport() {
    if (kIsWeb && !isFullCampusBridgeReady) {
      throw AppError(
        AppErrorKind.schemaOrRedirect,
        message: '请更新网页版桥接脚本（需 ≥ 1.4.2）',
        hint: '旧版桥接脚本不支持一网通办消息接口，更新后刷新页面即可查看。',
      );
    }
  }

  static AppError get _expiredError => AppError(
    AppErrorKind.sessionExpired,
    message: '统一身份认证登录已失效',
    hint: '请重新登录。',
  );

  /// Exchanges a CAS ticket for the host's session (coalesced per host).
  Future<void> open(PortalHost host) {
    _requireSessionSupport();
    if (_ready.contains(host)) return Future.value();
    final existing = _opening[host];
    if (existing != null) return existing;
    final gen = _generation;
    late final Future<void> run;
    run = () async {
      final last = await cas.follow(host.loginUrl);
      if (last.realUri.host == _portalAuthServerHost) {
        if (last.realUri.path.contains('/reAuthCheck/')) {
          throw AppError(
            AppErrorKind.sessionExpired,
            message: '访问学校门户需要二次验证',
            hint: kIsWeb && !isCasLoginBridgeReady
                ? '请先在浏览器打开 ${host.host} 完成二次验证后刷新。'
                : '请重新登录统一身份认证，并在二次验证时勾选「信任此设备」后再试。',
            raw: _portalReAuthMarker,
          );
        }
        final tip = extractCasErrorTip(last.data ?? '');
        if (tip.isNotEmpty) {
          throw classifyLoginFailure(last.data ?? '');
        }
      }
      if (last.realUri.host != host.host || (last.statusCode ?? 500) >= 400) {
        throw _expiredError;
      }
      if (gen == _generation) _ready.add(host);
    }().whenComplete(() {
      if (identical(_opening[host], run)) _opening.remove(host);
    });
    _opening[host] = run;
    return run;
  }

  Future<Map<String, dynamic>> _call(
    PortalHost host,
    Future<Response<String>> Function() send, {
    bool retried = false,
  }) async {
    _requireSessionSupport();
    try {
      if (!_ready.contains(host)) await open(host);
    } on AppError catch (e) {
      if (e.kind != AppErrorKind.sessionExpired ||
          identical(e.raw, _portalReAuthMarker) ||
          retried) {
        rethrow;
      }
      if (!await _recover(host)) throw _expiredError;
      return _call(host, send, retried: true);
    }
    final Response<String> res;
    try {
      res = await send();
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
    final body = _decode(res);
    if (body == null || _expired(res, body)) {
      _ready.remove(host);
      if (body != null || _redirectedToLogin(res)) {
        if (retried || !await _recover(host)) throw _expiredError;
        return _call(host, send, retried: true);
      }
      if ((res.statusCode ?? 500) >= 400) {
        throw AppError(AppErrorKind.serverError, message: '学校门户暂时无法响应');
      }
      throw AppError(
        AppErrorKind.schemaOrRedirect,
        message: '学校门户返回了无法识别的内容',
      );
    }
    return body;
  }

  Future<bool> _recover(PortalHost host) {
    final existing = _recovering;
    if (existing != null) return existing;
    late final Future<bool> run;
    run = () async {
      if (!await cas.hasLogin(host.loginUrl)) {
        if (!await (onLoginRequired?.call() ?? Future.value(false))) {
          return false;
        }
      }
      reset();
      return true;
    }().whenComplete(() {
      if (identical(_recovering, run)) _recovering = null;
    });
    _recovering = run;
    return run;
  }

  static bool _redirectedToLogin(Response<String> res) {
    if (res.statusCode == 302 ||
        res.statusCode == 401 ||
        res.statusCode == 403 ||
        (res.headers.value('location') ?? '').contains('authserver')) {
      return true;
    }
    final trimmed = (res.data ?? '').trimLeft();
    if (res.statusCode == 200 &&
        (trimmed.startsWith('{') || trimmed.startsWith('['))) {
      return false;
    }
    final text = trimmed.toLowerCase();
    return text.contains('/authserver/login') ||
        text.contains('name="execution"');
  }

  static bool _expired(Response<String> res, Map<String, dynamic> body) =>
      _redirectedToLogin(res) ||
      body['hasLogin'] == false ||
      body['errcode']?.toString() == '999' ||
      (body['result'] == 'failed' && '${body['data']}'.contains('登录'));

  static Map<String, dynamic>? _decode(Response<String> res) {
    try {
      final j = jsonDecode(res.data ?? '');
      return j is Map<String, dynamic> ? j : null;
    } on FormatException {
      return null;
    }
  }

  static Map<String, dynamic> _map(Object? v) =>
      v is Map<String, dynamic> ? v : const {};

  static List<Map<String, dynamic>> _list(Object? v) =>
      v is List ? v.whereType<Map<String, dynamic>>().toList() : const [];

  static int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v');

  Future<Map<String, dynamic>> _newehallGet(String path) => _call(
    PortalHost.newehall,
    () => _dio.get<String>(
      '$kNewEhallOrigin$path',
      queryParameters: {'_': DateTime.now().millisecondsSinceEpoch},
      options: Options(headers: {'X-Requested-With': 'XMLHttpRequest'}),
    ),
  );

  Future<Map<String, dynamic>> _newehallPost(String path, [Object? json]) =>
      _call(
        PortalHost.newehall,
        () => _dio.post<String>(
          '$kNewEhallOrigin$path',
          data: json == null ? null : jsonEncode(json),
          options: Options(
            contentType: 'application/json;charset=UTF-8',
            headers: {'X-Requested-With': 'XMLHttpRequest'},
          ),
        ),
      );

  // ---------------------------------------------------------------------------
  // 一网通办
  // ---------------------------------------------------------------------------

  /// Unread message count (the portal's 未读消息 card).
  Future<int?> unreadCount() async {
    final j = await _newehallGet('/jsonp/ywtb/getUnreadMessageCount');
    return _int(_map(j['data'])['totalSize']);
  }

  /// 待办 / 已办 counts of the task centre.
  Future<({int? todo, int? done})> taskCounts() async {
    final j = await _newehallPost(
      '/taskcenterapp/sys/taskCenter/taskNew/getTaskTodoAndDoneCount.do',
    );
    final d = _map(j['datas']);
    return (todo: _int(d['todoCount']), done: _int(d['doneCount']));
  }

  /// The first page of to-dos (flag 1 = 待办).
  Future<List<PortalItem>> todos({int size = 20}) async {
    final j = await _newehallPost(
      '/taskcenterapp/sys/taskCenter/taskNew/getTaskRestful.do',
      {
        'flag': 1,
        'sourceWid': '',
        'pageNumber': 1,
        'pageSize': size,
        '_': DateTime.now().millisecondsSinceEpoch,
      },
    );
    final d = _map(j['datas']);
    final rows = _list(_map(d['queryTodoTask'])['taskData']);
    return [
      for (final r in rows) PortalItem.fromRow(r, base: _kNewEhallUri),
    ];
  }

  /// The first page of messages from every category.
  Future<List<PortalItem>> messages({int size = 20}) async {
    final j = await _newehallGet(
      '/jsonp/getTagsMessages?typeId=&size=$size&start=0&typeName=',
    );
    final data = j['data'];
    final List<Map<String, dynamic>> rows;
    if (data is List) {
      rows = _list(data);
    } else {
      final m = _map(data);
      final children = _list(m['children']);
      rows = children.isNotEmpty ? children : _list(m['rows'] ?? m['list']);
    }
    return [
      for (final r in rows) PortalItem.fromRow(r, base: _kNewEhallUri),
    ];
  }

  // ---------------------------------------------------------------------------
  // ehall 新闻通知 card
  // ---------------------------------------------------------------------------

  static const _newsCardWid = '47526598509360696';
  static const _newsCardId = 'SYS_CARD_NEWSANNOUNCEMENT';

  Future<Map<String, dynamic>> _newsCard(
    String method,
    Map<String, dynamic> param,
  ) async {
    final j = await _call(
      PortalHost.ehall,
      () => _dio.post<String>(
        '$kEhallPortalOrigin/execCardMethod/$_newsCardWid/$_newsCardId',
        data: jsonEncode({
          'cardId': _newsCardId,
          'cardWid': _newsCardWid,
          'method': method,
          'param': {...param, 'lang': 'zh_CN', 'platformType': 0},
          'n': '${_random.nextDouble()}',
        }),
        options: Options(contentType: 'application/json;charset=UTF-8'),
      ),
    );
    if (j['errcode']?.toString() != '0') {
      throw AppError(
        AppErrorKind.unknown,
        message: (j['errmsg'] ?? '获取通知失败').toString(),
      );
    }
    return _map(j['data']);
  }

  /// The newest notices from the channels the portal shows this student
  /// (OA通知公告, 新闻焦点, …), as the ehall home page lists them.
  Future<List<PortalItem>> notices() async {
    final channels = await _newsCard('getConfiguredAndSubscribedChannel', {});
    var ids = [
      for (final c in _list(channels['subscribedChannel']))
        if ('${c['wid'] ?? ''}'.isNotEmpty) '${c['wid']}',
    ];
    if (ids.isEmpty) {
      ids = [
        for (final c in _list(channels['configuredChannel']))
          if ('${c['wid'] ?? ''}'.isNotEmpty) '${c['wid']}',
      ];
    }
    final news = await _newsCard('getChannelNews', {
      'channelIds': ids.join(','),
      'programIds': '',
      'pageNumber': 1,
    });
    final rows = _list(_map(news['datas'])['data']);
    return [
      for (final r in rows) PortalItem.fromRow(r, base: _kEhallPortalUri),
    ];
  }

  // ---------------------------------------------------------------------------

  /// Everything the 消息 page needs. Sections fail independently; only when
  /// every one fails is the first error thrown.
  Future<PortalInbox> inbox({bool withNotices = true}) async {
    final errors = <String, AppError>{};
    Future<T?> guard<T>(String section, Future<T> Function() f) async {
      try {
        return await f();
      } on AppError catch (e) {
        errors[section] ??= e;
        return null;
      } catch (e) {
        errors[section] ??= AppError(
          AppErrorKind.schemaOrRedirect,
          message: '学校门户数据结构已变化',
          raw: e,
        );
        return null;
      }
    }

    // One newehall request first so a re-login happens once, not in parallel.
    final unread = await guard('counts', unreadCount);
    final firstErr = errors['counts'];
    if (unread == null &&
        firstErr != null &&
        (firstErr.kind == AppErrorKind.sessionExpired ||
            firstErr.kind == AppErrorKind.campusNetwork)) {
      throw firstErr;
    }
    final results = await Future.wait([
      guard('counts', taskCounts),
      guard('messages', messages),
      if (withNotices) guard('notices', notices),
    ]);
    final counts = results[0] as ({int? todo, int? done})?;
    final messageList = results[1] as List<PortalItem>?;
    final noticeList = withNotices ? results[2] as List<PortalItem>? : null;
    if (unread == null &&
        counts == null &&
        messageList == null &&
        noticeList == null &&
        errors.isNotEmpty) {
      throw errors.values.first;
    }
    final todoList = (counts?.todo ?? 0) > 0
        ? await guard('todos', todos)
        : null;
    return PortalInbox(
      unread: unread,
      todo: counts?.todo,
      done: counts?.done,
      todos: todoList ?? const [],
      messages: messageList ?? const [],
      notices: noticeList ?? const [],
      errors: errors,
      fetchedAt: DateTime.now(),
    );
  }
}
