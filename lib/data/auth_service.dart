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
import '../core/errors.dart';
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

  /// Retries login through transient server failures until it succeeds, a hard
  /// error occurs, or [shouldContinue] returns false (user cancelled).
  ///
  /// This is for the opening-rush stampede, when the server is crashing/timing
  /// out/返回繁忙 under load. Those are transient: we back off and try again.
  /// Bad credentials or a bad captcha are NOT transient — we stop and rethrow so
  /// the user can fix them. A captcha is re-fetched (and re-solved via [solver],
  /// or re-requested via [onNeedCaptcha]) on every attempt.
  ///
  /// [onNeedCaptcha] is called when no solver can answer and a human must enter
  /// the code; it returns (verifyCode, vtoken) or null to abort.
  Future<void> loginWithRetry({
    required String loginName,
    required String password,
    String? initialVerifyCode,
    String? initialVtoken,
    Future<(String, String)?> Function()? onNeedCaptcha,
    bool Function()? shouldContinue,
    void Function(int attempt, String message)? onProgress,
    Duration baseDelay = const Duration(seconds: 2),
    Duration maxDelay = const Duration(seconds: 20),
    int maxAttempts = 0, // 0 = unlimited until success/hard-stop/cancel
  }) async {
    var attempt = 0;
    String? verifyCode = initialVerifyCode;
    String? vtoken = initialVtoken;

    while (true) {
      if (shouldContinue != null && !shouldContinue()) {
        throw LoginException('cancelled', '已取消登录');
      }
      attempt++;

      // Ensure we have a captcha answer for this attempt.
      if (verifyCode == null || verifyCode.isEmpty || vtoken == null || vtoken.isEmpty) {
        final solved = await _obtainCaptcha(onNeedCaptcha);
        if (solved == null) {
          throw LoginException('cancelled', '需要验证码，已取消');
        }
        verifyCode = solved.$1;
        vtoken = solved.$2;
      }

      try {
        await loginInteractive(
          loginName: loginName,
          password: password,
          verifyCode: verifyCode,
          vtoken: vtoken,
        );
        onProgress?.call(attempt, '登录成功');
        return;
      } on LoginException catch (e) {
        // Bad credentials -> hard stop. Bad captcha -> get a new one and retry
        // immediately (not a "server down" situation).
        if (e.code == '2') rethrow; // wrong username/password
        if (e.code == '3') {
          onProgress?.call(attempt, '验证码错误，重试');
          verifyCode = null;
          vtoken = null;
          continue;
        }
        // Other login codes: treat as transient (server may be flaky at open).
        onProgress?.call(attempt, e.message.isEmpty ? '登录失败，重试' : e.message);
      } on AppError catch (e) {
        if (e.isHardStop && e.kind == AppErrorKind.account) rethrow;
        // Network/timeout/5xx/maintenance/campus — all transient during a rush.
        onProgress?.call(attempt, e.message);
        // Force a fresh captcha next round in case the vtoken expired.
        verifyCode = null;
        vtoken = null;
      }

      if (maxAttempts > 0 && attempt >= maxAttempts) {
        throw LoginException('exhausted', '重试次数已用尽，仍无法登录');
      }

      // Exponential backoff, capped, so we don't pile onto a struggling server.
      final factor = 1 << (attempt - 1).clamp(0, 20);
      final delayMs = (baseDelay.inMilliseconds * factor).clamp(0, maxDelay.inMilliseconds);
      onProgress?.call(attempt, '第 $attempt 次重试，${(delayMs / 1000).toStringAsFixed(1)}s 后再试');
      await Future<void>.delayed(Duration(milliseconds: delayMs));
    }
  }

  /// Gets a captcha answer: prefers the headless solver, falls back to the UI
  /// callback. Returns (verifyCode, vtoken) or null to abort.
  Future<(String, String)?> _obtainCaptcha(Future<(String, String)?> Function()? onNeedCaptcha) async {
    try {
      final challenge = await _auth.fetchCaptcha();
      final solved = await _solver.solve(challenge.imageBytes);
      if (solved != null && solved.isNotEmpty) {
        return (solved, challenge.vtoken);
      }
    } catch (_) {
      // fall through to UI callback
    }
    if (onNeedCaptcha != null) return onNeedCaptcha();
    return null;
  }

  /// The silent path invoked by ApiClient on expiry (e.g. server restart /
  /// cookie expiry). Re-logins headlessly using the stored credentials + OCR,
  /// retrying a few times through transient failures (server flaky right after a
  /// restart) and OCR misreads. Returns a fresh token or null.
  Future<String?> _onExpired() async {
    final name = _loginName;
    final pw = _password;
    if (name == null || pw == null) return null;

    const maxTries = 5;
    for (var attempt = 1; attempt <= maxTries; attempt++) {
      try {
        final challenge = await _auth.fetchCaptcha();
        final solved = await _solver.solve(challenge.imageBytes);
        if (solved == null || solved.isEmpty) {
          // OCR couldn't read it — nothing to submit headlessly. Try a fresh one.
          continue;
        }
        final res = await _auth.login(
          loginName: name,
          password: pw,
          verifyCode: solved,
          vtoken: challenge.vtoken,
        );
        return res.token;
      } on LoginException catch (e) {
        // Wrong password won't fix itself — stop. Wrong captcha (3) → retry.
        if (e.code == '2') return null;
      } on AppError catch (e) {
        if (e.kind == AppErrorKind.account) return null;
        // Transient (server restarting / busy) → back off and retry.
        await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
      } catch (_) {
        await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
      }
    }
    return null;
  }
}
