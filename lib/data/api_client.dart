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

import 'package:flutter/foundation.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';

import '../core/constants.dart';
import '../core/errors.dart';
import '../core/web_env.dart';
import 'models.dart';
import 'secure_cookie_storage.dart' show OriginScopedCookieManager;
import 'vpn/campus_proxy.dart';

/// Result of probing one backend node of the course-selection cluster.
class ClusterNodeProbe {
  const ClusterNodeProbe({
    this.route,
    this.initTimestamp,
  });

  /// Load-balancer sticky cookie value (`route=<hash>`), or null if absent.
  final String? route;

  /// Server cache generation (`publicinfo/sysparam.do` → `data.initTimestamp`).
  final int? initTimestamp;
}

class _CachedFreshNode {
  const _CachedFreshNode({
    required this.route,
    required this.initTimestamp,
    required this.verifiedAt,
  });

  final String route;
  final int initTimestamp;
  final DateTime verifiedAt;
}

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
        _origin = _normaliseOrigin(origin),
        _usesDefaultTransport = dio == null {
    _dio = dio ??
        Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 30),
          // The API returns JSON with assorted content-types; parse leniently.
          responseType: ResponseType.plain,
          headers: {
            if (!kIsWeb)
              'User-Agent':
                  'Mozilla/5.0 (compatible; nwafu-xk/1.0; +local) AppleWebKit/537.36',
            'X-Requested-With': 'XMLHttpRequest',
          },
        ));
    if (!kIsWeb) {
      _dio.interceptors.add(OriginScopedCookieManager(_cookieJar));
      if (dio == null) CampusProxy.instance.attach(_dio);
    }
  }

  /// Process-wide cache of the freshest verified load-balancer node per origin
  /// (so `anonymousAuthProvider`, `publicInfoServiceProvider`, and per-account
  /// clients all avoid stale/zombie backend nodes without redundant probes).
  static final Map<String, _CachedFreshNode> _freshNodes = {};
  static final Map<String, int> _highestInitTimestamps = {};
  static final Map<String, Future<ClusterNodeProbe?>> _pinInFlight = {};
  static const _freshNodeTtl = Duration(minutes: 5);
  static final _routeCookieRe = RegExp(r'^\s*route=([^;\s]+)', caseSensitive: false);

  @visibleForTesting
  static void resetClusterNodeCache() {
    _freshNodes.clear();
    _highestInitTimestamps.clear();
    _pinInFlight.clear();
  }

  late final Dio _dio;
  Dio? _probeDio;
  final CookieJar _cookieJar;
  final bool _usesDefaultTransport;
  final String _origin;
  bool _closed = false;
  bool _pendingBridgeRouteRefresh = false;

  /// Current auth token (`data.token` from login). Null when logged out.
  String? token;

  /// Called when a response indicates the session expired. Should perform a
  /// silent re-login and return the fresh token, or null if it could not.
  Future<String?> Function()? onSessionExpired;

  /// Guards against concurrent re-login storms — only one runs at a time.
  Completer<String?>? _reloginInFlight;

  String get origin => _origin;

  CookieJar get cookieJar => _cookieJar;

  /// Highest `sysparam.do -> data.initTimestamp` observed on this origin.
  int? get knownClusterInitTimestamp => _highestInitTimestamps[_origin];

  /// Records a node's `initTimestamp` into the cluster high-water mark.
  /// If a newer generation appears, any older cached node is evicted.
  void recordClusterInitTimestamp(int? ts) {
    if (ts == null || ts <= 0) return;
    final prev = _highestInitTimestamps[_origin] ?? 0;
    if (ts > prev) {
      _highestInitTimestamps[_origin] = ts;
      final cached = _freshNodes[_origin];
      if (cached != null && cached.initTimestamp < ts) {
        _freshNodes.remove(_origin);
      }
    }
  }

  /// Whether this client should probe multiple backend nodes for freshness.
  /// Disabled on web (handled by the bridge), custom mock Dio clients, and
  /// RFC 2606 / loopback test hosts.
  bool get supportsClusterProbe {
    if (!_usesDefaultTransport || kIsWeb) return false;
    final host = Uri.tryParse(_origin)?.host.toLowerCase() ?? '';
    if (host.isEmpty ||
        host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '::1' ||
        host.endsWith('.invalid') ||
        host.endsWith('.test') ||
        host.endsWith('.example') ||
        host.endsWith('.local')) {
      return false;
    }
    return true;
  }

  static int? parseInitTimestamp(dynamic data) {
    if (data is! Map) return null;
    final raw = data['initTimestamp'];
    if (raw == null) return null;
    if (raw is int) return raw > 0 ? raw : null;
    if (raw is num) return raw > 0 ? raw.toInt() : null;
    final parsed = int.tryParse(raw.toString().trim());
    return (parsed != null && parsed > 0) ? parsed : null;
  }

  static String? extractRouteCookie(List<String>? setCookies) {
    if (setCookies == null) return null;
    for (final header in setCookies) {
      final match = _routeCookieRe.firstMatch(header);
      if (match != null) {
        final v = match.group(1)?.trim();
        if (v != null && v.isNotEmpty) return v;
      }
    }
    return null;
  }

  static String _normaliseOrigin(String origin) {
    var o = origin.trim();
    while (o.endsWith('/')) {
      o = o.substring(0, o.length - 1);
    }
    return o;
  }

  String _url(String path) => '$_origin/xsxkapp$path';

  Uri get _cookieUri => Uri.parse('$_origin/xsxkapp/');

  Map<String, String> _headers({bool auth = true}) {
    final h = <String, String>{};
    if (auth && token != null && token!.isNotEmpty) {
      h['token'] = token!;
    }
    h['Cache-Control'] = 'no-cache';
    if (_pendingBridgeRouteRefresh && isFreshRouteBridgeReady) {
      _pendingBridgeRouteRefresh = false;
      h['X-Bksxk-Refresh-Route'] = '1';
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
    if (addTimestamp && !q.containsKey('timestamp')) {
      q['timestamp'] = nowStamp();
    }
    final res = await _request(
      () => _dio.get(
        _url(path),
        queryParameters: q,
        options: Options(headers: _headers(auth: auth)),
      ),
      auth: auth,
      allowRelogin: allowRelogin,
      retry: () => getJson(path,
          query: query,
          auth: auth,
          addTimestamp: addTimestamp,
          allowRelogin: false),
    );
    if (path == Api.sysParam && res.ok) {
      recordClusterInitTimestamp(parseInitTimestamp(res.data));
    }
    return res;
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
      retry: () =>
          postForm(path, form, auth: auth, query: query, allowRelogin: false),
    );
  }

  /// Fetches raw bytes (e.g. captcha image). No envelope parsing.
  Future<List<int>> getBytes(String path,
      {Map<String, dynamic>? query, bool auth = false}) async {
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
    final usedToken = token;
    Response resp;
    try {
      resp = await send();
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (auth && allowRelogin && (status == 401 || status == 403)) {
        if (usedToken != null && token != null && token != usedToken) {
          return retry();
        }
        final fresh = await _attemptRelogin();
        if (fresh != null) return retry();
      }
      throw AppError.fromDio(e);
    }

    final result = _parse(resp);

    if (auth && _looksExpired(result, resp)) {
      if (allowRelogin) {
        // Another concurrent request already refreshed the token; just retry
        // with the fresh token instead of kicking it off with a duplicate login.
        if (usedToken != null && token != null && token != usedToken) {
          return retry();
        }
        final fresh = await _attemptRelogin();
        if (fresh != null) {
          return retry();
        }
      }
      throw AppError(
        AppErrorKind.sessionExpired,
        message: allowRelogin ? '会话已过期，且自动重新登录失败' : '登录状态已失效',
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
          final decoded = jsonDecode(trimmed);
          if (decoded is Map) {
            return ApiResult.fromJson(decoded.cast<String, dynamic>());
          }
          return ApiResult(
              code: '1',
              msg: '',
              data: decoded,
              dataList: decoded is List ? decoded : const [],
              totalCount: 0);
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
    return ApiResult(
        code: '0', msg: 'empty', data: null, dataList: const [], totalCount: 0);
  }

  /// Whether a response means the session is gone.
  ///
  /// Verified 2026-09-18 against the live server: after a login elsewhere or
  /// a ~10 minute idle, authenticated endpoints answer HTTP 200 with
  /// `{"code":"302","msg":"未查询到登录信息"}`, while xkxf.do answers
  /// `code "2" 非法请求`. Public endpoints (batch.do, notice.do, sysparam.do)
  /// keep answering normally, which is why a request can look healthy while
  /// the session is dead. Only [auth] requests are classified here.
  bool _looksExpired(ApiResult r, Response resp) {
    if (r.keyExpired) return true;
    if (resp.statusCode == 401 || resp.statusCode == 403) return true;
    if (r.ok) return false;
    if (r.code == '302') return true;
    final m = r.msg;
    return m.contains('未查询到登录信息') ||
        m.contains('未登录') ||
        m.contains('登录信息') ||
        m.contains('重新登录') ||
        m.contains('token') ||
        m.contains('会话') ||
        m.contains('超时') ||
        m == '非法请求';
  }

  bool _htmlLooksLikeLogin(String html) {
    final h = html.toLowerCase();
    // Avoid bare 'cas' which false-matches English words like 'case'/'cascade'.
    return h.contains('login') ||
        h.contains('统一身份') ||
        h.contains('authserver') ||
        h.contains('/cas/') ||
        h.contains('pwdencryptsalt');
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

  /// Returns the sticky `route` cookie currently stored in this client's jar.
  Future<String?> currentRouteCookie() async {
    if (kIsWeb) return null;
    try {
      final cookies = await _cookieJar.loadForRequest(_cookieUri);
      for (final c in cookies) {
        if (c.name.toLowerCase() == 'route' && c.value.isNotEmpty) {
          return c.value;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Pins a specific load-balancer sticky `route` cookie in this client's jar.
  Future<void> setRouteCookie(String route) async {
    if (kIsWeb || route.isEmpty) return;
    final cookie = Cookie('route', route)..path = '/';
    await _cookieJar.saveFromResponse(_cookieUri, [cookie]);
  }

  /// Sends one cookieless `sysparam.do` probe to observe a backend node's
  /// `route` cookie and `initTimestamp` without touching this client's jar.
  Future<ClusterNodeProbe?> probeCookielessNode() async {
    if (kIsWeb || _closed) return null;
    final dio = _probeDio ??= () {
      final d = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 4),
        receiveTimeout: const Duration(seconds: 5),
        responseType: ResponseType.plain,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (compatible; nwafu-xk/1.0; +local) AppleWebKit/537.36',
          'X-Requested-With': 'XMLHttpRequest',
          'Cache-Control': 'no-cache',
        },
      ));
      CampusProxy.instance.attach(d);
      return d;
    }();
    try {
      final resp = await dio.get(
        _url(Api.sysParam),
        queryParameters: {'timestamp': nowStamp()},
      );
      final route = extractRouteCookie(resp.headers['set-cookie']);
      final parsed = _parse(resp);
      final ts = parsed.ok ? parseInitTimestamp(parsed.data) : null;
      if (route == null && ts == null) return null;
      return ClusterNodeProbe(route: route, initTimestamp: ts);
    } catch (_) {
      return null;
    }
  }

  /// Queries `sysparam.do` on this client's currently-pinned node to inspect
  /// its `initTimestamp`. Never throws; returns null when unavailable.
  Future<int?> fetchCurrentNodeInitTimestamp() async {
    if (!supportsClusterProbe && !kIsWeb) return null;
    try {
      final res = await getJson(
        Api.sysParam,
        auth: false,
        allowRelogin: false,
      );
      if (!res.ok) return null;
      final ts = parseInitTimestamp(res.data);
      recordClusterInitTimestamp(ts);
      return ts;
    } catch (_) {
      return null;
    }
  }

  /// Pins this client to a verified-fresh backend node in the cluster.
  ///
  /// NWAFU's `bksxk` deployment runs multiple Tomcat nodes behind nginx sticky
  /// `route` cookies; if any node fails to refresh its round cache, its
  /// `sysparam.do -> data.initTimestamp` lags behind the rest of the cluster
  /// and serves stale historical rounds until the `route` cookie is rotated.
  /// Probing a small batch of cookieless `sysparam.do` calls in parallel picks
  /// a node with the highest `initTimestamp` before login/context calls run.
  Future<ClusterNodeProbe?> pinFreshNode({
    bool forceRefresh = false,
    int probes = 3,
  }) async {
    if (kIsWeb) {
      if (forceRefresh && isFreshRouteBridgeReady) {
        _pendingBridgeRouteRefresh = true;
      }
      return null;
    }
    if (!supportsClusterProbe || _closed) return null;

    final knownMax = _highestInitTimestamps[_origin] ?? 0;
    if (!forceRefresh) {
      final cached = _freshNodes[_origin];
      if (cached != null &&
          DateTime.now().difference(cached.verifiedAt) < _freshNodeTtl &&
          cached.initTimestamp >= knownMax) {
        await setRouteCookie(cached.route);
        return ClusterNodeProbe(
          route: cached.route,
          initTimestamp: cached.initTimestamp,
        );
      }
      // Coalesce concurrent cold-start probes for the same origin.
      final inflight = _pinInFlight[_origin];
      if (inflight != null) {
        final shared = await inflight;
        if (shared != null && shared.route != null && shared.route!.isNotEmpty) {
          await setRouteCookie(shared.route!);
        }
        return shared;
      }
    }

    Future<ClusterNodeProbe?> runProbe() async {
      final excludedRoute = forceRefresh ? await currentRouteCookie() : null;
      final count = probes < 1 ? 1 : probes;
      final results = <ClusterNodeProbe>[
        for (final p in await Future.wait(
          List.generate(count, (_) => probeCookielessNode()),
        ))
          if (p != null) p,
      ];
      for (final p in results) {
        recordClusterInitTimestamp(p.initTimestamp);
      }

      // If every parallel probe landed on a lagging node compared to the
      // highest generation already known for this cluster, try a few more
      // cookieless probes to escape the zombie node.
      var targetMax = _highestInitTimestamps[_origin] ?? 0;
      bool hasFreshCandidate() => results.any(
            (p) =>
                p.route != null &&
                p.route!.isNotEmpty &&
                (p.initTimestamp ?? 0) >= targetMax &&
                (excludedRoute == null || p.route != excludedRoute),
          );
      for (var extra = 0; extra < 3 && targetMax > 0 && !hasFreshCandidate(); extra++) {
        final p = await probeCookielessNode();
        if (p == null) continue;
        results.add(p);
        recordClusterInitTimestamp(p.initTimestamp);
        targetMax = _highestInitTimestamps[_origin] ?? targetMax;
      }

      ClusterNodeProbe? best;
      for (final p in results) {
        final route = p.route;
        if (route == null || route.isEmpty) continue;
        if (best == null) {
          best = p;
          continue;
        }
        final bestTs = best.initTimestamp ?? 0;
        final curTs = p.initTimestamp ?? 0;
        if (curTs > bestTs) {
          best = p;
        } else if (curTs == bestTs &&
            excludedRoute != null &&
            best.route == excludedRoute &&
            route != excludedRoute) {
          best = p;
        }
      }

      if (best != null && best.route != null && best.route!.isNotEmpty) {
        await setRouteCookie(best.route!);
        _freshNodes[_origin] = _CachedFreshNode(
          route: best.route!,
          initTimestamp: best.initTimestamp ?? 0,
          verifiedAt: DateTime.now(),
        );
        return best;
      }
      return null;
    }

    if (forceRefresh) return runProbe();
    final future = runProbe();
    _pinInFlight[_origin] = future;
    try {
      return await future;
    } finally {
      if (identical(_pinInFlight[_origin], future)) {
        _pinInFlight.remove(_origin);
      }
    }
  }

  /// Closes the underlying HTTP client sockets when this scope is disposed.
  void close() {
    if (_closed) return;
    _closed = true;
    if (_usesDefaultTransport) _dio.close();
    _probeDio?.close();
    _probeDio = null;
  }

  /// Lightweight reachability probe for the diagnostics page. Hits a cheap
  /// public endpoint (batch list) and classifies the outcome. Never throws.
  Future<ReachabilityResult> probe() async {
    final start = DateTime.now();
    try {
      final resp = await _dio.get<String>(
        _url(Api.batch),
        queryParameters: {'timestamp': nowStamp()},
        options: Options(
          headers: _headers(auth: false),
          // Short timeout so the diagnostics page feels responsive.
          receiveTimeout: const Duration(seconds: 6),
        ),
      );
      final body = resp.data ?? '';
      if (body.contains('Not allowed to visit') || body.contains('禁止访问')) {
        final err = AppError(
          AppErrorKind.campusNetwork,
          message: '校园网关拒绝访问',
          hint: '当前网络可能处于校外或被限流，请确认校园网连接或开启内置校外访问。',
        );
        return ReachabilityResult(
          reachable: false,
          detail: err.message,
          error: err,
        );
      }
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
    } catch (e) {
      final err = AppError(
        AppErrorKind.unknown,
        message: '服务器地址无效或连接异常',
        hint: '请检查设置中的服务器地址是否正确。',
        raw: e,
      );
      return ReachabilityResult(
        reachable: false,
        detail: err.message,
        error: err,
      );
    }
  }
}
