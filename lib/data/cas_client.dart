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
enum MfaMethod {
  sms('3', '短信验证码', needsSend: true),
  wecom('4', '企业微信验证码', needsSend: true),
  totp('10', '安全令牌（TOTP）'),
  wechatScan('8', '微信扫码', supported: false);

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

  /// Methods that only work in a browser (QR scans) are listed but disabled.
  final bool supported;

  String? get sendTypeName => switch (this) {
    sms => 'reAuthDynamicCodeType',
    wecom => 'reAuthWChatDynamicCodeType',
    _ => null,
  };

  static MfaMethod? byCode(String code) {
    for (final m in values) {
      if (m.code == code) return m;
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
  });

  /// The service the login was for; the ticket is issued for it afterwards.
  final String service;
  final List<MfaMethod> methods;

  /// `reAuthUserId` from the page; the SMS endpoint wants it.
  final String userId;
  final String displayName;
}

/// Thrown by [CasClient.login] when a second factor is required.
class CasMfaRequired implements Exception {
  CasMfaRequired(this.challenge);
  final CasMfaChallenge challenge;
  @override
  String toString() => '需要二次验证';
}

class CasClient {
  CasClient({required CookieJar cookieJar, Dio? dio, this.random})
    : _jar = cookieJar {
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
              if (!kIsWeb)
                'User-Agent':
                    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
                    '(KHTML, like Gecko) Chrome/150.0 Safari/537.36',
            },
          ),
        );
    if (!kIsWeb) {
      _dio.interceptors.add(CookieManager(_jar));
      if (dio == null) CampusProxy.instance.attach(_dio);
    }
  }

  late final Dio _dio;
  final CookieJar _jar;

  /// Source for the password/passkey nonces; tests pin it.
  final Random? random;

  Dio get dio => _dio;
  CookieJar get cookieJar => _jar;

  static void requireSupportedPlatform() {
    if (kIsWeb) {
      throw AppError(
        AppErrorKind.schemaOrRedirect,
        message: '网页版请连接浏览器教务会话',
        hint: '请先在学校官方页面登录，再返回连接；网页版不接收统一认证密码或通行密钥。',
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
    final uri = Uri.parse(kAuthServer);
    final cookies = await _jar.loadForRequest(uri);
    final trusted = cookies
        .where((c) => c.name == 'MULTIFACTOR_BROWSER_FINGERPRINT')
        .toList();
    await _jar.deleteAll();
    if (trusted.isNotEmpty) await _jar.saveFromResponse(uri, trusted);
  }

  static void _validateUrl(Uri uri) {
    if (uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443) ||
        !const {
          'authserver.nwafu.edu.cn',
          'ehall.nwafu.edu.cn',
        }.contains(uri.host)) {
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
    if (kIsWeb) {
      requireBrowserSessionBridge();
      _validateUrl(current);
      if (current.host != 'ehall.nwafu.edu.cn' ||
          !current.path.startsWith('/jwapp/')) {
        throw AppError(
          AppErrorKind.schemaOrRedirect,
          message: '网页版只能连接学校官方教务应用',
        );
      }
      // GM owns redirects and browser cookies. Never emulate native manual CAS.
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
    if (kIsWeb) {
      final res = await follow(service);
      final target = Uri.parse(service);
      return res.realUri.host == target.host &&
          res.realUri.path == target.path &&
          (res.statusCode ?? 500) < 400;
    }
    final res = await _guard(() => _dio.get<String>(loginUrl(service)));
    final loc = res.headers.value('location') ?? '';
    return _isRedirect(res.statusCode) && !loc.contains('/authserver/login');
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
    requireSupportedPlatform();
    _validateUrl(Uri.parse(service));
    if (passkey != null &&
        (!passkey.isComplete || passkey.rpId != Uri.parse(kAuthServer).host)) {
      throw AppError(AppErrorKind.account, message: '通行密钥不属于西农统一身份认证或信息不完整');
    }
    final page = await _guard(() => _dio.get<String>(loginUrl(service)));
    if (_isRedirect(page.statusCode)) {
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
      res = await _passkeyLogin(service, username, execution, passkey);
    } else {
      final salt = _inputValue(html, 'pwdEncryptSalt');
      if (salt == null || salt.length != 16) {
        throw AppError(
          AppErrorKind.schemaOrRedirect,
          message: '统一身份认证加密参数缺失',
          hint: '未发送密码，请更新应用或使用官方登录页。',
        );
      }
      res = await _guard(
        () => _dio.post<String>(
          loginUrl(service),
          data: {
            'username': username,
            'password': encryptCasPassword(password, salt, random: random),
            'captcha': '',
            'rememberMe': 'true',
            '_eventId': 'submit',
            'cllt': 'userNameLogin',
            'dllt': 'generalLogin',
            'lt': '',
            'execution': execution,
          },
          options: Options(contentType: Headers.formUrlEncodedContentType),
        ),
      );
    }
    if (!_isRedirect(res.statusCode)) {
      throw classifyLoginFailure(res.data ?? '');
    }
    await _afterLogin(res, service);
  }

  Future<Response<String>> _passkeyLogin(
    String service,
    String username,
    String execution,
    PasskeyCredential passkey,
  ) async {
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
      result =
          (jsonDecode(start.data ?? '') as Map)['result']
              as Map<String, dynamic>;
    } catch (_) {
      result = const {};
    }
    final request = result['request'] as Map<String, dynamic>?;
    final options =
        request?['publicKeyCredentialRequestOptions'] as Map<String, dynamic>?;
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
    return _guard(
      () => _dio.post<String>(
        loginUrl(service),
        data: {
          'username': userId,
          'responseJson': jsonEncode({
            'requestId': requestId,
            'credential': assertion,
            'sessionToken': null,
          }),
          '_eventId': 'submit',
          'cllt': 'fidoLogin',
          'dllt': 'generalLogin',
          'lt': '',
          'rememberMe': 'true',
          'execution': execution,
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
      throw CasMfaRequired(_parseMfaPage(last.data ?? '', service));
    }
    if (url.contains('/authserver/login')) {
      throw classifyLoginFailure(last.data ?? '');
    }
    _requireService(last, service);
  }

  CasMfaChallenge _parseMfaPage(String html, String service) {
    final methods = <MfaMethod>[];
    for (final m in RegExp(
      r'class="[^"]*changeReAuthTypes[^"]*"[^>]*?id="([^"]+)"',
      dotAll: true,
    ).allMatches(html)) {
      final method = MfaMethod.byCode(m[1]!);
      if (method != null && !methods.contains(method)) methods.add(method);
    }
    if (methods.isEmpty) {
      throw AppError(
        AppErrorKind.schemaOrRedirect,
        message: '无法读取学校提供的二次验证方式',
        hint: '请使用官方认证页面登录。',
      );
    }
    String param(String key) =>
        RegExp('"$key"\\s*:\\s*"([^"]*)"').firstMatch(html)?[1] ?? '';
    final name = RegExp(
      r'id="username"[^>]*value="([^"]*)"',
    ).firstMatch(html)?[1];
    return CasMfaChallenge(
      service: service,
      methods: methods,
      userId: param('reAuthUserId'),
      displayName: name ?? '',
    );
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
          'isMultifactor': 'true',
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
  }

  /// Sends an SMS / 企业微信 code. Returns the server's message (it names
  /// the masked phone number).
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
    if (code.trim().isEmpty) {
      throw AppError(AppErrorKind.captcha, message: '请输入二次验证码');
    }
    if (method == MfaMethod.totp) await selectMfaMethod(c, method);
    final res = await _guard(
      () => _dio.post<String>(
        '$kAuthServer/authserver/reAuthCheck/reAuthSubmit.do',
        data: {
          'service': c.service,
          'reAuthType': method.code,
          'isMultifactor': 'true',
          'password': '',
          'dynamicCode': method == MfaMethod.totp ? '' : code.trim(),
          'uuid': '',
          'answer1': '',
          'answer2': '',
          'otpCode': method == MfaMethod.totp ? code.trim() : '',
          'skipTmpReAuth': trustDevice ? 'true' : 'false',
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      ),
    );
    final j = _json(res.data);
    if (j['code']?.toString() != 'reAuth_success') {
      throw AppError(
        AppErrorKind.captcha,
        message: j['msg']?.toString().isNotEmpty == true
            ? j['msg'].toString()
            : '验证码错误',
        hint: '检查验证码后重试；安全令牌请确认手机时间准确。',
      );
    }
    final last = await follow(loginUrl(c.service));
    if (last.realUri.toString().contains('/authserver/')) {
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
    final res = await _dio.get<List<int>>(
      '$_pcBase/captcha/checkCode?data=${DateTime.now().millisecondsSinceEpoch}',
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(res.data ?? const []);
  }

  /// Re-checks the password (with the captcha from [recheckCaptcha]).
  Future<void> recheckPassword(String password, String captcha) async {
    final key = await _cookie('WIS_PER_ENC') ?? '';
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
    final request = (start['datas'] as Map?)?['request'];
    final options = request is Map
        ? request['publicKeyCredentialCreationOptions']
        : null;
    if (start['code']?.toString() != '0' || options is! Map) {
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
    try {
      await _dio.get<String>('$kAuthServer/authserver/logout');
    } catch (_) {}
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
    return RegExp(r'''\bvalue=["']([^"']*)["']''').firstMatch(tag)?.group(1) ??
        '';
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
    requireSupportedPlatform();
    try {
      return await f();
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }
}

/// Turns a failed login page into an [AppError], keyed on the page's own
/// error tip, as `wisedu_cas._classify_and_raise` does.
AppError classifyLoginFailure(String html) {
  final tip =
      RegExp(r'id="showErrorTip"[^>]*>([^<]+)<').firstMatch(html)?[1]?.trim() ??
      RegExp(
        r'id=["\x27]formErrorTip["\x27][^>]*>.*?<span[^>]*>([^<]+)</span>',
        dotAll: true,
      ).firstMatch(html)?[1]?.trim() ??
      '';
  if (tip.contains('锁定') || html.contains('LOCK')) {
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
