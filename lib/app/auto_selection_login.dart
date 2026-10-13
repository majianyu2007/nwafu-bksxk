/// 一次登录: the selection system (bksxk) takes the same student ID and
/// password as the unified identity, so when the identity is signed in with
/// a remembered password and no selection account is signed in, the shell
/// signs into bksxk on its own instead of showing the login form.
///
/// It goes through the normal captcha login (session-less captcha client,
/// on-device OCR, `SessionController.login`), with a small budget: the school
/// gateway blocks clients that fetch `vcode.do` too often. It runs at most
/// once per identity per app run unless the user asks again; any failure
/// leaves the regular (prefilled) login form.
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
  final _tried = <String>{};

  /// Captcha fetches per attempt run (each one is a `vcode.do` request).
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

  /// Signs in if the conditions hold and it has not been tried for this
  /// identity yet ([force] = the user asked again). Returns true when a
  /// selection account was signed in.
  Future<bool> ensure({bool force = false}) async {
    final id = candidate;
    if (id == null || state.running) return false;
    if (!force && _tried.contains(id)) return false;
    _tried.add(id);
    final password = await _ref.read(storageProvider).eduPassword(id);
    if (!mounted) return false;
    if (password == null || password.isEmpty) {
      state = const AutoSelectionLoginState();
      return false;
    }
    final edu = _ref.read(eduSessionProvider.notifier);
    final epoch = edu.epoch;
    bool stillWanted() =>
        mounted &&
        edu.isCurrent(epoch) &&
        _ref.read(signedInAccountsProvider).isEmpty;

    var misreads = 0;
    String? failure;
    for (var attempt = 1; attempt <= maxCaptchas; attempt++) {
      if (!stillWanted()) return _stop();
      state = AutoSelectionLoginState(
        phase: AutoSelectionPhase.running,
        attempt: attempt,
      );
      if (attempt > 1) await Future<void>.delayed(pause);
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

  /// Clears the once-per-identity memory and any failure message.
  void forget() {
    _tried.clear();
    if (mounted && !state.running) state = const AutoSelectionLoginState();
  }
}

final autoSelectionLoginProvider =
    StateNotifierProvider<AutoSelectionLogin, AutoSelectionLoginState>((ref) {
      final auto = AutoSelectionLogin(ref);
      // A new sign-in of the identity gets a fresh try.
      ref.listen<String?>(
        eduSessionProvider.select((s) => s.account?.username),
        (_, _) => auto.forget(),
      );
      return auto;
    });
