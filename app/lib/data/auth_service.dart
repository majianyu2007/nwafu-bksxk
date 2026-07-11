/// Authentication + session lifecycle.
///
/// Login sequence (transcribed from the site's index.min.js):
///   1. GET student/4/vcode.do            -> data.token = vtoken
///   2. GET student/vcode/image.do?vtoken -> captcha image bytes
///   3. loginPwd = base64(strEnc(pw, this,password,is))
///   4. GET student/check/login.do?timestrap=<ms> with
///      loginName, loginPwd, verifyCode, vtoken
///      -> code=="1": data.token (auth), data.number (studentCode)
///   5. GET student/<studentCode>.do      -> student profile
///   6. GET elective/batch.do             -> visible batches
///
/// [SessionManager] holds the live token and knows how to silently re-login,
/// which the [ApiClient] invokes when it detects an expired session. Because a
/// text captcha is required, silent re-login needs a captcha solver; the manager
/// delegates that to a pluggable [CaptchaSolver].
library;

import '../core/constants.dart';
import '../core/crypto/des_login.dart';
import 'api_client.dart';
import 'captcha.dart';
import 'models.dart';

/// A single captcha challenge: the token to submit with, and the image bytes.
class CaptchaChallenge {
  CaptchaChallenge({required this.vtoken, required this.imageBytes});
  final String vtoken;
  final List<int> imageBytes;
}

/// Outcome of a login attempt.
class LoginResult {
  LoginResult({required this.token, required this.studentCode});
  final String token;
  final String studentCode;
}

/// Raised when the server rejects credentials or the captcha.
class LoginException implements Exception {
  LoginException(this.code, this.message);

  /// Server code: "2" bad credentials, "3" bad captcha, others map to messages.
  final String code;
  final String message;
  @override
  String toString() => 'LoginException($code): $message';
}

class AuthService {
  AuthService(this._client);

  final ApiClient _client;

  /// Step 1+2: fetch a fresh captcha token and its image.
  Future<CaptchaChallenge> fetchCaptcha() async {
    final tokenRes = await _client.getJson(Api.vcodeToken, auth: false, allowRelogin: false);
    final vtoken = _extractToken(tokenRes);
    if (vtoken.isEmpty) {
      throw LoginException('0', '获取验证码令牌失败');
    }
    final bytes = await _client.getBytes(Api.vcodeImage, query: {'vtoken': vtoken}, auth: false);
    return CaptchaChallenge(vtoken: vtoken, imageBytes: bytes);
  }

  String _extractToken(ApiResult res) {
    final data = res.data;
    if (data is Map && data['token'] != null) return data['token'].toString();
    // Some deployments put it directly in msg/data string.
    if (data is String && data.isNotEmpty) return data;
    return '';
  }

  /// Steps 3+4: submit credentials with a solved captcha. On success the token
  /// is installed into the client. Does NOT fetch profile/batches — call
  /// [loadContext] after.
  Future<LoginResult> login({
    required String loginName,
    required String password,
    required String verifyCode,
    required String vtoken,
  }) async {
    final loginPwd = encodeLoginPassword(password);
    final res = await _client.getJson(
      Api.checkLogin,
      auth: false,
      addTimestamp: false,
      allowRelogin: false,
      query: {
        'timestrap': ApiClient.nowStamp(),
        'loginName': loginName,
        'loginPwd': loginPwd,
        'verifyCode': verifyCode,
        'vtoken': vtoken,
      },
    );

    final code = res.code;
    if (code == '1') {
      final data = res.data;
      final token = (data is Map ? data['token'] : null)?.toString() ?? '';
      final number = (data is Map ? data['number'] : null)?.toString() ?? '';
      if (token.isEmpty) throw LoginException('0', '登录响应缺少 token');
      _client.token = token;
      return LoginResult(token: token, studentCode: number);
    }
    // Map the frontend's known codes to messages.
    switch (code) {
      case '2':
        throw LoginException('2', '登录名或密码不正确');
      case '3':
        throw LoginException('3', '验证码不正确');
      default:
        throw LoginException(code, res.msg.isEmpty ? '登录失败' : res.msg);
    }
  }

  /// Steps 5+6: load student profile and the visible elective batches.
  Future<(StudentInfo, List<ElectiveBatch>)> loadContext(String studentCode) async {
    final infoRes = await _client.getJson(Api.studentInfo(studentCode));
    final info = StudentInfo.fromJson(
      (infoRes.data is Map) ? (infoRes.data as Map).cast<String, dynamic>() : {'code': studentCode},
    );
    final batchRes = await _client.getJson(Api.batch);
    final batches = batchRes.dataList
        .whereType<Map>()
        .map((e) => ElectiveBatch.fromJson(e.cast<String, dynamic>()))
        .toList();
    return (info, batches);
  }

  /// Confirms whether a batch is currently open (called before write ops).
  Future<bool> isBatchOpen(String batchCode) async {
    final res = await _client.postForm(Api.batchIsOpen, {'xklcdm': batchCode});
    // Server returns code=1, msg=1 when open.
    return res.ok && (res.msg == '1' || res.msg.isEmpty);
  }
}

/// Owns the live session and performs silent, captcha-solving re-login.
///
/// When [ApiClient] sees an expired session, it calls [relogin], which replays
/// the full login using the stored password and a captcha solved by [solver].
/// If the solver cannot produce an answer (e.g. no OCR configured and the app is
/// backgrounded), re-login fails gracefully and the caller surfaces it.
class SessionManager {
  SessionManager({
    required ApiClient client,
    required AuthService auth,
    required CaptchaSolver solver,
  })  : _client = client,
        _auth = auth,
        _solver = solver {
    _client.onSessionExpired = _onExpired;
  }

  final ApiClient _client;
  final AuthService _auth;
  CaptchaSolver _solver;

  String? _loginName;
  String? _password;

  StudentInfo? student;
  List<ElectiveBatch> batches = [];
  ElectiveBatch? activeBatch;

  ApiClient get client => _client;
  AuthService get auth => _auth;
  String? get studentCode => student?.studentCode;

  set solver(CaptchaSolver s) => _solver = s;

  /// Remembers credentials so silent re-login can replay them.
  void rememberCredentials(String loginName, String password) {
    _loginName = loginName;
    _password = password;
  }

  /// Full interactive login: caller supplies the solved captcha. Loads context
  /// and remembers credentials for later silent re-login.
  Future<void> loginInteractive({
    required String loginName,
    required String password,
    required String verifyCode,
    required String vtoken,
  }) async {
    final res = await _auth.login(
      loginName: loginName,
      password: password,
      verifyCode: verifyCode,
      vtoken: vtoken,
    );
    rememberCredentials(loginName, password);
    final (info, batchList) = await _auth.loadContext(res.studentCode);
    student = info;
    batches = batchList;
    activeBatch = _pickDefaultBatch(batchList);
  }

  ElectiveBatch? _pickDefaultBatch(List<ElectiveBatch> list) {
    if (list.isEmpty) return null;
    // Prefer an open/selectable batch.
    for (final b in list) {
      if (b.canSelect) return b;
    }
    return list.first;
  }

  /// The silent path invoked by ApiClient on expiry. Returns a fresh token or
  /// null. Solves a captcha headlessly via [_solver]; if it can't, returns null.
  Future<String?> _onExpired() async {
    final name = _loginName;
    final pw = _password;
    if (name == null || pw == null) return null;
    try {
      final challenge = await _auth.fetchCaptcha();
      final solved = await _solver.solve(challenge.imageBytes);
      if (solved == null || solved.isEmpty) return null;
      final res = await _auth.login(
        loginName: name,
        password: pw,
        verifyCode: solved,
        vtoken: challenge.vtoken,
      );
      return res.token;
    } catch (_) {
      return null;
    }
  }
}
