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
import 'info_service.dart';
import 'models.dart';
import 'param_builders.dart';

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
    final tokenRes =
        await _client.getJson(Api.vcodeToken, auth: false, allowRelogin: false);
    final vtoken = _extractToken(tokenRes);
    if (vtoken.isEmpty) {
      throw LoginException('0', '获取验证码令牌失败');
    }
    final bytes = await _client.getBytes(Api.vcodeImage,
        query: {'vtoken': vtoken}, auth: false);
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
  Future<(StudentInfo, List<ElectiveBatch>)> loadContext(
      String studentCode) async {
    final infoRes = await _client.getJson(Api.studentInfo(studentCode));
    final infoMap = (infoRes.data is Map)
        ? (infoRes.data as Map).cast<String, dynamic>()
        : <String, dynamic>{'code': studentCode};
    final info = StudentInfo.fromJson(infoMap);
    final batchRes = await _client.getJson(Api.batch);
    final batches = mergeBatchAvailability(
      batchRes.dataList
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList(),
      infoMap,
    );
    return (info, batches);
  }

  /// Confirms whether a batch is currently open (called before write ops).
  Future<bool> isBatchOpen(String batchCode) async {
    final res = await _client.postForm(Api.batchIsOpen, {'xklcdm': batchCode});
    // Server returns code=1, msg=1 when open.
    return res.ok && (res.msg == '1' || res.msg.isEmpty);
  }

  /// Confirms that the student acknowledged the selected round's notice
  /// (student/xklcqr.do), matching the official post-login flow.
  Future<ApiResult> confirmBatch({
    required String studentCode,
    required String batchCode,
  }) =>
      _client.postForm(
        Api.batchConfirm,
        buildBatchConfirmParam(
          studentCode: studentCode,
          electiveBatchCode: batchCode,
        ),
      );

  /// Logs out on the server (logout.do). Best-effort: the caller clears the
  /// local session regardless of the outcome, since the cookie/token are gone
  /// either way.
  Future<void> logout(String studentCode) async {
    try {
      await _client.getJson(
        Api.logout,
        auth: false,
        addTimestamp: false,
        allowRelogin: false,
        query: buildLogoutQuery(
          studentCode: studentCode,
          timestamp: ApiClient.nowStamp(),
        ),
      );
    } catch (_) {
      // Swallow: the local session is dropped below regardless.
    }
    _client.token = null;
    await _client.clearCookies();
  }
}

/// Builds the round list from batch.do rows plus the student profile.
///
/// batch.do describes every round but leaves `canSelect` null; the profile's
/// `electiveBatchList` repeats the rounds with the per-student `canSelect` and
/// `noSelectReason`, which is what the official page reads. Values already
/// present on the batch.do row win; profile-only rounds (and the profile's
/// experimental `expElectiveBatchList`) are appended so nothing disappears.
List<ElectiveBatch> mergeBatchAvailability(
  List<Map<String, dynamic>> batchRows,
  Map<String, dynamic> studentInfo,
) {
  String codeOf(Map<String, dynamic> m) =>
      (m['electiveBatchCode'] ?? m['code'] ?? m['xklcdm'] ?? '').toString();
  List<Map<String, dynamic>> rows(dynamic v) => v is List
      ? v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList()
      : const [];

  final profileRows = [
    ...rows(studentInfo['electiveBatchList']),
    ...rows(studentInfo['expElectiveBatchList']),
  ];
  final byCode = {for (final r in profileRows) codeOf(r): r};

  final merged = <ElectiveBatch>[];
  final seen = <String>{};
  for (final row in batchRows) {
    final code = codeOf(row);
    final profile = byCode[code];
    final combined = <String, dynamic>{
      if (profile != null) ...profile,
      // batch.do wins wherever it actually has a value.
      for (final e in row.entries)
        if (e.value != null) e.key: e.value,
    };
    merged.add(ElectiveBatch.fromJson(combined));
    seen.add(code);
  }
  for (final row in profileRows) {
    final code = codeOf(row);
    if (code.isEmpty || seen.contains(code)) continue;
    merged.add(ElectiveBatch.fromJson(row));
    seen.add(code);
  }
  return merged;
}

/// Pure batch-selection policy used after login and unit-tested independently.
/// Prefer the first selectable round; if none are open, keep the first visible
/// round for read-only browsing while reporting [hasSelectable] = false so UI
/// can warn instead of implying the round is usable.
({ElectiveBatch? batch, bool hasSelectable}) selectInitialBatch(
    List<ElectiveBatch> list) {
  if (list.isEmpty) return (batch: null, hasSelectable: false);
  for (final b in list) {
    if (b.canSelect) return (batch: b, hasSelectable: true);
  }
  return (batch: list.first, hasSelectable: false);
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
    InfoService? info,
  })  : _client = client,
        _auth = auth,
        _solver = solver,
        _info = info {
    _client.onSessionExpired = _onExpired;
  }

  final ApiClient _client;
  final AuthService _auth;
  final InfoService? _info;
  CaptchaSolver _solver;

  String? _loginName;
  String? _password;

  /// Captcha attempts the silent re-login may spend before giving up.
  /// 0 disables silent re-login: the first expiry goes straight to the user;
  /// a negative value means unlimited (keeps trying with backoff).
  int maxSilentReloginAttempts = 3;

  /// Master switch for silent re-login. Off = every drop asks the user.
  bool silentReloginEnabled = true;

  /// Why the last silent re-login gave up, for the re-login dialog.
  String lastFailure = '';

  /// Fired when a silent re-login could not recover the session (attempts
  /// exhausted, no stored password, the account was rejected, or the session
  /// is [contested]). The UI prompts the user to log in again.
  void Function()? onSilentReloginFailed;

  /// The server keeps one session per account, so a login in a browser kills
  /// the app's session and vice versa. With [contestedGuardEnabled], if the
  /// app re-logged in silently and was kicked again within [contestedWindow],
  /// someone else is using the account and re-logging in again would only
  /// kick them in turn, every heartbeat. Off by default: the user asked for
  /// the app to win the session unless they turn this on.
  bool contestedGuardEnabled = false;
  Duration contestedWindow = const Duration(minutes: 3);
  DateTime? _lastSilentRelogin;

  /// True when the last expiry was left alone because the account is in use
  /// elsewhere (see [contestedWindow]). Cleared by the next login.
  bool contested = false;

  /// Fired after a silent re-login succeeded.
  void Function()? onSilentReloginSucceeded;

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
    contested = false;
    _lastSilentRelogin = null;
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
    // Silent re-login replays exactly these.
    rememberCredentials(loginName, password);
    final (info, batchList) = await _auth.loadContext(res.studentCode);
    final initialChoice = selectInitialBatch(batchList);
    var merged = info;
    // The student/<code>.do profile often omits name/college/major/grade;
    // xkxf.do (credit info) carries them. Best-effort merge so the home page
    // shows the real name instead of "同学".
    final initialBatch = initialChoice.batch;
    if (_info != null && initialBatch != null) {
      try {
        final credit = await _info.fetchCreditInfo(
          studentCode: res.studentCode,
          electiveBatchCode: initialBatch.code,
          batchType: initialBatch.batchType,
        );
        if (credit.raw.isNotEmpty) merged = info.mergeFromCredit(credit);
      } catch (_) {
        // Non-fatal: keep the sparser profile.
      }
    }
    student = merged;
    batches = batchList;
    activeBatch = initialBatch;
  }

  /// The silent path invoked by ApiClient on expiry (e.g. server restart /
  /// cookie expiry). Re-logins headlessly using the stored credentials + OCR,
  /// retrying a few times through transient failures (server flaky right after a
  /// restart) and OCR misreads. Returns a fresh token or null.
  Future<String?> _onExpired() async {
    if (!silentReloginEnabled || maxSilentReloginAttempts == 0) {
      lastFailure = '自动重新登录已关闭';
      onSilentReloginFailed?.call();
      return null;
    }
    final last = _lastSilentRelogin;
    if (contestedGuardEnabled &&
        last != null &&
        DateTime.now().difference(last) < contestedWindow) {
      contested = true;
      lastFailure = '刚重新登录又被踢下线，账号可能正在别处使用';
      onSilentReloginFailed?.call();
      return null;
    }
    final token = await _silentRelogin();
    if (token == null) {
      onSilentReloginFailed?.call();
    } else {
      _lastSilentRelogin = DateTime.now();
      contested = false;
      onSilentReloginSucceeded?.call();
    }
    return token;
  }

  /// One captcha fetch + OCR + login per attempt, at most
  /// [maxSilentReloginAttempts] times. Each captcha fetch is a server request,
  /// and the school's gateway blocks clients that hammer vcode.do, so the
  /// budget is deliberately small.
  Future<String?> _silentRelogin() async {
    final name = _loginName;
    final pw = _password;
    if (name == null || pw == null) {
      lastFailure = '没有保存的密码';
      return null;
    }
    lastFailure = '';
    var misreads = 0;
    var unreadable = 0;
    String? lastError;

    final unlimited = maxSilentReloginAttempts < 0;
    for (var attempt = 1;
        unlimited || attempt <= maxSilentReloginAttempts;
        attempt++) {
      if (unlimited && attempt > 1) {
        // Space unlimited retries out so the captcha endpoint's rate limit
        // (which blocks the client outright) is not tripped.
        await Future<void>.delayed(
            Duration(seconds: (2 * (attempt - 1)).clamp(2, 30)));
      }
      try {
        final challenge = await _auth.fetchCaptcha();
        final solved = await _solver.solve(challenge.imageBytes);
        if (solved == null || solved.isEmpty) {
          // OCR couldn't read it — nothing to submit headlessly. Try a fresh one.
          unreadable++;
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
        if (e.code == '2') {
          lastFailure = e.message;
          return null;
        }
        if (e.code == '3') {
          misreads++;
        } else {
          lastError = e.message;
        }
      } on AppError catch (e) {
        if (e.kind == AppErrorKind.account) {
          lastFailure = e.message;
          return null;
        }
        lastError = e.message;
        // Transient (server restarting / busy) → back off and retry.
        await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
      } catch (e) {
        lastError = '$e';
        await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
      }
    }
    final tried = misreads + unreadable;
    lastFailure = tried > 0
        ? '验证码自动识别连续 $tried 次未通过（识别错 $misreads 次，无法识别 $unreadable 次）'
        : (lastError ?? '自动重新登录未成功');
    return null;
  }
}
