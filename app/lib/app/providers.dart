/// Riverpod providers: the composition root wiring storage, client, services,
/// and the monitor engine, plus app-level state (theme, session, watches).
///
/// Kept hand-written (no codegen) so the project builds without build_runner.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors.dart';
import '../data/api_client.dart';
import '../data/auth_service.dart';
import '../data/captcha.dart';
import '../data/course_service.dart';
import '../data/enroll_service.dart';
import '../data/models.dart';
import '../data/monitor_engine.dart';
import '../data/notifications.dart';
import '../data/storage.dart';

/// Overridden in main() once Storage has been opened.
final storageProvider = Provider<Storage>((ref) => throw UnimplementedError());

/// The single long-lived HTTP client, seeded with the saved origin.
final apiClientProvider = Provider<ApiClient>((ref) {
  final storage = ref.watch(storageProvider);
  final client = ApiClient(origin: storage.origin());
  ref.onDispose(() {});
  return client;
});

/// The pluggable captcha solver. Defaults to no-op (manual entry); Settings can
/// swap in an OCR-backed solver at runtime.
final captchaSolverProvider = StateProvider<CaptchaSolver>((ref) => const NoopCaptchaSolver());

final authServiceProvider = Provider<AuthService>((ref) => AuthService(ref.watch(apiClientProvider)));

final courseServiceProvider = Provider<CourseService>((ref) => CourseService(ref.watch(apiClientProvider)));

final enrollServiceProvider = Provider<EnrollService>((ref) => EnrollService(ref.watch(apiClientProvider)));

final sessionManagerProvider = Provider<SessionManager>((ref) {
  final mgr = SessionManager(
    client: ref.watch(apiClientProvider),
    auth: ref.watch(authServiceProvider),
    solver: ref.watch(captchaSolverProvider),
  );
  // Keep the manager's solver in sync when the user configures OCR.
  ref.listen<CaptchaSolver>(captchaSolverProvider, (_, next) => mgr.solver = next);
  return mgr;
});

final monitorEngineProvider = Provider<MonitorEngine>((ref) {
  final storage = ref.watch(storageProvider);
  final saved = storage.monitorConfigJson();
  final cfg = saved != null
      ? MonitorConfig.fromJson(jsonDecode(saved) as Map<String, dynamic>)
      : const MonitorConfig();
  final engine = MonitorEngine(
    courseService: ref.watch(courseServiceProvider),
    enrollService: ref.watch(enrollServiceProvider),
    config: cfg,
  );
  ref.onDispose(engine.dispose);
  return engine;
});

/// Reads/updates the monitor config, persisting changes and applying them to
/// the live engine.
class MonitorConfigController extends StateNotifier<MonitorConfig> {
  MonitorConfigController(this._ref, MonitorConfig initial) : super(initial);
  final Ref _ref;

  Future<void> update(MonitorConfig cfg) async {
    state = cfg;
    _ref.read(monitorEngineProvider).config = cfg;
    await _ref.read(storageProvider).setMonitorConfigJson(jsonEncode(cfg.toJson()));
  }
}

final monitorConfigProvider =
    StateNotifierProvider<MonitorConfigController, MonitorConfig>((ref) {
  final engine = ref.watch(monitorEngineProvider);
  return MonitorConfigController(ref, engine.config);
});

// ---------------------------------------------------------------------------
// Theme
// ---------------------------------------------------------------------------

class ThemeSettings {
  ThemeSettings({required this.mode, required this.seed});
  final ThemeMode mode;
  final Color seed;

  ThemeSettings copyWith({ThemeMode? mode, Color? seed}) =>
      ThemeSettings(mode: mode ?? this.mode, seed: seed ?? this.seed);
}

class ThemeController extends StateNotifier<ThemeSettings> {
  ThemeController(this._storage)
      : super(ThemeSettings(
          mode: _modeFromIndex(_storage.themeModeIndex()),
          seed: Color(_storage.seedColor()),
        ));

  final Storage _storage;

  static ThemeMode _modeFromIndex(int i) => switch (i) {
        1 => ThemeMode.light,
        2 => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  static int _indexFromMode(ThemeMode m) => switch (m) {
        ThemeMode.light => 1,
        ThemeMode.dark => 2,
        ThemeMode.system => 0,
      };

  Future<void> setMode(ThemeMode mode) async {
    state = state.copyWith(mode: mode);
    await _storage.setThemeModeIndex(_indexFromMode(mode));
  }

  /// Cycles system -> light -> dark -> system for a one-tap toggle.
  Future<void> cycleMode() async {
    final next = switch (state.mode) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    await setMode(next);
  }

  Future<void> setSeed(Color seed) async {
    state = state.copyWith(seed: seed);
    await _storage.setSeedColor(seed.toARGB32());
  }
}

final themeControllerProvider =
    StateNotifierProvider<ThemeController, ThemeSettings>((ref) => ThemeController(ref.watch(storageProvider)));

// ---------------------------------------------------------------------------
// Session / account state
// ---------------------------------------------------------------------------

/// High-level auth state for the UI.
enum AuthPhase { loggedOut, loggingIn, loggedIn }

class SessionState {
  SessionState({
    this.phase = AuthPhase.loggedOut,
    this.student,
    this.batches = const [],
    this.activeBatch,
    this.account,
    this.error,
  });

  final AuthPhase phase;
  final StudentInfo? student;
  final List<ElectiveBatch> batches;
  final ElectiveBatch? activeBatch;
  final Account? account;
  final String? error;

  SessionState copyWith({
    AuthPhase? phase,
    StudentInfo? student,
    List<ElectiveBatch>? batches,
    ElectiveBatch? activeBatch,
    Account? account,
    String? error,
    bool clearError = false,
  }) =>
      SessionState(
        phase: phase ?? this.phase,
        student: student ?? this.student,
        batches: batches ?? this.batches,
        activeBatch: activeBatch ?? this.activeBatch,
        account: account ?? this.account,
        error: clearError ? null : (error ?? this.error),
      );
}

class SessionController extends StateNotifier<SessionState> {
  SessionController(this._ref) : super(SessionState());

  final Ref _ref;

  SessionManager get _mgr => _ref.read(sessionManagerProvider);
  Storage get _storage => _ref.read(storageProvider);

  /// Fetches a fresh captcha challenge for the login screen.
  Future<CaptchaChallenge> fetchCaptcha() => _mgr.auth.fetchCaptcha();

  /// Performs interactive login and persists the account (password secured).
  Future<void> login({
    required String loginName,
    required String password,
    required String verifyCode,
    required String vtoken,
    bool remember = true,
  }) async {
    state = state.copyWith(phase: AuthPhase.loggingIn, clearError: true);
    try {
      await _mgr.loginInteractive(
        loginName: loginName,
        password: password,
        verifyCode: verifyCode,
        vtoken: vtoken,
      );
      final account = Account(
        id: loginName,
        loginName: loginName,
        displayName: _mgr.student?.name.isNotEmpty == true ? _mgr.student!.name : loginName,
        studentCode: _mgr.studentCode ?? '',
        lastBatchCode: _mgr.activeBatch?.code ?? '',
        lastToken: _mgr.client.token ?? '',
      );
      if (remember) {
        await _storage.upsertAccount(account, password: password);
        await _storage.setActiveAccount(account.id);
      }
      state = SessionState(
        phase: AuthPhase.loggedIn,
        student: _mgr.student,
        batches: _mgr.batches,
        activeBatch: _mgr.activeBatch,
        account: account,
      );
      // Now that the user is in, ask for notification permission so grab/seat
      // alerts can reach them when the app is backgrounded.
      await NotificationService.instance.requestPermission();
    } catch (e) {
      state = state.copyWith(phase: AuthPhase.loggedOut, error: _describe(e));
      rethrow;
    }
  }

  /// Logs in a saved account using its stored password (still needs a captcha).
  Future<void> loginSavedAccount({
    required Account account,
    required String verifyCode,
    required String vtoken,
  }) async {
    final pw = await _storage.passwordFor(account.id);
    if (pw == null) {
      throw LoginException('0', '未找到该账号的已保存密码，请重新登录');
    }
    await login(
      loginName: account.loginName,
      password: pw,
      verifyCode: verifyCode,
      vtoken: vtoken,
    );
  }

  void setActiveBatch(ElectiveBatch batch) {
    _mgr.activeBatch = batch;
    state = state.copyWith(activeBatch: batch);
  }

  Future<void> logout() async {
    _ref.read(monitorEngineProvider).stop();
    _ref.read(apiClientProvider).token = null;
    await _ref.read(apiClientProvider).clearCookies();
    state = SessionState();
  }

  String _describe(Object e) {
    if (e is AppError) return e.hint != null ? '${e.message} · ${e.hint}' : e.message;
    if (e is LoginException) return e.message;
    return e.toString();
  }
}

final sessionProvider =
    StateNotifierProvider<SessionController, SessionState>((ref) => SessionController(ref));

/// The list of saved accounts (rebuilds when storage changes via refresh()).
final accountsProvider = StateNotifierProvider<AccountsController, List<Account>>(
    (ref) => AccountsController(ref.watch(storageProvider)));

class AccountsController extends StateNotifier<List<Account>> {
  AccountsController(this._storage) : super(_storage.accounts());
  final Storage _storage;

  void refresh() => state = _storage.accounts();

  Future<void> remove(String id) async {
    await _storage.removeAccount(id);
    refresh();
  }
}
