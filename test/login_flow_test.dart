import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nwafu_bksxk/app/providers.dart';
import 'package:nwafu_bksxk/app/update_providers.dart';
import 'package:nwafu_bksxk/data/api_client.dart';
import 'package:nwafu_bksxk/data/auth_service.dart';
import 'package:nwafu_bksxk/data/captcha.dart';
import 'package:nwafu_bksxk/data/storage.dart';
import 'package:nwafu_bksxk/data/update_service.dart';
import 'package:nwafu_bksxk/ui/login_page.dart';
import 'package:nwafu_bksxk/ui/relogin_dialog.dart';

class _Storage extends Storage {
  _Storage(super.prefs);
  final passwords = <String, Future<String?>>{};
  @override
  Future<String?> passwordFor(String id) async => passwords[id];
}

class _Auth extends AuthService {
  _Auth() : super(ApiClient(origin: 'https://example.invalid'));
  int requests = 0;
  @override
  Future<CaptchaChallenge> fetchCaptcha() async =>
      CaptchaChallenge(vtoken: 'challenge-${++requests}', imageBytes: []);
}

class _Session extends SessionController {
  _Session(super.ref, super.accountId, this.auth, this.failures);
  final _Auth auth;
  final List<String> failures;
  int attempts = 0;
  final tokens = <String>[];
  Future<void> attempt(String token) async {
    tokens.add(token);
    final index = attempts++;
    if (index < failures.length) {
      throw LoginException(failures[index], '模拟登录失败');
    }
  }

  @override
  Future<CaptchaChallenge> fetchCaptcha() => auth.fetchCaptcha();
  @override
  Future<void> login({
    required String loginName,
    required String password,
    required String verifyCode,
    required String vtoken,
    bool remember = true,
  }) => attempt(vtoken);
  @override
  Future<void> relogin({
    required String password,
    required String verifyCode,
    required String vtoken,
  }) => attempt(vtoken);
}

Future<(_Storage, ProviderContainer, _Auth)> setup(
  List<String> failures, {
  CaptchaSolver? solver,
}) async {
  SharedPreferences.setMockInitialValues({});
  final storage = _Storage(await SharedPreferences.getInstance());
  final auth = _Auth();
  final service = UpdateService();
  final container = ProviderContainer(
    overrides: [
      storageProvider.overrideWithValue(storage),
      anonymousAuthProvider.overrideWithValue(auth),
      captchaSolverProvider.overrideWithValue(
        solver ?? OcrCaptchaSolver((_) async => '1234'),
      ),
      sessionControllerProvider.overrideWith(
        (ref, id) => _Session(ref, id, auth, failures),
      ),
      // No version/network work in login widget tests.
      updatesProvider.overrideWith(
        (ref) => UpdatesController(
          service: service,
          storage: storage,
          isWeb: false,
          bridgeInstalled: () => false,
          bridgeVersion: () => null,
        ),
      ),
    ],
  );
  addTearDown(() {
    container.dispose();
    service.dispose();
  });
  return (storage, container, auth);
}

Widget page(
  ProviderContainer container, {
  Widget child = const LoginPage(),
  double scale = 1,
}) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: child,
    ),
  ),
);

Future<void> _savedAccount(
  _Storage storage,
  String id, {
  String? password,
}) async {
  await storage.upsertAccount(Account(id: id, loginName: id, displayName: id));
  storage.passwords[id] = Future.value(password);
}

void main() {
  testWidgets(
    'OCR retries after releasing submit guard and uses a fresh token',
    (tester) async {
      final (storage, container, auth) = await setup(['3']);
      await _savedAccount(storage, 'student', password: 'password');
      await storage.setActiveAccount('student');
      await tester.pumpWidget(page(container));
      await tester.pumpAndSettle();
      final session =
          container.read(sessionControllerProvider('student').notifier)
              as _Session;
      expect(session.attempts, 2);
      expect(session.tokens, ['challenge-1', 'challenge-2']);
      expect(auth.requests, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'OCR retry budget ends in manual entry; wrong password never retries',
    (tester) async {
      for (final failures in [
        List.filled(8, '3'),
        ['2'],
      ]) {
        final (storage, container, auth) = await setup(failures);
        await _savedAccount(storage, 'student', password: 'password');
        await storage.setActiveAccount('student');
        await tester.pumpWidget(page(container));
        await tester.pumpAndSettle();
        final session =
            container.read(sessionControllerProvider('student').notifier)
                as _Session;
        expect(session.attempts, failures.first == '3' ? 5 : 1);
        expect(auth.requests, session.attempts + 1);
        expect(container.read(signedInAccountsProvider), isEmpty);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  testWidgets(
    'switching to an account without a saved password clears the old password',
    (tester) async {
      final (storage, container, _) = await setup(
        [],
        solver: OcrCaptchaSolver((_) async => null),
      );
      await _savedAccount(storage, 'first', password: 'first-secret');
      await _savedAccount(storage, 'second');
      await tester.pumpWidget(page(container));
      await tester.pumpAndSettle();
      await tester.tap(find.text('first'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'first-secret'), findsOneWidget);
      await tester.tap(find.text('second'));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(find.byType(TextField).at(1));
      expect(field.controller!.text, isEmpty);
    },
  );

  testWidgets('late OCR cannot overwrite a manually typed captcha', (
    tester,
  ) async {
    final result = Completer<String?>();
    final (_, container, _) = await setup(
      [],
      solver: OcrCaptchaSolver((_) => result.future),
    );
    await tester.pumpWidget(page(container));
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(2), '5678');
    result.complete('1234');
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField).at(2));
    expect(field.controller!.text, '5678');
  });

  testWidgets('relogin OCR retries and stops at its own budget', (
    tester,
  ) async {
    final (storage, container, auth) = await setup(List.filled(8, '3'));
    storage.passwords['student'] = Future.value('password');
    await tester.pumpWidget(
      page(
        container,
        child: const Scaffold(body: ReloginDialog(accountId: 'student')),
      ),
    );
    await tester.pumpAndSettle();
    final session =
        container.read(sessionControllerProvider('student').notifier)
            as _Session;
    expect(session.attempts, 4);
    expect(auth.requests, 5);
    expect(tester.takeException(), isNull);
  });

  testWidgets('login fits a 320px screen with large text and a keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final (_, container, _) = await setup(
      [],
      solver: OcrCaptchaSolver((_) async => null),
    );
    await tester.pumpWidget(page(container, scale: 2));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('登录'));
    expect(tester.takeException(), isNull);
  });
}
