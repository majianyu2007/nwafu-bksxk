/// 一次登录: the selection system (bksxk) takes the same student ID and
/// password as the unified identity, so when the identity is signed in with
/// a remembered password and no selection account is signed in, the shell
/// signs into bksxk on its own instead of showing the login form.
///
/// It goes through the normal captcha login (session-less captcha client,
/// on-device OCR, `SessionController.login`), with a small budget: the school
/// gateway blocks clients that fetch `vcode.do` too often, and the account is
/// frozen for logging in from too many clients. So it runs at most once per
/// app session, never while another login is in flight, and any failure
/// leaves the regular (prefilled) login form. Only the user's tap retries.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors.dart';
import '../data/auth_service.dart';
import 'edu_providers.dart';
import 'providers.dart';

enum AutoSelectionPhase {
  /// Nothing to do, or not tried yet.
  idle,
  running,

  /// Gave up; [AutoSelectionLoginState.message] says why.
  failed,
}

class AutoSelectionLoginState {
  const AutoSelectionLoginState({
    this.phase = AutoSelectionPhase.idle,
    this.message = '',
    this.attempt = 0,
  });
  final AutoSelectionPhase phase;
  final String message;
  final int attempt;
  bool get running => phase == AutoSelectionPhase.running;
}

class AutoSelectionLogin extends StateNotifier<AutoSelectionLoginState> {
  AutoSelectionLogin(
    this._ref, {
    this.pause = const Duration(milliseconds: 800),
  }) : super(const AutoSelectionLoginState());

  final Ref _ref;

  /// One automatic run per app session, whatever the identity: a failed
  /// run is never repeated on its own (the school freezes accounts that
  /// log in from too many clients). Only an explicit tap retries.
  bool _autoUsed = false;
  bool _busy = false;

  /// Captcha fetches per run (each one is a `vcode.do` request).
  static const maxCaptchas = 3;

  /// Pause between captcha fetches, to stay well under the gateway's limit.
  final Duration pause;

  /// The student ID that would be signed in, when the conditions hold:
  /// a password-signed-in identity and no selection account signed in.
  String? get candidate {
    final account = _ref.read(eduSessionProvider).account;
    if (account == null || account.usePasskey) return null;
    if (_ref.read(signedInAccountsProvider).isNotEmpty) return null;
    return account.username;
  }

  /// Whether the session controller for [id] is in the middle of a login
  /// started elsewhere (the login form, the re-login dialog).
  bool _loginInFlight(String id) =>
      _ref.read(sessionControllerProvider(id)).phase == AuthPhase.loggingIn;

  /// Signs in if the conditions hold. Without [force] this runs at most once
  /// per app session; [force] is for the user's own 再试一次. Never starts
  /// while another login is in flight. Returns true when a selection
  /// account was signed in.
  Future<bool> ensure({bool force = false}) async {
    final id = candidate;
    if (id == null || _busy || state.running) return false;
    if (!force && _autoUsed) return false;
    if (_loginInFlight(id)) return false;
    _busy = true;
    try {
      return await _run(id, consumeAutoBudget: !force);
    } finally {
      _busy = false;
    }
  }

  Future<bool> _run(String id, {required bool consumeAutoBudget}) async {
    final password = await _ref.read(storageProvider).eduPassword(id);
    if (!mounted) return false;
    if (password == null || password.isEmpty) {
      state = const AutoSelectionLoginState();
      return false;
    }
    if (consumeAutoBudget) _autoUsed = true;
    final edu = _ref.read(eduSessionProvider.notifier);
    final epoch = edu.epoch;
    bool stillWanted() =>
        mounted &&
        edu.isCurrent(epoch) &&
        _ref.read(signedInAccountsProvider).isEmpty &&
        !_loginInFlight(id);

    var misreads = 0;
    String? failure;
    for (var attempt = 1; attempt <= maxCaptchas; attempt++) {
      if (!stillWanted()) return _stop();
      state = AutoSelectionLoginState(
        phase: AutoSelectionPhase.running,
        attempt: attempt,
      );
      if (attempt > 1) {
        await Future<void>.delayed(pause);
        if (!stillWanted()) return _stop();
      }
      try {
        final challenge = await _ref.read(anonymousAuthProvider).fetchCaptcha();
        final code = await _ref
            .read(captchaSolverProvider)
            .solve(challenge.imageBytes);
        if (code == null || code.isEmpty) {
          misreads++;
          continue;
        }
        if (!stillWanted()) return _stop();
        await _ref
            .read(sessionControllerProvider(id).notifier)
            .login(
              loginName: id,
              password: password,
              verifyCode: code,
              vtoken: challenge.vtoken,
            );
        if (!stillWanted()) {
          // The identity changed while logging in; do not keep its session.
          if (mounted) await leaveAccountFrom(_ref, id);
          return _stop();
        }
        _ref.read(accountsProvider.notifier).refresh();
        enterAccountFrom(_ref, id);
        state = const AutoSelectionLoginState();
        return true;
      } on LoginException catch (e) {
        if (e.code == '3') {
          misreads++;
          continue;
        }
        failure = e.code == '2'
            ? '选课系统没接受统一身份认证的密码，请手动登录'
            : e.message;
        break;
      } on AppError catch (e) {
        failure = e.kind == AppErrorKind.campusNetwork
            ? '连不上选课系统，它只在校园网内可用'
            : e.message;
        break;
      } catch (e) {
        failure = '自动登录选课系统没成功';
        break;
      }
    }
    if (!mounted) return false;
    state = AutoSelectionLoginState(
      phase: AutoSelectionPhase.failed,
      message: failure ?? '验证码自动识别 $misreads 次没通过，请手动登录',
    );
    return false;
  }

  bool _stop() {
    if (mounted) state = const AutoSelectionLoginState();
    return false;
  }

  /// Clears a failure message (e.g. after the identity changed). Does not
  /// re-arm the once-per-session automatic run.
  void forget() {
    if (mounted && !state.running) state = const AutoSelectionLoginState();
  }
}

final autoSelectionLoginProvider =
    StateNotifierProvider<AutoSelectionLogin, AutoSelectionLoginState>((ref) {
      final auto = AutoSelectionLogin(ref);
      // A new identity clears an old failure message; the automatic run
      // itself stays spent for this session.
      ref.listen<String?>(
        eduSessionProvider.select((s) => s.account?.username),
        (_, _) => auto.forget(),
      );
      return auto;
    });
