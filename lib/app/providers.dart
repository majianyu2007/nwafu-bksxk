/// Riverpod providers: the composition root wiring storage, client, services,
/// and the monitor engine, plus app-level state (theme, session, watches).
///
/// Kept hand-written (no codegen) so the project builds without build_runner.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors.dart';
import '../data/api_client.dart';
import '../data/auth_service.dart';
import '../data/captcha.dart';
import '../data/course_service.dart';
import '../data/enroll_service.dart';
import '../data/http_ocr_solver.dart';
import '../data/info_service.dart';
import '../data/captcha_solver_factory.dart';
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
/// The user's OCR-API config, or null to use the built-in on-device model.
class OcrApiController extends StateNotifier<OcrApiConfig?> {
  OcrApiController(this._storage) : super(_load(_storage));
  final Storage _storage;

  static OcrApiConfig? _load(Storage s) {
    final raw = s.ocrApiConfigJson();
    if (raw == null) return null;
    try {
      return OcrApiConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> set(OcrApiConfig? cfg) async {
    state = cfg;
    await _storage
        .setOcrApiConfigJson(cfg == null ? null : jsonEncode(cfg.toJson()));
  }
}

final ocrApiProvider = StateNotifierProvider<OcrApiController, OcrApiConfig?>(
    (ref) => OcrApiController(ref.watch(storageProvider)));

/// The active captcha solver. Uses the user's OCR API if configured and valid,
/// otherwise the built-in on-device model (no-op on web). Rebuilds when the OCR
/// API config changes. If solve() returns null the UI falls back to manual entry.
final captchaSolverProvider = StateProvider<CaptchaSolver>((ref) {
  final api = ref.watch(ocrApiProvider);
  if (api != null && api.isValid) {
    return HttpOcrCaptchaSolver(api);
  }
  final solver = createCaptchaSolver();
  ref.onDispose(() => disposeCaptchaSolver(solver));
  return solver;
});

final authServiceProvider =
    Provider<AuthService>((ref) => AuthService(ref.watch(apiClientProvider)));

final courseServiceProvider = Provider<CourseService>(
    (ref) => CourseService(ref.watch(apiClientProvider)));

final enrollServiceProvider = Provider<EnrollService>(
    (ref) => EnrollService(ref.watch(apiClientProvider)));
final infoServiceProvider =
    Provider<InfoService>((ref) => InfoService(ref.watch(apiClientProvider)));

/// Monotonic signal for server-backed selection data. Every successful
/// enrollment mutation or batch switch increments it; dependent providers then
/// refetch instead of leaving stale state until a manual refresh.
final selectionDataRevisionProvider = StateProvider<int>((ref) => 0);

/// How many captcha attempts a silent re-login may spend (Settings).
class SilentReloginController extends StateNotifier<int> {
  SilentReloginController(this._storage)
      : super(_storage.silentReloginAttempts());
  final Storage _storage;

  Future<void> set(int attempts) async {
    state = attempts;
    await _storage.setSilentReloginAttempts(attempts);
  }
}

final silentReloginAttemptsProvider =
    StateNotifierProvider<SilentReloginController, int>(
        (ref) => SilentReloginController(ref.watch(storageProvider)));

final sessionManagerProvider = Provider<SessionManager>((ref) {
  final mgr = SessionManager(
    client: ref.watch(apiClientProvider),
    auth: ref.watch(authServiceProvider),
    solver: ref.watch(captchaSolverProvider),
    info: ref.watch(infoServiceProvider),
  );
  // Keep the manager's solver in sync when the user configures OCR.
  ref.listen<CaptchaSolver>(
      captchaSolverProvider, (_, next) => mgr.solver = next);
  mgr.maxSilentReloginAttempts = ref.read(silentReloginAttemptsProvider);
  ref.listen<int>(silentReloginAttemptsProvider,
      (_, next) => mgr.maxSilentReloginAttempts = next);
  // A dropped session that silent re-login could not recover is surfaced by
  // the session controller (dialog + notification, monitor paused).
  mgr.onSilentReloginFailed =
      () => ref.read(sessionProvider.notifier).markSessionExpired();
  mgr.onSilentReloginSucceeded = (token) =>
      ref.read(sessionProvider.notifier).onSilentReloginSucceeded(token);
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
    await _ref
        .read(storageProvider)
        .setMonitorConfigJson(jsonEncode(cfg.toJson()));
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
    StateNotifierProvider<ThemeController, ThemeSettings>(
        (ref) => ThemeController(ref.watch(storageProvider)));

// ---------------------------------------------------------------------------
// Session / account state
// ---------------------------------------------------------------------------

/// High-level auth state for the UI.
enum AuthPhase {
  loggedOut,
  loggingIn,
  loggedIn,

  /// The server dropped the session and silent re-login failed. The shell
  /// stays mounted and asks the user to log in again in a dialog.
  expired,
}

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

  /// Whether the monitor was running when the session dropped, so a
  /// successful re-login can start it again.
  bool _resumeMonitorAfterRelogin = false;

  /// Fetches a fresh captcha challenge for the login screen.
  Future<CaptchaChallenge> fetchCaptcha() => _mgr.auth.fetchCaptcha();

  /// Called when the API client detected an expired session and the silent
  /// re-login budget is spent. Pauses the monitor (without failing watches),
  /// notifies, and flips the phase so the shell shows the re-login dialog.
  void markSessionExpired() {
    if (state.phase != AuthPhase.loggedIn) return;
    final engine = _ref.read(monitorEngineProvider);
    _resumeMonitorAfterRelogin = engine.isRunning || engine.haltedForSession;
    engine.haltForSession();
    state = state.copyWith(
      phase: AuthPhase.expired,
      error: '登录已失效，自动重新登录未成功',
    );
    NotificationService.instance.sessionExpired();
  }

  /// A silent re-login recovered the session: remember the new token so a
  /// warm start next launch uses it.
  Future<void> onSilentReloginSucceeded(String token) async {
    final account = state.account;
    if (account == null) return;
    final updated = account.copyWith(lastToken: token);
    state = state.copyWith(account: updated);
    await _storage.upsertAccount(updated);
  }

  /// Interactive re-login from the expired-session dialog. Keeps the shell
  /// (phase stays [AuthPhase.expired] until success), keeps the active round
  /// when it still exists, and restarts the monitor if it had been running.
  Future<void> relogin({
    required String password,
    required String verifyCode,
    required String vtoken,
  }) async {
    final account = state.account;
    final loginName = account?.loginName ?? state.student?.studentCode ?? '';
    if (loginName.isEmpty) throw LoginException('0', '没有可用的账号信息，请退出后重新登录');
    state = state.copyWith(clearError: true);
    final previousActive = state.activeBatch?.code;
    await _mgr.loginInteractive(
      loginName: loginName,
      password: password,
      verifyCode: verifyCode,
      vtoken: vtoken,
    );
    ElectiveBatch? active;
    for (final b in _mgr.batches) {
      if (b.code == previousActive) active = b;
    }
    active ??= _mgr.activeBatch;
    _mgr.activeBatch = active;
    final updated = (account ??
            Account(
              id: loginName,
              loginName: loginName,
              displayName: _mgr.student?.name ?? loginName,
              studentCode: _mgr.studentCode ?? '',
            ))
        .copyWith(lastToken: _mgr.client.token ?? '');
    await _storage.upsertAccount(updated, password: password);
    state = SessionState(
      phase: AuthPhase.loggedIn,
      student: _mgr.student,
      batches: _mgr.batches,
      activeBatch: active,
      account: updated,
    );
    _ref.read(selectionDataRevisionProvider.notifier).state++;
    if (_resumeMonitorAfterRelogin) {
      _resumeMonitorAfterRelogin = false;
      _ref.read(monitorEngineProvider).start();
    }
  }

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
        displayName: _mgr.student?.name.isNotEmpty == true
            ? _mgr.student!.name
            : loginName,
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
      // Native platforms can request from the signed-in flow. Browsers require
      // a direct, explicit action, exposed in Settings.
      if (!kIsWeb) await NotificationService.instance.requestPermission();
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

  Future<void> setActiveBatch(ElectiveBatch batch) async {
    final changed = state.activeBatch?.code != batch.code;
    _mgr.activeBatch = batch;
    state = state.copyWith(activeBatch: batch);
    await _confirmBatchIfOpen(batch);
    // Re-picking the same batch (the post-login dialog usually confirms the
    // auto-selected one) changes no server-side data, so don't refetch.
    if (changed) _ref.read(selectionDataRevisionProvider.notifier).state++;
  }

  /// Mirrors the official post-login flow: acknowledge the round's notice
  /// (student/xklcqr.do) when a selectable round that requires confirmation
  /// (needConfirm "1", not yet confirmed) becomes active. Rounds without a
  /// notice are entered directly, exactly as the official page does.
  Future<void> _confirmBatchIfOpen(ElectiveBatch batch) async {
    final studentCode = state.student?.studentCode;
    if (!batch.canSelect || !batch.needsNoticeConfirmation) return;
    if (studentCode == null || studentCode.isEmpty) return;
    try {
      await _ref.read(authServiceProvider).confirmBatch(
            studentCode: studentCode,
            batchCode: batch.code,
          );
    } catch (_) {
      // Selection remains active for browsing; write calls surface a concrete
      // rejection if the server requires confirmation and this request failed.
    }
  }

  Future<void> reloadContext() async {
    final code = _mgr.studentCode ?? state.student?.studentCode;
    if (code == null || code.isEmpty) return;
    final (student, batches) = await _mgr.auth.loadContext(code);
    final previousStudent = state.student;
    final mergedStudent = student.copyWith(
      name: student.name.isEmpty ? previousStudent?.name : student.name,
      campus: student.campus.isEmpty ? previousStudent?.campus : student.campus,
      collegeName: student.collegeName.isEmpty
          ? previousStudent?.collegeName
          : student.collegeName,
      majorName: student.majorName.isEmpty
          ? previousStudent?.majorName
          : student.majorName,
      grade: student.grade.isEmpty ? previousStudent?.grade : student.grade,
      schoolClassName: student.schoolClassName.isEmpty
          ? previousStudent?.schoolClassName
          : student.schoolClassName,
    );
    ElectiveBatch? active;
    final previousCode = state.activeBatch?.code;
    if (previousCode != null) {
      for (final batch in batches) {
        if (batch.code == previousCode) {
          active = batch;
          break;
        }
      }
    }
    active ??= selectInitialBatch(batches).batch;
    // A round that just opened (the usual reason to hit refresh before a rush)
    // still needs the notice acknowledgement that setActiveBatch performs.
    final previous = state.activeBatch;
    final alreadyConfirmed =
        previous != null && previous.code == active?.code && previous.canSelect;
    _mgr.student = mergedStudent;
    _mgr.batches = batches;
    _mgr.activeBatch = active;
    state = SessionState(
      phase: AuthPhase.loggedIn,
      student: mergedStudent,
      batches: batches,
      activeBatch: active,
      account: state.account,
    );
    if (active != null && !alreadyConfirmed) await _confirmBatchIfOpen(active);
    _ref.read(selectionDataRevisionProvider.notifier).state++;
  }

  Future<void> logout() async {
    _ref.read(monitorEngineProvider).stop();
    final code = state.student?.studentCode;
    // Best-effort server-side logout so the school session terminates cleanly;
    // cookies + token are dropped locally either way.
    if (code != null && code.isNotEmpty) {
      try {
        await _ref.read(authServiceProvider).logout(code);
      } catch (_) {
        // local cleanup below is unconditional.
      }
    }
    _ref.read(apiClientProvider).token = null;
    await _ref.read(apiClientProvider).clearCookies();
    state = SessionState();
  }

  String _describe(Object e) {
    if (e is AppError) {
      return e.hint != null ? '${e.message} · ${e.hint}' : e.message;
    }
    if (e is LoginException) return e.message;
    return e.toString();
  }
}

final sessionProvider = StateNotifierProvider<SessionController, SessionState>(
    (ref) => SessionController(ref));

/// The list of saved accounts (rebuilds when storage changes via refresh()).
final accountsProvider =
    StateNotifierProvider<AccountsController, List<Account>>(
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
