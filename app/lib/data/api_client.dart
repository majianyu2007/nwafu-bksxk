/// The low-level HTTP client for the BKSXK API.
///
/// Responsibilities:
///  - prepend the configured origin + api prefix,
///  - attach the `token` header on every authenticated call,
///  - persist cookies (same-origin session) via a cookie jar,
///  - add cache-busting `timestamp` on GETs that expect it,
///  - normalise responses into [ApiResult] and detect session expiry.
///
/// Silent re-login is layered on top by [SessionManager], which owns the token
/// and supplies the [onSessionExpired] callback used here.
library;

import 'dart:async';
import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import '../core/constants.dart';
import '../core/errors.dart';
import 'models.dart';

/// Result of a lightweight reachability probe (for the diagnostics page).
class ReachabilityResult {
  ReachabilityResult({
    required this.reachable,
    required this.detail,
    this.latency,
    this.error,
  });

  final bool reachable;
  final String detail;
  final Duration? latency;
  final AppError? error;
}

class ApiClient {
  ApiClient({
    required String origin,
    CookieJar? cookieJar,
    Dio? dio,
  })  : _cookieJar = cookieJar ?? CookieJar(),
        _origin = _normaliseOrigin(origin) {
    _dio = dio ??
        Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 30),
          // The API returns JSON with assorted content-types; parse leniently.
          responseType: ResponseType.plain,
          headers: {
            'User-Agent':
                'Mozilla/5.0 (compatible; nwafu-xk/1.0; +local) AppleWebKit/537.36',
            'X-Requested-With': 'XMLHttpRequest',
          },
        ));
    _dio.interceptors.add(CookieManager(_cookieJar));
  }

  late final Dio _dio;
  final CookieJar _cookieJar;
  String _origin;

  /// Current auth token (`data.token` from login). Null when logged out.
  String? token;

  /// Called when a response indicates the session expired. Should perform a
  /// silent re-login and return the fresh token, or null if it could not.
  Future<String?> Function()? onSessionExpired;

  /// Guards against concurrent re-login storms — only one runs at a time.
  Completer<String?>? _reloginInFlight;

  String get origin => _origin;
  set origin(String value) => _origin = _normaliseOrigin(value);

  CookieJar get cookieJar => _cookieJar;

  static String _normaliseOrigin(String origin) {
    var o = origin.trim();
    if (o.endsWith('/')) o = o.substring(0, o.length - 1);
    return o;
  }

  String _url(String path) => '$_origin/xsxkapp$path';

  Map<String, String> _headers({bool auth = true}) {
    final h = <String, String>{};
    if (auth && token != null && token!.isNotEmpty) {
      h['token'] = token!;
    }
    return h;
  }

  /// Milliseconds since epoch, as the frontend's `timestamp`/`timestrap`.
  static String nowStamp() => DateTime.now().millisecondsSinceEpoch.toString();

  /// GET returning the parsed envelope. [query] is sent as query params.
  Future<ApiResult> getJson(
    String path, {
    Map<String, dynamic>? query,
    bool auth = true,
    bool addTimestamp = true,
    bool allowRelogin = true,
  }) async {
    final q = <String, dynamic>{...?query};
    if (addTimestamp && !q.containsKey('timestamp')) q['timestamp'] = nowStamp();
    return _request(
      () => _dio.get(
        _url(path),
        queryParameters: q,
        options: Options(headers: _headers(auth: auth)),
      ),
      auth: auth,
      allowRelogin: allowRelogin,
      retry: () => getJson(path, query: query, auth: auth, addTimestamp: addTimestamp, allowRelogin: false),
    );
  }

  /// POST form-encoded, returning the parsed envelope.
  Future<ApiResult> postForm(
    String path,
    Map<String, dynamic> form, {
    bool auth = true,
    Map<String, dynamic>? query,
    bool allowRelogin = true,
  }) async {
    return _request(
      () => _dio.post(
        _url(path),
        data: form,
        queryParameters: query,
        options: Options(
          headers: _headers(auth: auth),
          contentType: 'application/x-www-form-urlencoded; charset=UTF-8',
        ),
      ),
      auth: auth,
      allowRelogin: allowRelogin,
      retry: () => postForm(path, form, auth: auth, query: query, allowRelogin: false),
    );
  }

  /// Fetches raw bytes (e.g. captcha image). No envelope parsing.
  Future<List<int>> getBytes(String path, {Map<String, dynamic>? query, bool auth = false}) async {
    try {
      final resp = await _dio.get<List<int>>(
        _url(path),
        queryParameters: query,
        options: Options(
          headers: _headers(auth: auth),
          responseType: ResponseType.bytes,
        ),
      );
      return resp.data ?? const [];
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  /// Core request runner: parses the envelope, detects session expiry, and
  /// triggers a single silent re-login + retry when [allowRelogin] is set.
  Future<ApiResult> _request(
    Future<Response> Function() send, {
    required bool auth,
    required bool allowRelogin,
    required Future<ApiResult> Function() retry,
  }) async {
    Response resp;
    try {
      resp = await send();
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }

    final result = _parse(resp);

    if (auth && allowRelogin && _looksExpired(result, resp)) {
      final fresh = await _attemptRelogin();
      if (fresh != null) {
        return retry();
      }
      throw AppError(
        AppErrorKind.sessionExpired,
        message: '会话已过期，且自动重新登录失败',
        hint: '请重新登录。',
        retryable: false,
      );
    }
    return result;
  }

  ApiResult _parse(Response resp) {
    final body = resp.data;
    if (body is Map) {
      return ApiResult.fromJson(body.cast<String, dynamic>());
    }
    if (body is String) {
      final trimmed = body.trimLeft();
      if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
        try {
          final decoded = _decode(trimmed);
          if (decoded is Map) return ApiResult.fromJson(decoded.cast<String, dynamic>());
          return ApiResult(code: '1', msg: '', data: decoded, dataList: decoded is List ? decoded : const [], totalCount: 0);
        } catch (_) {
          // Fall through to non-JSON handling.
        }
      }
      // HTML or plain text: usually a login redirect => treat as expired.
      return ApiResult(
        code: '0',
        msg: 'non-json',
        data: body,
        dataList: const [],
        totalCount: 0,
        keyExpired: _htmlLooksLikeLogin(body),
        raw: const {},
      );
    }
    return ApiResult(code: '0', msg: 'empty', data: null, dataList: const [], totalCount: 0);
  }

  dynamic _decode(String s) => jsonDecode(s);

  bool _looksExpired(ApiResult r, Response resp) {
    if (r.keyExpired) return true;
    if (resp.statusCode == 401 || resp.statusCode == 403) return true;
    // Some deployments return code with an expiry message rather than a flag.
    final m = r.msg;
    if (!r.ok && (m.contains('登录') || m.contains('token') || m.contains('会话') || m.contains('超时'))) {
      return true;
    }
    return false;
  }

  bool _htmlLooksLikeLogin(String html) {
    final h = html.toLowerCase();
    return h.contains('login') || h.contains('统一身份') || h.contains('cas');
  }

  Future<String?> _attemptRelogin() async {
    final cb = onSessionExpired;
    if (cb == null) return null;
    // Collapse concurrent expiries into a single re-login.
    if (_reloginInFlight != null) return _reloginInFlight!.future;
    final completer = Completer<String?>();
    _reloginInFlight = completer;
    try {
      final fresh = await cb();
      token = fresh ?? token;
      completer.complete(fresh);
      return fresh;
    } catch (e) {
      completer.complete(null);
      return null;
    } finally {
      _reloginInFlight = null;
    }
  }

  Future<void> clearCookies() => _cookieJar.deleteAll();

  /// Lightweight reachability probe for the diagnostics page. Hits a cheap
  /// public endpoint (batch list) and classifies the outcome. Never throws.
  Future<ReachabilityResult> probe() async {
    final start = DateTime.now();
    try {
      await _dio.get(
        _url(Api.batch),
        queryParameters: {'timestamp': nowStamp()},
        options: Options(
          headers: _headers(auth: false),
          // Short timeout so the diagnostics page feels responsive.
          receiveTimeout: const Duration(seconds: 6),
          sendTimeout: const Duration(seconds: 6),
        ),
      );
      final latency = DateTime.now().difference(start);
      return ReachabilityResult(
        reachable: true,
        detail: '可以连接到 $_origin',
        latency: latency,
      );
    } on DioException catch (e) {
      final err = AppError.fromDio(e);
      return ReachabilityResult(
        reachable: false,
        detail: err.message,
        error: err,
      );
    }
  }
}
