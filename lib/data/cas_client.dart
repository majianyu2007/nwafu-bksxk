/// The NWAFU unified-identity (Wisedu/金智 AuthServer, CAS) client, a Dart
/// port of the flow in `wisedu_cas` (github.com/majianyu2007/wisedu_cas),
/// verified against authserver.nwafu.edu.cn on 2026-10-11:
///
///  1. GET `/authserver/login?service=<target>`. A 302 means the CASTGC cookie
///     is still valid; otherwise the page carries `execution` and
///     `pwdEncryptSalt`.
///  2. POST the form (AES password, see `cas_password.dart`) or a signed
///     passkey assertion (`cllt=fidoLogin`).
///  3. Follow redirects. A client without the year-long trusted-device cookie
///     `MULTIFACTOR_BROWSER_FINGERPRINT` lands on
///     `reAuthCheck/reAuthLoginView.do?isMultifactor=true`, which needs a
///     second factor ([CasMfaChallenge]); submitting with `skipTmpReAuth=true`
///     ("信任此设备") sets that cookie so later logins skip it.
///  4. The service URL gets `?ticket=ST-…`, which the target exchanges for its
///     own session cookie.
///
/// Cookies live in the [CookieJar] passed in; persist it to keep both the
/// login (CASTGC) and the trusted-device mark across restarts.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart';

import '../core/crypto/cas_password.dart';
import '../core/crypto/passkey.dart';
import '../core/crypto/webauthn_register.dart';
import '../core/errors.dart';
import '../core/web_env.dart';
import 'vpn/campus_proxy.dart';

const kAuthServer = 'https://authserver.nwafu.edu.cn';

/// A second-factor method the AuthServer offered for this login.
/// Synced with `nwafu-cas` 1.0.1 (`reAuth.js`).
enum MfaMethod {
  password('2', '认证密码'),
  sms('3', '短信验证码', needsSend: true),
  wecom('4', '企业微信验证码', needsSend: true),
  cpdaily('5', '今日校园验证码', needsSend: true),
  totp('10', '安全令牌（TOTP）'),
  email('11', '邮箱验证码', needsSend: true),
  dingtalk('12', '钉钉验证码', needsSend: true),
  welink('13', 'WeLink 验证码', needsSend: true),
  wechatService('15', '公众号验证码', needsSend: true),
  wechatScan('8', '微信扫码', supported: false),
  qrScan('14', '钉钉/企微/WeLink 扫码', supported: false),
  face('6', '实人认证（刷脸）', supported: false);

  const MfaMethod(
    this.code,
    this.label, {
    this.needsSend = false,
    this.supported = true,
  });
  final String code;
  final String label;

  /// Whether a code must be requested before it can be typed.
  final bool needsSend;

  /// Methods that only work in a browser (QR/face scans) are listed but disabled.
  final bool supported;

  String? get sendTypeName => switch (this) {
    sms => 'reAuthDynamicCodeType',
    wecom => 'reAuthWChatDynamicCodeType',
    cpdaily => 'reAuthCpdailyDynamicCodeType',
    email => 'reAuthEmailDynamicCodeType',
    dingtalk => 'reAuthDingTalkDynamicCodeType',
    welink => 'reAuthWeLinkDynamicCodeType',
    wechatService => 'reAuthWeChatServiceDynamicCodeType',
    _ => null,
  };

  static MfaMethod? byCode(String code) {
    final normalized = code.trim();
    if (normalized == '7') return password; // 安全问题 now falls back to password
    if (normalized == '18' ||
        normalized == '20' ||
        normalized.toUpperCase().startsWith('REAL_PERSON_PLUGIN_')) {
      return face;
    }
    for (final m in values) {
      if (m.code == normalized) return m;
    }
    return null;
  }
}

/// The multi-factor step of a login in progress. Hold on to it, let the user
/// pick a method, then [CasClient.sendMfaCode] / [CasClient.submitMfa].
class CasMfaChallenge {
  CasMfaChallenge({
    required this.service,
    required this.methods,
    required this.userId,
    required this.displayName,
    this.isMultifactor = 'true',
    this.asksTrust = true,
    this.salt = '',
  });

  /// The service the login was for; the ticket is issued for it afterwards.
  final String service;
  final List<MfaMethod> methods;

  /// `reAuthUserId` from the page; the SMS endpoint wants it.
  final String userId;
  final String displayName;
  final String isMultifactor;
  final bool asksTrust;
  final String salt;
}

/// Thrown by [CasClient.login] when a second factor is required.
class CasMfaRequired implements Exception {
  CasMfaRequired(this.challenge);
  final CasMfaChallenge challenge;
  @override
  String toString() => '需要二次验证';
}

class CasClient {
  CasClient({
    required CookieJar cookieJar,
    Dio? dio,
    this.random,
    this.webBridgeMode = kIsWeb,
    this.casLoginBridgeReady,
  })  : _jar = cookieJar,
        _ownsDio = dio == null {
    _dio =
        dio ??
        Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 12),
            receiveTimeout: const Duration(seconds: 30),
            responseType: ResponseType.plain,
            followRedirects: false,
            validateStatus: (s) => s != null && s < 500,
            headers: {
              if (!webBridgeMode)
                'User-Agent':
                    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
                    '(KHTML, like Gecko) Chrome/150.0 Safari/537.36',
            },
          ),
        );
    if (!webBridgeMode) {
      _dio.interceptors.add(CookieManager(_jar));
      if (dio == null) CampusProxy.instance.attach(_dio);
    }
  }

  late final Dio _dio;
  final bool _ownsDio;
  final CookieJar _jar;

  /// Source for the password/passkey nonces; tests pin it.
  final Random? random;

  /// True on Flutter web (or in unit tests simulating GM_xmlhttpRequest).
  final bool webBridgeMode;

  /// Optional test override for [isCasLoginBridgeReady].
  final bool? casLoginBridgeReady;

  bool get _casLoginBridgeReady => casLoginBridgeReady ?? isCasLoginBridgeReady;

  /// Closes the underlying HTTP client sockets if owned by this instance.
  void close({bool force = false}) {
    if (_ownsDio) _dio.close(force: force);
  }

  static final _captchaSwitchRe =
      RegExp(r'''\bvar\s+captchaSwitch\s*=\s*["']([^"']*)["']''');
  static final _formRe = RegExp(
    r'<form\b[^>]*>(.*?)</form>',
    caseSensitive: false,
    dotAll: true,
  );
  static final _inputRe = RegExp(r'<input\b([^>]*)>', caseSensitive: false);
  static final _attrRe = RegExp(
    r'''([\w:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')''',
    dotAll: true,
  );
  static final _mfaTagRe = RegExp(
    r'<[a-z]+\b[^>]*\b(?:reauth-tab-item|reauth-tab-more-item|changeReAuthTypes)\b[^>]*>',
    caseSensitive: false,
    dotAll: true,
  );
  static final _mfaUsernameRe = RegExp(r'id="username"[^>]*value="([^"]*)"');
  static final _valueAttrRe = RegExp(r'''\bvalue=["']([^"']*)["']''');

  static Map<String, String> _parseAttrs(String raw) {
    final attrs = <String, String>{};
    for (final am in _attrRe.allMatches(raw)) {
      attrs[am.group(1)!.toLowerCase()] = am.group(2) ?? am.group(3) ?? '';
    }
    return attrs;
  }

  /// Stable browser fingerprint for `/authserver/bfp/info` (信任此设备).
  late final String _fingerprint = _generateFingerprint(random);

  static String _generateFingerprint(Random? rng) {
    final r = rng ?? Random.secure();
    return List.generate(
      16,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Dio get dio => _dio;
  CookieJar get cookieJar => _jar;

  void _requireWebBridge() {
    if (!webBridgeMode) return;
    if (_casLoginBridgeReady) return;
    requireBrowserSessionBridge();
  }

  Future<void> _ensureFingerprint() async {
    try {
      if (!webBridgeMode) {
        final cookies = await _jar.loadForRequest(
          Uri.parse('$kAuthServer/authserver/login'),
        );
        if (cookies.any((c) => c.name == 'MULTIFACTOR_BROWSER_FINGERPRINT')) {
          return;
        }
      } else if (!_casLoginBridgeReady) {
        return;
      }
      await _dio.get<String>(
        '$kAuthServer/authserver/bfp/info',
        queryParameters: {
          'bfp': _fingerprint,
          '_': DateTime.now().millisecondsSinceEpoch,
        },
      );
    } catch (_) {
      // Best-effort fingerprint registration.
    }
  }

  static void requireSupportedPlatform({
    bool web = kIsWeb,
    bool? casLoginBridgeReady,
  }) {
    if (web && !(casLoginBridgeReady ?? isCasLoginBridgeReady)) {
      throw AppError(
        AppErrorKind.schemaOrRedirect,
        message: '请更新桥接脚本以使用站内统一身份认证',
        hint: '需要 1.5.0 或更新版本，更新后刷新本页面；也可暂时使用浏览器会话连接。',
      );
    }
  }

  static void requireBrowserSessionBridge() {
    if (!kIsWeb || !isEduSessionBridgeReady) {
      throw AppError(
        AppErrorKind.schemaOrRedirect,
        message: '请安装或更新教务会话桥接脚本',
        hint: '需要 1.3.0 或更新版本，更新后刷新本页面。',
      );
    }
  }

  /// Explicit sign-in must not silently reuse another account's CASTGC.
  /// Keep only the trusted-device marker; logout still removes everything.
  Future<void> clearSession() async {
    if (webBridgeMode) {
      if (_casLoginBridgeReady) {
        try {
          await _dio.get<String>('$kAuthServer/authserver/logout');
        } catch (_) {}
      }
      await _jar.deleteAll();
      return;
    }
    final uri = Uri.parse('$kAuthServer/authserver/login');
    final cookies = await _jar.loadForRequest(uri);
    final trusted = cookies
        .where((c) => c.name == 'MULTIFACTOR_BROWSER_FINGERPRINT')
        .toList();
    await _jar.deleteAll();
    if (trusted.isNotEmpty) await _jar.saveFromResponse(uri, trusted);
  }

  static bool _isAllowedUrl(Uri uri) =>
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      (!uri.hasPort || uri.port == 443) &&
      const {
        'authserver.nwafu.edu.cn',
        'ehall.nwafu.edu.cn',
        // 一网通办 (messages, to-dos); see portal_service.dart.
        'newehall.nwafu.edu.cn',
        // 图书馆空间预约; see library_service.dart.
        'booking-lib.nwafu.edu.cn',
      }.contains(uri.host);

  static void _validateUrl(Uri uri) {
    if (!_isAllowedUrl(uri)) {
      throw AppError(
        AppErrorKind.schemaOrRedirect,
        message: '统一身份认证返回了不安全的跳转地址',
      );
    }
  }

  static String loginUrl(String service) =>
      '$kAuthServer/authserver/login?service=${Uri.encodeComponent(service)}';

  /// Follows redirects by hand (cookies are stored at every hop) and returns
  /// the final response. [Response.realUri] is the last URL visited.
  Future<Response<String>> follow(String url, {int max = 12}) async {
    var current = Uri.parse(url);
    if (webBridgeMode) {
      _requireWebBridge();
      _validateUrl(current);
      final allowedWeb =
          (current.host == 'ehall.nwafu.edu.cn' &&
              (current.path.startsWith('/jwapp/') || current.path == '/login')) ||
          (current.host == 'newehall.nwafu.edu.cn' &&
              current.path == '/login') ||
          (current.host == 'booking-lib.nwafu.edu.cn' &&
              current.path == '/api/cas/cas') ||
          (_casLoginBridgeReady &&
              current.host == 'authserver.nwafu.edu.cn' &&
              current.path == '/authserver/login');
      if (!allowedWeb) {
        throw AppError(
          AppErrorKind.schemaOrRedirect,
          message: '网页版只能连接学校官方认证、教务、门户与图书馆应用',
        );
      }
      // GM follows redirects and carries browser cookies automatically.
      final res = await _guard(() => _dio.getUri<String>(current));
      final finalUrl = res.headers.value('x-bksxk-final-url');
      final finalUri = finalUrl == null ? null : Uri.tryParse(finalUrl);
      if (finalUri == null) {
        throw AppError(
          AppErrorKind.schemaOrRedirect,
          message: '教务桥接未返回会话跳转信息',
          hint: '请更新桥接脚本并刷新页面。',
        );
      }
      _validateUrl(finalUri);
      return _withUri(res, finalUri);
    }
    for (var i = 0; i < max; i++) {
      _validateUrl(current);
      final res = await _guard(() => _dio.getUri<String>(current));
      final loc = res.headers.value('location');
      if (!_isRedirect(res.statusCode) || loc == null || loc.isEmpty) {
        return _withUri(res, current);
      }
      current = current.resolve(loc);
    }
    throw AppError(AppErrorKind.unknown, message: '统一身份认证重定向次数过多');
  }

  /// True when the AuthServer still holds a valid login for this client.
  Future<bool> hasLogin(String service) async {
    if (webBridgeMode) {
      final res = await follow(service);
      final target = Uri.parse(service);
      return res.realUri.host == target.host &&
          res.realUri.path == target.path &&
          (res.statusCode ?? 500) < 400;
    }
    final res = await _guard(() => _dio.get<String>(loginUrl(service)));
    final loc = res.headers.value('location') ?? '';
    return _isRedirect(res.statusCode) &&
        !loc.contains('/authserver/login') &&
        !loc.contains('/reAuthCheck/');
  }

  /// Signs in with a password, or with [passkey] when given. Returns once
  /// the AuthServer has issued a ticket for [service] (already exchanged by
  /// following the redirect). Throws [CasMfaRequired] when a second factor
  /// is needed, or an [AppError].
  Future<void> login({
    required String service,
    required String username,
    String password = '',
    PasskeyCredential? passkey,
  }) async {
    requireSupportedPlatform(
      web: webBridgeMode,
      casLoginBridgeReady: _casLoginBridgeReady,
    );
    _validateUrl(Uri.parse(service));
    if (passkey != null &&
        (!passkey.isComplete || passkey.rpId != Uri.parse(kAuthServer).host)) {
      throw AppError(AppErrorKind.account, message: '通行密钥不属于西农统一身份认证或信息不完整');
    }
    final page = await _guard(() => _dio.get<String>(loginUrl(service)));
    if (webBridgeMode) {
      final finalUrl = page.headers.value('x-bksxk-final-url');
      final finalUri = finalUrl == null ? null : Uri.tryParse(finalUrl);
      if (finalUri != null &&
          !(finalUri.host == Uri.parse(kAuthServer).host &&
              finalUri.path == '/authserver/login')) {
        // Existing CASTGC: GM already followed the redirect to the service or MFA.
        await _afterWebLogin(page, service);
        return;
      }
    } else if (_isRedirect(page.statusCode)) {
      // Existing CASTGC: the AuthServer goes straight to the ticket.
      await _afterLogin(page, service);
      return;
    }
    final html = page.data ?? '';
    final execution = _inputValue(html, 'execution');
    if (execution == null) {
      throw AppError(
        AppErrorKind.unknown,
        message: '统一身份认证页面结构已变化',
        hint: '无法读取登录表单，请到浏览器登录或更新应用。',
      );
    }

    final Response<String> res;
    if (passkey != null) {
      final fidoFields = _parseFormFields(html, 'fidoLogin');
      res = await _passkeyLogin(
        service,
        username,
        execution,
        passkey,
        formFields: fidoFields,
      );
    } else {
      await _checkNeedCaptcha(username, html);
      final salt = _inputValue(html, 'pwdEncryptSalt');
      if (salt == null || salt.length != 16) {
        throw AppError(
          AppErrorKind.schemaOrRedirect,
          message: '统一身份认证加密参数缺失',
          hint: '未发送密码，请更新应用或使用官方登录页。',
        );
      }
      final baseFields = _parseFormFields(html, 'userNameLogin');
      baseFields.remove('passwordText');
      final formData = <String, String>{
        '_eventId': 'submit',
        'cllt': 'userNameLogin',
        'dllt': 'generalLogin',
        'lt': '',
        'execution': execution,
        ...baseFields,
        'username': username,
        'password': encryptCasPassword(password, salt, random: random),
        'rememberMe': 'true',
      };
      formData.putIfAbsent('captcha', () => '');
      res = await _guard(
        () => _dio.post<String>(
          loginUrl(service),
          data: formData,
          options: Options(contentType: Headers.formUrlEncodedContentType),
        ),
      );
    }
    if (webBridgeMode) {
      await _afterWebLogin(res, service);
      return;
    }
    if (!_isRedirect(res.statusCode)) {
      throw classifyLoginFailure(res.data ?? '');
    }
    await _afterLogin(res, service);
  }

  Future<void> _checkNeedCaptcha(String username, String html) async {
    try {
      final res = await _dio.get<String>(
        '$kAuthServer/authserver/checkNeedCaptcha.htl',
        queryParameters: {
          'username': username,
          '_': DateTime.now().millisecondsSinceEpoch,
        },
      );
      final j = _json(res.data);
      if (j['isNeed'] == true) {
        final sw = _captchaSwitchRe.firstMatch(html)?[1];
        final kind = sw == '2' ? '滑块验证' : '图形验证码';
        throw AppError(
          AppErrorKind.captcha,
          message: '学校要求$kind',
          hint: '失败次数较多时会出现；请先在浏览器里成功登录一次，或过一段时间再试。',
        );
      }
    } on AppError {
      rethrow;
    } catch (_) {
      // Optional pre-check; proceed if the endpoint is unavailable.
    }
  }

  static Map<String, String> _parseFormFields(String html, String cllt) {
    for (final fm in _formRe.allMatches(html)) {
      final body = fm.group(1) ?? '';
      final fields = <String, String>{};
      for (final im in _inputRe.allMatches(body)) {
        final rawAttrs = im.group(1) ?? '';
        final attrs = _parseAttrs(rawAttrs);
        final type = attrs['type']?.toLowerCase();
        if ((type == 'checkbox' || type == 'radio') &&
            !rawAttrs.toLowerCase().contains('checked')) {
          continue;
        }
        final name = attrs['name'];
        if (name != null && name.isNotEmpty) {
          fields.putIfAbsent(name, () => attrs['value'] ?? '');
        }
      }
      if (fields['cllt'] == cllt) return fields;
    }
    return {};
  }

  Future<Response<String>> _passkeyLogin(
    String service,
    String username,
    String execution,
    PasskeyCredential passkey, {
    Map<String, String> formFields = const {},
  }) async {
    final userId = base64.encode(utf8.encode(username));
    final start = await _guard(
      () => _dio.post<String>(
        '$kAuthServer/authserver/startAssertion',
        data: jsonEncode({'userId': userId, 'id': passkey.deviceBindingId}),
        options: Options(contentType: 'application/json;charset=utf-8'),
      ),
    );
    Map<String, dynamic> result;
    try {
      final decoded = jsonDecode(start.data ?? '');
      final rawResult = decoded is Map ? decoded['result'] : null;
      result = rawResult is Map
          ? rawResult.cast<String, dynamic>()
          : const {};
    } catch (_) {
      result = const {};
    }
    final rawReq = result['request'];
    final request = rawReq is Map ? rawReq.cast<String, dynamic>() : null;
    final rawOpts = request?['publicKeyCredentialRequestOptions'];
    final options = rawOpts is Map ? rawOpts.cast<String, dynamic>() : null;
    final challenge = options?['challenge']?.toString() ?? '';
    final requestId = request?['requestId']?.toString() ?? '';
    if (result['success'] != true || challenge.isEmpty || requestId.isEmpty) {
      throw AppError(
        AppErrorKind.account,
        message: '通行密钥未被服务器认可',
        hint: '该设备的生物识别绑定可能已被删除，请在个人中心重新绑定或改用密码登录。',
      );
    }
    if (options?['rpId'] != passkey.rpId) {
      throw AppError(AppErrorKind.schemaOrRedirect, message: '通行密钥认证域名不匹配');
    }
    final Map<String, dynamic> assertion;
    try {
      assertion = buildPasskeyAssertion(
        credential: passkey,
        challenge: challenge,
        origin: kAuthServer,
        random: random,
      );
    } catch (_) {
      throw AppError(AppErrorKind.account, message: '通行密钥私钥格式无效');
    }
    final sessionToken = request?['sessionToken'];
    return _guard(
      () => _dio.post<String>(
        loginUrl(service),
        data: {
          '_eventId': 'submit',
          'cllt': 'fidoLogin',
          'dllt': 'generalLogin',
          'lt': '',
          'execution': execution,
          ...formFields,
          'username': userId,
          'responseJson': jsonEncode({
            'requestId': requestId,
            'credential': assertion,
            'sessionToken': sessionToken,
          }),
          'rememberMe': 'true',
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      ),
    );
  }

  Future<void> _afterLogin(Response<String> res, String service) async {
    final loc = res.headers.value('location') ?? '';
    final last = await follow(
      Uri.parse(loginUrl(service)).resolve(loc).toString(),
    );
    final url = last.realUri.toString();
    if (url.contains('/reAuthCheck/reAuthLoginView.do')) {
      throw CasMfaRequired(
        _parseMfaPage(last.data ?? '', service, pageUri: last.realUri),
      );
    }
    if (url.contains('/authserver/login')) {
      throw classifyLoginFailure(last.data ?? '');
    }
    _requireService(last, service);
  }

  Future<void> _afterWebLogin(Response<String> res, String service) async {
    final finalUrl = res.headers.value('x-bksxk-final-url') ?? '';
    final finalUri = Uri.tryParse(finalUrl);
    if (finalUri == null) {
      throw AppError(
        AppErrorKind.schemaOrRedirect,
        message: '教务桥接未返回登录跳转信息',
        hint: '请更新桥接脚本至 1.5.0 或以上版本后刷新页面。',
      );
    }
    _validateUrl(finalUri);
    final wrapped = _withUri(res, finalUri);
    final url = finalUri.toString();
    if (url.contains('/reAuthCheck/reAuthLoginView.do')) {
      throw CasMfaRequired(
        _parseMfaPage(res.data ?? '', service, pageUri: finalUri),
      );
    }
    if (url.contains('/authserver/login')) {
      throw classifyLoginFailure(res.data ?? '');
    }
    _requireService(wrapped, service);
  }

  CasMfaChallenge _parseMfaPage(String html, String service, {Uri? pageUri}) {
    final methods = <MfaMethod>[];
    for (final m in _mfaTagRe.allMatches(html)) {
      final attrs = _parseAttrs(m.group(0)!);
      var code = attrs['data-type'] ?? attrs['id'] ?? '';
      if (code.startsWith('tab_')) code = code.substring(4);
      final method = MfaMethod.byCode(code);
      if (method != null && !methods.contains(method)) methods.add(method);
    }
    final reAuthParams = parseJsObject(html, 'reAuthParams');
    final fallbackParams = reAuthParams.isEmpty
        ? _parseLooseJsStringParams(html)
        : const <String, String>{};
    String param(String key) {
      final raw = reAuthParams.containsKey(key)
          ? reAuthParams[key]
          : fallbackParams[key];
      if (raw == null) return '';
      if (raw is bool) return raw ? 'true' : 'false';
      return raw.toString();
    }

    if (methods.isEmpty) {
      final current = MfaMethod.byCode(param('reAuthType'));
      if (current != null) methods.add(current);
    }
    if (methods.isEmpty) {
      throw AppError(
        AppErrorKind.schemaOrRedirect,
        message: '无法读取学校提供的二次验证方式',
        hint: '请使用官方认证页面登录。',
      );
    }
    final name = _mfaUsernameRe.firstMatch(html)?[1];
    final isMultifactor = param('isMultifactor');
    final isSleepAccount = param('isSleepAccount');
    final resolvedService =
        normalizeCasServiceUrl(param('service')) ??
        normalizeCasServiceUrl(pageUri?.queryParameters['service']) ??
        service;
    return CasMfaChallenge(
      service: resolvedService,
      methods: methods,
      userId: param('reAuthUserId'),
      displayName: name ?? '',
      isMultifactor: isMultifactor.isEmpty ? 'true' : isMultifactor,
      asksTrust: isSleepAccount.isEmpty || isSleepAccount == '0',
      salt: param('pwdEncryptSalt'),
    );
  }

  /// Normalizes a CAS `service` URL parsed from HTML/JS, rejecting corrupt
  /// escapes or non-campus hosts so we never post an unregistered URL.
  @visibleForTesting
  static String? normalizeCasServiceUrl(String? raw) {
    if (raw == null) return null;
    var s = raw.trim();
    if (s.isEmpty) return null;
    s = s.replaceAll('&amp;', '&');
    if (RegExp(r'^https?%3A%2F%2F', caseSensitive: false).hasMatch(s)) {
      try {
        s = Uri.decodeComponent(s);
      } catch (_) {
        return null;
      }
    }
    if (s.contains(r'\')) return null;
    final uri = Uri.tryParse(s);
    if (uri == null || !_isAllowedUrl(uri)) return null;
    return s;
  }

  /// Extracts a JS object literal assigned to [name] (e.g. `reAuthParams = {...}`)
  /// and decodes JS/Thymeleaf string escapes (`\/`, `\u0026`, `\'`, etc.).
  @visibleForTesting
  static Map<String, dynamic> parseJsObject(String src, String name) {
    final block = _extractJsObjectBlock(src, name);
    if (block == null) return const {};
    try {
      final decoded = jsonDecode(block);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // Fall through to JS-syntax parser (handles \' escapes, unquoted keys,
      // single-quoted strings, comments, trailing commas, undefined).
    }
    return _parseJsObjectLiteral(block);
  }

  static String? _extractJsObjectBlock(String src, String name) {
    final m = RegExp('\\b${RegExp.escape(name)}\\s*=\\s*\\{').firstMatch(src);
    if (m == null) return null;
    final start = m.end - 1;
    var depth = 0;
    var i = start;
    while (i < src.length) {
      final ch = src[i];
      if (ch == '"' || ch == "'") {
        i = _scanJsStringEnd(src, i);
        continue;
      }
      if (ch == '/' && i + 1 < src.length) {
        final next = src[i + 1];
        if (next == '/') {
          final nl = src.indexOf('\n', i + 2);
          i = nl < 0 ? src.length : nl + 1;
          continue;
        }
        if (next == '*') {
          final end = src.indexOf('*/', i + 2);
          i = end < 0 ? src.length : end + 2;
          continue;
        }
      }
      if (ch == '{') {
        depth++;
      } else if (ch == '}') {
        depth--;
        if (depth == 0) return src.substring(start, i + 1);
      }
      i++;
    }
    return null;
  }

  static int _scanJsStringEnd(String src, int start) {
    final quote = src[start];
    var i = start + 1;
    while (i < src.length) {
      final ch = src[i];
      if (ch == r'\') {
        i += 2;
        continue;
      }
      if (ch == quote) return i + 1;
      i++;
    }
    return src.length;
  }

  static int _skipJsSpaceAndComments(String src, int i) {
    while (i < src.length) {
      final code = src.codeUnitAt(i);
      if (code <= 0x20 || code == 0xFEFF) {
        i++;
        continue;
      }
      if (code == 0x2F /* / */ && i + 1 < src.length) {
        final next = src.codeUnitAt(i + 1);
        if (next == 0x2F /* / */ ) {
          final nl = src.indexOf('\n', i + 2);
          i = nl < 0 ? src.length : nl + 1;
          continue;
        }
        if (next == 0x2A /* * */ ) {
          final end = src.indexOf('*/', i + 2);
          i = end < 0 ? src.length : end + 2;
          continue;
        }
      }
      break;
    }
    return i;
  }

  static int _scanJsBalancedEnd(String src, int start, String open, String close) {
    var depth = 0;
    var i = start;
    while (i < src.length) {
      final ch = src[i];
      if (ch == '"' || ch == "'") {
        i = _scanJsStringEnd(src, i);
        continue;
      }
      if (ch == '/' && i + 1 < src.length) {
        final next = src[i + 1];
        if (next == '/') {
          final nl = src.indexOf('\n', i + 2);
          i = nl < 0 ? src.length : nl + 1;
          continue;
        }
        if (next == '*') {
          final end = src.indexOf('*/', i + 2);
          i = end < 0 ? src.length : end + 2;
          continue;
        }
      }
      if (ch == open) {
        depth++;
      } else if (ch == close) {
        depth--;
        if (depth == 0) return i + 1;
      }
      i++;
    }
    return src.length;
  }

  static Map<String, dynamic> _parseJsObjectLiteral(String block) {
    final result = <String, dynamic>{};
    var i = _skipJsSpaceAndComments(block, 0);
    if (i >= block.length || block[i] != '{') return result;
    i++;
    while (i < block.length) {
      i = _skipJsSpaceAndComments(block, i);
      if (i >= block.length || block[i] == '}') break;
      if (block[i] == ',') {
        i++;
        continue;
      }
      String? key;
      if (block[i] == '"' || block[i] == "'") {
        final quote = block[i];
        final end = _scanJsStringEnd(block, i);
        if (end <= i + 1 || block[end - 1] != quote) break;
        key = unescapeJsString(block.substring(i + 1, end - 1));
        i = end;
      } else {
        final keyStart = i;
        while (i < block.length && _isJsIdentChar(block.codeUnitAt(i))) {
          i++;
        }
        if (i == keyStart) {
          i++;
          continue;
        }
        key = block.substring(keyStart, i);
      }
      i = _skipJsSpaceAndComments(block, i);
      if (i >= block.length || block[i] != ':') {
        while (i < block.length && block[i] != ',' && block[i] != '}') {
          i++;
        }
        continue;
      }
      i = _skipJsSpaceAndComments(block, i + 1);
      if (i >= block.length) break;
      final ch = block[i];
      if (ch == '"' || ch == "'") {
        final end = _scanJsStringEnd(block, i);
        if (end > i + 1 && block[end - 1] == ch) {
          result[key] = unescapeJsString(block.substring(i + 1, end - 1));
        }
        i = end;
      } else if (ch == '{') {
        i = _scanJsBalancedEnd(block, i, '{', '}');
      } else if (ch == '[') {
        i = _scanJsBalancedEnd(block, i, '[', ']');
      } else {
        final valStart = i;
        while (i < block.length && block[i] != ',' && block[i] != '}') {
          if (block[i] == '"' || block[i] == "'") {
            i = _scanJsStringEnd(block, i);
            continue;
          }
          if (block[i] == '/' &&
              i + 1 < block.length &&
              (block[i + 1] == '/' || block[i + 1] == '*')) {
            break;
          }
          i++;
        }
        final token = block.substring(valStart, i).trim();
        if (token == 'true') {
          result[key] = true;
        } else if (token == 'false') {
          result[key] = false;
        } else if (token == 'null' || token == 'undefined') {
          result[key] = null;
        } else {
          final numVal = num.tryParse(token);
          if (numVal != null) result[key] = numVal;
        }
      }
    }
    return result;
  }

  static bool _isJsIdentChar(int c) =>
      (c >= 0x30 && c <= 0x39) ||
      (c >= 0x41 && c <= 0x5A) ||
      (c >= 0x61 && c <= 0x7A) ||
      c == 0x5F /* _ */ ||
      c == 0x24 /* $ */;

  static final _looseJsParamRe = RegExp(
    r'''(?:["'](\w+)["']|\b(\w+))\s*:\s*(?:"((?:\\.|[^"\\])*)"|'((?:\\.|[^'\\])*)')''',
  );

  static Map<String, String> _parseLooseJsStringParams(String html) {
    final result = <String, String>{};
    for (final m in _looseJsParamRe.allMatches(html)) {
      final key = m.group(1) ?? m.group(2);
      final raw = m.group(3) ?? m.group(4);
      if (key != null && raw != null && !result.containsKey(key)) {
        result[key] = unescapeJsString(raw);
      }
    }
    return result;
  }

  @visibleForTesting
  static String unescapeJsString(String raw) {
    if (!raw.contains(r'\')) return raw;
    final out = StringBuffer();
    for (var i = 0; i < raw.length; i++) {
      final ch = raw[i];
      if (ch != r'\' || i + 1 >= raw.length) {
        out.write(ch);
        continue;
      }
      final next = raw[++i];
      switch (next) {
        case '/':
          out.write('/');
        case r'\':
          out.write(r'\');
        case '"':
          out.write('"');
        case "'":
          out.write("'");
        case 'n':
          out.write('\n');
        case 'r':
          out.write('\r');
        case 't':
          out.write('\t');
        case 'b':
          out.write('\b');
        case 'f':
          out.write('\f');
        case 'v':
          out.write('\v');
        case '0':
          out.writeCharCode(0);
        case '\r':
          if (i + 1 < raw.length && raw[i + 1] == '\n') i++;
        case '\n':
          break;
        case 'u':
          if (i + 1 < raw.length && raw[i + 1] == '{') {
            final close = raw.indexOf('}', i + 2);
            if (close > i + 2) {
              final cp = int.tryParse(raw.substring(i + 2, close), radix: 16);
              if (cp != null && cp >= 0 && cp <= 0x10FFFF) {
                out.writeCharCode(cp);
                i = close;
                break;
              }
            }
          } else if (i + 4 < raw.length) {
            final cp = int.tryParse(raw.substring(i + 1, i + 5), radix: 16);
            if (cp != null) {
              out.writeCharCode(cp);
              i += 4;
              break;
            }
          }
          out.write('u');
        case 'x':
          if (i + 2 < raw.length) {
            final cp = int.tryParse(raw.substring(i + 1, i + 3), radix: 16);
            if (cp != null) {
              out.writeCharCode(cp);
              i += 2;
              break;
            }
          }
          out.write('x');
        default:
          out.write(next);
      }
    }
    return out.toString();
  }

  /// Switches the MFA page to [method]; the server wants this before a code
  /// can be sent or submitted.
  void _checkMfaMethod(CasMfaChallenge c, MfaMethod method) {
    if (!method.supported || !c.methods.contains(method)) {
      throw AppError(AppErrorKind.account, message: '该二次验证方式不可用');
    }
  }

  Future<void> selectMfaMethod(CasMfaChallenge c, MfaMethod method) async {
    _checkMfaMethod(c, method);
    final res = await _guard(
      () => _dio.post<String>(
        '$kAuthServer/authserver/reAuthCheck/changeReAuthType.do',
        data: {
          'isMultifactor': c.isMultifactor,
          'reAuthType': method.code,
          'service': c.service,
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      ),
    );
    final j = _json(res.data);
    if (j['code']?.toString() != '1') {
      throw AppError(
        AppErrorKind.account,
        message: j['message']?.toString() ?? '无法切换验证方式',
      );
    }
    final data = j['data'];
    if (method == MfaMethod.totp &&
        data is Map &&
        data['otpIsBind'] == false) {
      throw AppError(
        AppErrorKind.account,
        message: '该账号尚未绑定安全令牌（OTP）',
        hint: '请先在浏览器二次认证页面扫码绑定“数盾OTP”，或改用其他验证方式。',
      );
    }
  }

  /// Sends a dynamic verification code (SMS, 企业微信, 今日校园, 邮箱, 钉钉,
  /// WeLink, 公众号). Returns the server's message.
  Future<String> sendMfaCode(CasMfaChallenge c, MfaMethod method) async {
    _checkMfaMethod(c, method);
    if (!method.needsSend || c.userId.isEmpty) {
      throw AppError(AppErrorKind.account, message: '无法为该验证方式发送验证码');
    }
    await selectMfaMethod(c, method);
    final res = await _guard(
      () => _dio.post<String>(
        '$kAuthServer/authserver/dynamicCode/getDynamicCodeByReauth.do',
        data: {'userName': c.userId, 'authCodeTypeName': method.sendTypeName},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      ),
    );
    final j = _json(res.data);
    final msg = '${j['returnMessage'] ?? ''}${j['mobile'] ?? ''}';
    final ok = const {
      'success',
      'wechat_success',
      'cpdaily_success',
      'other_success',
    }.contains(j['res']?.toString());
    if (!ok) {
      throw AppError(
        AppErrorKind.account,
        message: msg.isEmpty ? '验证码发送失败' : msg,
        retryable: true,
      );
    }
    return msg.isEmpty ? '验证码已发送' : msg;
  }

  /// Submits the second factor and, on success, completes the login for
  /// [CasMfaChallenge.service]. [trustDevice] = 信任此设备 (no MFA for a year).
  Future<void> submitMfa(
    CasMfaChallenge c,
    MfaMethod method,
    String code, {
    bool trustDevice = true,
  }) async {
    _checkMfaMethod(c, method);
    final value = method == MfaMethod.password ? code : code.trim();
    if (value.isEmpty) {
      throw AppError(
        AppErrorKind.captcha,
        message: method == MfaMethod.password ? '请输入认证密码' : '请输入二次验证码',
      );
    }
    if (method == MfaMethod.totp && value.length != 6) {
      throw AppError(AppErrorKind.captcha, message: '安全令牌需要 6 位数字');
    }
    String encryptedPassword = '';
    if (method == MfaMethod.password) {
      final salt = c.salt.trim();
      if (salt.isNotEmpty) {
        final keyLen = utf8.encode(salt).length;
        if (keyLen != 16 && keyLen != 24 && keyLen != 32) {
          throw AppError(
            AppErrorKind.schemaOrRedirect,
            message: '二次认证加密参数异常（未发送密码）',
            hint: '请重新登录或使用官方认证页面。',
          );
        }
        encryptedPassword = encryptCasPassword(value, salt, random: random);
      } else {
        encryptedPassword = value;
      }
    }
    if (method == MfaMethod.totp || method == MfaMethod.password) {
      await selectMfaMethod(c, method);
    }
    await _ensureFingerprint();
    final data = <String, String>{
      'service': c.service,
      'reAuthType': method == MfaMethod.password ? '2' : method.code,
      'isMultifactor': c.isMultifactor,
      'password': encryptedPassword,
      'dynamicCode': method.needsSend ? value : '',
      'uuid': '',
      'answer1': '',
      'answer2': '',
      'otpCode': method == MfaMethod.totp ? value : '',
    };
    if (c.asksTrust) {
      data['skipTmpReAuth'] = trustDevice ? 'true' : 'false';
    }
    final res = await _guard(
      () => _dio.post<String>(
        '$kAuthServer/authserver/reAuthCheck/reAuthSubmit.do',
        data: data,
        options: Options(contentType: Headers.formUrlEncodedContentType),
      ),
    );
    if (_isRedirect(res.statusCode)) {
      throw AppError(
        AppErrorKind.sessionExpired,
        message: '二次验证会话已过期',
        hint: '请重新登录。',
      );
    }
    final j = _json(res.data);
    if (j.isEmpty) {
      final tip = _extractCasErrorTip(res.data ?? '');
      if (tip.isNotEmpty) {
        throw classifyLoginFailure(res.data ?? '');
      }
      throw AppError(
        AppErrorKind.sessionExpired,
        message: '二次验证提交响应异常',
        hint: '请重新登录。',
      );
    }
    if (j['code']?.toString() != 'reAuth_success') {
      final msg = j['msg']?.toString().trim() ?? '';
      if (msg.contains('未注册') || msg.contains('无权访问')) {
        throw AppError(
          AppErrorKind.schemaOrRedirect,
          message: msg,
          hint: '认证服务未认可目标应用地址，请更新应用或使用官方页面登录。',
        );
      }
      throw AppError(
        AppErrorKind.captcha,
        message: msg.isNotEmpty ? msg : '验证码错误',
        hint: '检查验证码后重试；安全令牌请确认手机时间准确。',
      );
    }
    final last = await follow(loginUrl(c.service));
    if (last.realUri.toString().contains('/authserver/')) {
      final html = last.data ?? '';
      if (_extractCasErrorTip(html).isNotEmpty) {
        throw classifyLoginFailure(html);
      }
      throw AppError(
        AppErrorKind.sessionExpired,
        message: '二次验证后未能完成登录',
        hint: '请重新登录。',
      );
    }
    _requireService(last, c.service);
  }

  void _requireService(Response<String> response, String service) {
    final target = Uri.parse(service);
    final uri = response.realUri;
    if (uri.origin != target.origin ||
        uri.path != target.path ||
        response.statusCode == null ||
        response.statusCode! >= 400) {
      throw AppError(
        AppErrorKind.sessionExpired,
        message: '统一身份认证未完成服务登录',
        hint: '请重新登录。',
      );
    }
  }

  // -------------------------------------------------------------------------
  // 个人中心 → 生物识别: bind this app as a passkey device.
  //
  // The personal centre (`/personalInfo/personCenter/`) is a CAS service like
  // any other; its JSON API wants `X-Requested-With`, the `XSRF-TOKEN` cookie
  // echoed as `X-XSRF-TOKEN`, and a random `n` in every body. Adding or
  // deleting a device may first need a password re-check
  // (`common/isUserRecheckNecessary` → `common/reCheckPwd` with the password
  // AES-encrypted under the `WIS_PER_ENC` cookie, plus an image captcha).
  // -------------------------------------------------------------------------

  static const _pcBase = '$kAuthServer/personalInfo';
  static const personalCenterService =
      '$kAuthServer/personalInfo/personCenter/index.html';

  /// Opens a personal-centre session (needs a live CASTGC).
  Future<void> openPersonalCenter() async {
    final last = await follow(loginUrl(personalCenterService));
    final uri = last.realUri;
    if (!uri.path.startsWith('/personalInfo/') ||
        (last.statusCode ?? 500) >= 400) {
      throw AppError(
        AppErrorKind.sessionExpired,
        message: '无法进入统一身份认证个人中心',
        hint: '请先用密码登录一次。',
      );
    }
  }

  Future<String?> _cookie(String name) async {
    final cookies = await _jar.loadForRequest(Uri.parse('$_pcBase/'));
    for (final c in cookies) {
      if (c.name == name) return c.value;
    }
    return null;
  }

  Future<Map<String, dynamic>> _pcPost(
    String path, [
    Map<String, dynamic> body = const {},
  ]) async {
    final xsrf = await _cookie('XSRF-TOKEN');
    final referer = await _cookie('REFERERCE_TOKEN');
    final res = await _guard(
      () => _dio.post<String>(
        '$_pcBase$path',
        data: jsonEncode({...body, 'n': '${Random.secure().nextDouble()}'}),
        options: Options(
          contentType: 'application/json',
          headers: {
            'Accept': 'application/json',
            'X-Requested-With': 'XMLHttpRequest',
            'xsrf-token': ?xsrf,
            'X-XSRF-TOKEN': ?xsrf,
            'refererToken': ?referer,
            'Referer': personalCenterService,
          },
        ),
      ),
    );
    final j = _json(res.data);
    if (j.isEmpty) {
      throw AppError(
        AppErrorKind.sessionExpired,
        message: '个人中心会话已失效',
        hint: '请重新登录后再试。',
      );
    }
    return j;
  }

  Future<Map<String, dynamic>> _pcGet(String path) async {
    final res = await _guard(
      () => _dio.get<String>(
        '$_pcBase$path',
        options: Options(headers: {
          'Accept': 'application/json',
          'X-Requested-With': 'XMLHttpRequest',
        }),
      ),
    );
    return _json(res.data);
  }

  /// Whether adding/removing a device needs a password re-check first.
  Future<bool> personalCenterNeedsRecheck() async {
    final j = await _pcGet('/common/isUserRecheckNecessary');
    return j['code']?.toString() != '0';
  }

  /// The re-check captcha image (PNG bytes).
  Future<Uint8List> recheckCaptcha() async {
    _requireWebBridge();
    try {
      final res = await _dio.get<List<int>>(
        '$_pcBase/captcha/checkCode?data=${DateTime.now().millisecondsSinceEpoch}',
        options: Options(responseType: ResponseType.bytes),
      );
      final data = res.data ?? const <int>[];
      if ((res.statusCode ?? 0) != 200 || data.isEmpty) {
        throw AppError(
          AppErrorKind.schemaOrRedirect,
          message: '获取安全校验验证码失败',
          hint: '请稍后重试。',
        );
      }
      return data is Uint8List ? data : Uint8List.fromList(data);
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  /// Re-checks the password (with the captcha from [recheckCaptcha]).
  Future<void> recheckPassword(String password, String captcha) async {
    final key = (await _cookie('WIS_PER_ENC') ?? '').trim();
    final keyLen = utf8.encode(key).length;
    if (keyLen != 16 && keyLen != 24 && keyLen != 32) {
      throw AppError(
        AppErrorKind.schemaOrRedirect,
        message: '个人中心会话缺少加密密钥（未发送密码）',
        hint: '请重新进入个人中心后再试。',
      );
    }
    final j = await _pcPost('/common/reCheckPwd', {
      'captcha': captcha.trim(),
      'password': encryptCasPassword(password, key, random: random),
    });
    final code = j['code']?.toString();
    if (code == '0') return;
    throw AppError(
      code == '2106010003' ? AppErrorKind.captcha : AppErrorKind.account,
      message: j['message']?.toString() ?? '身份校验失败',
    );
  }

  /// Registers a new passkey for this app. [deviceName] is what the personal
  /// centre lists. Returns the credential to keep in secure storage.
  Future<PasskeyCredential> registerDevicePasskey(
    String deviceName, {
    AttestationFormat format = AttestationFormat.none,
  }) async {
    final start = await _pcPost('/accountSecurity/startRegister');
    if (start['code']?.toString() != '0') {
      throw AppError(
        AppErrorKind.account,
        message: start['message']?.toString() ?? '学校未允许绑定新设备',
      );
    }
    final startDatas = start['datas'];
    final request = startDatas is Map ? startDatas['request'] : null;
    final options = request is Map
        ? request['publicKeyCredentialCreationOptions']
        : null;
    if (request is! Map || options is! Map) {
      throw AppError(
        AppErrorKind.account,
        message: start['message']?.toString() ?? '学校未允许绑定新设备',
      );
    }
    final reg = buildRegistrationCredential(
      options: options.cast<String, dynamic>(),
      origin: kAuthServer,
      format: format,
      random: random,
    );
    final finish = await _pcPost('/accountSecurity/finishRegister', {
      'deviceName': deviceName,
      'anonbiometricsd': null,
      'response': jsonEncode({
        'requestId': request['requestId'],
        'credential': reg.response,
        'sessionToken': request['sessionToken'],
      }),
    });
    final datas = finish['datas'];
    final deviceId = datas is Map ? datas['anonbiometricsd']?.toString() : null;
    if (finish['code']?.toString() != '0' ||
        deviceId == null ||
        deviceId.isEmpty) {
      throw AppError(
        AppErrorKind.account,
        message: finish['message']?.toString() ?? '绑定设备失败',
      );
    }
    final c = reg.credential;
    return PasskeyCredential(
      credentialId: c.credentialId,
      keyValue: c.keyValue,
      rpId: c.rpId,
      deviceBindingId: deviceId,
      userHandle: c.userHandle,
    );
  }

  /// Bound devices as the personal centre lists them.
  Future<List<Map<String, dynamic>>> boundDevices() async {
    final j = await _pcPost(
      '/accountSecurity/queryAllDevices',
      {'pageNumber': 1, 'pageSize': 50},
    );
    final d = j['datas'];
    return d is List ? d.whereType<Map<String, dynamic>>().toList() : const [];
  }

  /// Removes a bound device by its id (from [boundDevices]).
  Future<void> deleteBoundDevice(String id, String userId) async {
    final j = await _pcPost(
      '/accountSecurity/deleteDevice',
      {'id': id, 'response': userId},
    );
    if (j['code']?.toString() != '0') {
      throw AppError(
        AppErrorKind.account,
        message: j['message']?.toString() ?? '解绑失败',
      );
    }
  }

  /// Ends the AuthServer login (and with it every service's single sign-on).
  Future<void> logout() async {
    if (!webBridgeMode || _casLoginBridgeReady) {
      try {
        await _dio.get<String>('$kAuthServer/authserver/logout');
      } catch (_) {}
    }
    await _jar.deleteAll();
  }

  static bool _isRedirect(int? s) =>
      s == 301 || s == 302 || s == 303 || s == 307 || s == 308;

  static Response<String> _withUri(Response<String> r, Uri uri) => Response(
    requestOptions: r.requestOptions.copyWith(path: uri.toString()),
    data: r.data,
    statusCode: r.statusCode,
    headers: r.headers,
    redirects: [RedirectRecord(r.statusCode ?? 200, 'GET', uri)],
    isRedirect: true,
  );

  static String? _inputValue(String html, String id) {
    final tag = RegExp(
      '<input\\b[^>]*\\bid=["\']${RegExp.escape(id)}["\'][^>]*>',
      caseSensitive: false,
    ).firstMatch(html)?.group(0);
    if (tag == null) return null;
    return _valueAttrRe.firstMatch(tag)?.group(1) ?? '';
  }

  static Map<String, dynamic> _json(String? body) {
    try {
      final v = jsonDecode(body ?? '');
      return v is Map<String, dynamic> ? v : const {};
    } catch (_) {
      return const {};
    }
  }

  Future<Response<String>> _guard(Future<Response<String>> Function() f) async {
    // On web only the bridge may carry requests.
    _requireWebBridge();
    try {
      return await f();
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }
}

final _showErrorTipRe = RegExp(
  r'id=["\x27]showErrorTip["\x27][^>]*>\s*(?:<span[^>]*>)?([^<]+)<',
);
final _formErrorTipRe = RegExp(
  r'id=["\x27]formErrorTip["\x27][^>]*>.*?<span[^>]*>([^<]+)</span>',
  dotAll: true,
);
final _noAccessOrRegisteredTipRe = RegExp(
  r'class=["\x27][^"\x27]*no-access-or-registered-tip[^"\x27]*["\x27][^>]*>([^<]+)<',
);

String _extractCasErrorTip(String html) =>
    _showErrorTipRe.firstMatch(html)?[1]?.trim() ??
    _formErrorTipRe.firstMatch(html)?[1]?.trim() ??
    _noAccessOrRegisteredTipRe.firstMatch(html)?[1]?.trim() ??
    '';

/// Turns a failed login page into an [AppError], keyed on the page's own
/// error tip, as `wisedu_cas._classify_and_raise` does.
AppError classifyLoginFailure(String html) {
  final tip = _extractCasErrorTip(html);
  if (tip.contains('未注册') || tip.contains('无权访问')) {
    return AppError(
      AppErrorKind.schemaOrRedirect,
      message: tip,
      hint: '认证服务未认可目标应用地址，请更新应用或使用官方页面登录。',
    );
  }
  if (tip.contains('锁定') ||
      tip.toUpperCase().contains('LOCK') ||
      html.contains('ACCOUNT_LOCKED') ||
      html.contains('accountLocked')) {
    return AppError(
      AppErrorKind.account,
      message: '账号已被锁定',
      hint: '在统一身份认证页面解锁后再试。',
    );
  }
  if (tip.contains('密码') || tip.contains('用户名')) {
    return AppError(
      AppErrorKind.account,
      message: tip.isEmpty ? '用户名或密码错误' : tip,
      hint: '检查学号和统一身份认证密码。',
    );
  }
  if (tip.contains('验证码') || tip.contains('频繁')) {
    return AppError(
      AppErrorKind.captcha,
      message: tip.isEmpty ? '需要安全验证' : tip,
      hint: '失败次数过多时会要求滑块验证。可改用通行密钥登录，或稍后再试。',
    );
  }
  if (tip.contains('维护')) {
    return AppError(AppErrorKind.maintenanceOrThrottle, message: tip);
  }
  return AppError(
    AppErrorKind.account,
    message: tip.isEmpty ? '统一身份认证登录失败' : tip,
  );
}
