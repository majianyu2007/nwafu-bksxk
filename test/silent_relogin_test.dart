// The silent re-login budget: one captcha + OCR + login per attempt, at most
// maxSilentReloginAttempts times, then the failure callback so the UI can ask
// the user; a success reports the fresh token. Uses fakes, no network.
import 'package:nwafu_bksxk/core/errors.dart';
import 'package:nwafu_bksxk/data/api_client.dart';
import 'package:nwafu_bksxk/data/auth_service.dart';
import 'package:nwafu_bksxk/data/captcha.dart';
import 'package:nwafu_bksxk/data/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test/test.dart';

class _ScriptedAuth extends AuthService {
  _ScriptedAuth(this.outcomes) : super(ApiClient(origin: 'http://localhost'));

  /// Per login attempt: a token string to succeed with, a LoginException code
  /// ('2' bad credentials, '3' bad captcha), or 'busy' for a throttle error.
  final List<String> outcomes;
  int captchaFetches = 0;
  int loginCalls = 0;

  @override
  Future<CaptchaChallenge> fetchCaptcha() async {
    captchaFetches++;
    return CaptchaChallenge(vtoken: 'v$captchaFetches', imageBytes: const [1]);
  }

  @override
  Future<LoginResult> login({
    required String loginName,
    required String password,
    required String verifyCode,
    required String vtoken,
  }) async {
    final outcome = outcomes[loginCalls.clamp(0, outcomes.length - 1)];
    loginCalls++;
    switch (outcome) {
      case '2':
        throw LoginException('2', '登录名或密码不正确');
      case '3':
        throw LoginException('3', '验证码不正确');
      case 'busy':
        throw AppError(AppErrorKind.maintenanceOrThrottle, message: '系统繁忙');
      default:
        return LoginResult(token: outcome, studentCode: 'S');
    }
  }
}

(SessionManager, _ScriptedAuth, ApiClient) build(List<String> outcomes,
    {int attempts = 3}) {
  final client = ApiClient(origin: 'http://localhost');
  final auth = _ScriptedAuth(outcomes);
  final mgr = SessionManager(
    client: client,
    auth: auth,
    solver: OcrCaptchaSolver((_) async => 'abcd'),
  )
    ..rememberCredentials('user', 'pw')
    ..maxSilentReloginAttempts = attempts;
  return (mgr, auth, client);
}

void main() {
  test(
      'stops after the configured number of captcha attempts and reports failure',
      () async {
    final (mgr, auth, client) = build(['3', '3', '3', '3', '3']);
    var failed = 0;
    var succeeded = 0;
    mgr.onSilentReloginFailed = () => failed++;
    mgr.onSilentReloginSucceeded = () => succeeded++;

    final token = await client.onSessionExpired!();

    expect(token, isNull);
    expect(auth.loginCalls, 3);
    expect(auth.captchaFetches, 3);
    expect(failed, 1);
    expect(succeeded, 0);
  });

  test('a budget of 0 asks the user immediately without touching the server',
      () async {
    final (mgr, auth, client) = build(['tok'], attempts: 0);
    var failed = 0;
    mgr.onSilentReloginFailed = () => failed++;

    expect(await client.onSessionExpired!(), isNull);
    expect(auth.captchaFetches, 0);
    expect(auth.loginCalls, 0);
    expect(failed, 1);
  });

  test('a misread captcha is retried within the budget and success is reported',
      () async {
    final (mgr, auth, client) = build(['3', 'fresh-token']);
    var succeeded = 0;
    var failed = 0;
    mgr.onSilentReloginSucceeded = () => succeeded++;
    mgr.onSilentReloginFailed = () => failed++;

    final token = await client.onSessionExpired!();

    expect(token, 'fresh-token');
    expect(auth.loginCalls, 2);
    expect(succeeded, 1);
    expect(failed, 0);
  });

  test('wrong credentials stop immediately: retrying cannot help', () async {
    final (mgr, auth, client) = build(['2', 'tok', 'tok'], attempts: 5);
    var failed = 0;
    mgr.onSilentReloginFailed = () => failed++;

    expect(await client.onSessionExpired!(), isNull);
    expect(auth.loginCalls, 1);
    expect(failed, 1);
  });

  test('the budget defaults to 3 in storage and persists a change', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = Storage(await SharedPreferences.getInstance());
    expect(storage.silentReloginAttempts(), 3);
    await storage.setSilentReloginAttempts(0);
    expect(storage.silentReloginAttempts(), 0);
  });

  settingsTests();

  test('with the guard on, a session kicked again right after a silent re-login is left alone',
      () async {
    // Verified live 2026-09-18: one session per account, so re-logging in
    // would kick whoever is using the account elsewhere, every heartbeat.
    final (mgr, auth, client) = build(['tok-1', 'tok-2'], attempts: 3);
    mgr.contestedGuardEnabled = true;
    var failed = 0;
    mgr.onSilentReloginFailed = () => failed++;

    expect(await client.onSessionExpired!(), 'tok-1');
    expect(mgr.contested, isFalse);

    expect(await client.onSessionExpired!(), isNull);
    expect(auth.loginCalls, 1, reason: 'no second login within the window');
    expect(mgr.contested, isTrue);
    expect(failed, 1);

    // A deliberate login by the user resets the guard.
    mgr.rememberCredentials('user', 'pw');
    expect(mgr.contested, isFalse);
  });
}

// ---------------------------------------------------------------------------
// Settings the user asked for: a master switch, a failure reason for the
// dialog, and a contested-session guard that is off unless enabled.
// ---------------------------------------------------------------------------
void settingsTests() {
  test('the master switch off asks the user at once with a reason', () async {
    final (mgr, auth, client) = build(['tok']);
    mgr.silentReloginEnabled = false;
    var failed = 0;
    mgr.onSilentReloginFailed = () => failed++;
    expect(await client.onSessionExpired!(), isNull);
    expect(auth.loginCalls, 0);
    expect(failed, 1);
    expect(mgr.lastFailure, '自动重新登录已关闭');
  });

  test('exhausting the captcha budget reports how many misreads', () async {
    final (mgr, _, client) = build(['3', '3', '3'], attempts: 3);
    expect(await client.onSessionExpired!(), isNull);
    expect(mgr.lastFailure, contains('3 次'));
    expect(mgr.lastFailure, contains('识别错 3 次'));
  });

  test('a wrong password is reported verbatim', () async {
    final (mgr, _, client) = build(['2']);
    expect(await client.onSessionExpired!(), isNull);
    expect(mgr.lastFailure, '登录名或密码不正确');
  });

  test('the contested guard is off by default: every kick re-logs in', () async {
    final (mgr, auth, client) = build(['tok-1', 'tok-2']);
    expect(await client.onSessionExpired!(), 'tok-1');
    expect(await client.onSessionExpired!(), 'tok-2');
    expect(auth.loginCalls, 2);
    expect(mgr.contested, isFalse);
  });
}
