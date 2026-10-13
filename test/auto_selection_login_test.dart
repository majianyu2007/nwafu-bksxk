import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nwafu_bksxk/app/auto_selection_login.dart';
import 'package:nwafu_bksxk/app/edu_providers.dart';
import 'package:nwafu_bksxk/app/providers.dart';
import 'package:nwafu_bksxk/core/errors.dart';
import 'package:nwafu_bksxk/data/api_client.dart';
import 'package:nwafu_bksxk/data/auth_service.dart';
import 'package:nwafu_bksxk/data/captcha.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/edu_fixtures.dart';

class _Auth extends AuthService {
  _Auth() : super(ApiClient(origin: 'https://example.invalid'));
  int requests = 0;
  @override
  Future<CaptchaChallenge> fetchCaptcha() async =>
      CaptchaChallenge(vtoken: 'v${++requests}', imageBytes: const []);
}

/// Answers each login with the next outcome: null = success, a string =
/// LoginException code, an AppError = thrown as is.
class _Session extends SessionController {
  _Session(super.ref, super.accountId, this.outcomes);
  final List<Object?> outcomes;
  final logins = <({String name, String password, String vtoken})>[];
  bool loggedOut = false;

  @override
  Future<void> login({
    required String loginName,
    required String password,
    required String verifyCode,
    required String vtoken,
    bool remember = true,
  }) async {
    logins.add((name: loginName, password: password, vtoken: vtoken));
    final o = outcomes.isEmpty ? null : outcomes.removeAt(0);
    if (o is String) throw LoginException(o, '模拟失败');
    if (o is AppError) throw o;
  }

  @override
  Future<void> logout() async => loggedOut = true;
}

Future<
  ({
    ProviderContainer c,
    _Auth auth,
    MemoryEduStorage storage,
    Map<String, _Session> sessions,
  })
>
setup({
  List<Object?> outcomes = const [],
  String? password = 'secret',
  bool passkey = false,
  Future<String?> Function(List<int>)? ocr,
}) async {
  SharedPreferences.setMockInitialValues({});
  final storage = MemoryEduStorage(await SharedPreferences.getInstance());
  await storage.setEduAccount(
    EduAccount(username: '2024012001', usePasskey: passkey).encode(),
  );
  if (password != null) storage.passwords['2024012001'] = password;
  final auth = _Auth();
  final sessions = <String, _Session>{};
  final c = ProviderContainer(
    overrides: [
      storageProvider.overrideWithValue(storage),
      anonymousAuthProvider.overrideWithValue(auth),
      captchaSolverProvider.overrideWithValue(
        OcrCaptchaSolver(ocr ?? (_) async => 'ab12'),
      ),
      sessionControllerProvider.overrideWith(
        (ref, id) => sessions[id] = _Session(ref, id, [...outcomes]),
      ),
      autoSelectionLoginProvider.overrideWith(
        (ref) => AutoSelectionLogin(ref, pause: Duration.zero),
      ),
    ],
  );
  addTearDown(c.dispose);
  return (c: c, auth: auth, storage: storage, sessions: sessions);
}

void main() {
  test('signs in with the unified password and shows the account', () async {
    final s = await setup();
    final ok = await s.c.read(autoSelectionLoginProvider.notifier).ensure();
    expect(ok, isTrue);
    final session = s.sessions['2024012001']!;
    expect(session.logins.single.password, 'secret');
    expect(s.c.read(signedInAccountsProvider), ['2024012001']);
    expect(s.c.read(activeAccountIdProvider), '2024012001');
    // Once per identity: a second call does nothing.
    expect(await s.c.read(autoSelectionLoginProvider.notifier).ensure(), isFalse);
    expect(s.auth.requests, 1);
  });

  test('misread captchas use at most the small budget', () async {
    final s = await setup(outcomes: List.filled(10, '3'));
    final auto = s.c.read(autoSelectionLoginProvider.notifier);
    expect(await auto.ensure(), isFalse);
    expect(s.auth.requests, AutoSelectionLogin.maxCaptchas);
    final state = s.c.read(autoSelectionLoginProvider);
    expect(state.phase, AutoSelectionPhase.failed);
    expect(state.message, contains('验证码'));
    expect(s.c.read(signedInAccountsProvider), isEmpty);
    // Not retried on its own; only when the user asks again.
    expect(await auto.ensure(), isFalse);
    expect(s.auth.requests, AutoSelectionLogin.maxCaptchas);
    await auto.ensure(force: true);
    expect(s.auth.requests, AutoSelectionLogin.maxCaptchas * 2);
  });

  test('unreadable captchas count against the budget too', () async {
    final s = await setup(ocr: (_) async => null);
    expect(
      await s.c.read(autoSelectionLoginProvider.notifier).ensure(),
      isFalse,
    );
    expect(s.auth.requests, AutoSelectionLogin.maxCaptchas);
    expect(s.sessions['2024012001']?.logins ?? const [], isEmpty);
  });

  test('one automatic run per app session, even after an identity change',
      () async {
    final s = await setup(outcomes: List.filled(10, '3'));
    final auto = s.c.read(autoSelectionLoginProvider.notifier);
    await auto.ensure();
    expect(s.auth.requests, AutoSelectionLogin.maxCaptchas);
    // The identity signs in again (same or another student): no new run.
    auto.forget();
    expect(await auto.ensure(), isFalse);
    expect(s.auth.requests, AutoSelectionLogin.maxCaptchas);
  });

  test('concurrent calls collapse into one run', () async {
    final s = await setup(outcomes: List.filled(10, '3'));
    final auto = s.c.read(autoSelectionLoginProvider.notifier);
    await Future.wait([
      auto.ensure(),
      auto.ensure(),
      auto.ensure(force: true),
    ]);
    expect(s.auth.requests, AutoSelectionLogin.maxCaptchas);
  });

  test('never starts while another login is in flight', () async {
    final s = await setup();
    final session = s.c.read(sessionControllerProvider('2024012001').notifier);
    session.state = session.state.copyWith(phase: AuthPhase.loggingIn);
    final auto = s.c.read(autoSelectionLoginProvider.notifier);
    expect(await auto.ensure(), isFalse);
    expect(await auto.ensure(force: true), isFalse);
    expect(s.auth.requests, 0);
  });

  test('a rejected password stops at once', () async {
    final s = await setup(outcomes: ['2']);
    await s.c.read(autoSelectionLoginProvider.notifier).ensure();
    expect(s.auth.requests, 1);
    expect(s.c.read(autoSelectionLoginProvider).message, contains('密码'));
  });

  test('off campus stops at once', () async {
    final s = await setup(
      outcomes: [AppError(AppErrorKind.campusNetwork, message: 'x')],
    );
    await s.c.read(autoSelectionLoginProvider.notifier).ensure();
    expect(s.auth.requests, 1);
    expect(s.c.read(autoSelectionLoginProvider).message, contains('校园网'));
  });

  test('nothing happens without a saved password or with a passkey', () async {
    for (final s in [await setup(password: null), await setup(passkey: true)]) {
      expect(
        await s.c.read(autoSelectionLoginProvider.notifier).ensure(),
        isFalse,
      );
      expect(s.auth.requests, 0);
      expect(
        s.c.read(autoSelectionLoginProvider).phase,
        AutoSelectionPhase.idle,
      );
    }
  });

  test('nothing happens when a selection account is already in', () async {
    final s = await setup();
    s.c.read(signedInAccountsProvider.notifier).state = ['other'];
    expect(
      await s.c.read(autoSelectionLoginProvider.notifier).ensure(),
      isFalse,
    );
    expect(s.auth.requests, 0);
  });

  test('identity logout signs out the same student only', () async {
    final s = await setup();
    await s.c.read(autoSelectionLoginProvider.notifier).ensure();
    // A second, unrelated selection account (multi-account tabs).
    s.c.read(sessionControllerProvider('other'));
    s.c.read(signedInAccountsProvider.notifier).state = [
      ...s.c.read(signedInAccountsProvider),
      'other',
    ];
    final mine = s.sessions['2024012001']!;
    await s.c.read(eduSessionProvider.notifier).logout();
    expect(mine.loggedOut, isTrue);
    expect(s.sessions['other']!.loggedOut, isFalse);
    expect(s.c.read(signedInAccountsProvider), ['other']);
  });
}
