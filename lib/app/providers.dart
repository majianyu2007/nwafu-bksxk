/// Riverpod composition root.
///
/// Every signed-in account gets its own [SessionScope]: an HTTP client with
/// its own cookies and token, the services on top of it, the session manager
/// that re-logs it in, and a monitor engine with its own watch list. Scopes are
/// family providers keyed by the account id (the login name), so several
/// accounts can be signed in and grabbing at once; the UI shows one of them,
/// [activeAccountIdProvider], and the `current*` providers below resolve to
/// that account so pages never have to thread ids around.
///
/// Kept hand-written (no codegen) so the project builds without build_runner.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../core/errors.dart';
import '../data/api_client.dart';
import '../data/auth_service.dart';
import '../data/background.dart';
import '../data/captcha.dart';
import '../data/course_cache.dart';
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

// ---------------------------------------------------------------------------
// Global settings
// ---------------------------------------------------------------------------

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

/// The active captcha solver, shared by every session. Uses the user's OCR
/// API if configured and valid, otherwise the built-in on-device model.
final captchaSolverProvider = Provider<CaptchaSolver>((ref) {
  final api = ref.watch(ocrApiProvider);
  if (api != null && api.isValid) {
    return HttpOcrCaptchaSolver(api);
  }
  final solver = createCaptchaSolver();
  ref.onDispose(() => disposeCaptchaSolver(solver));
  return solver;
});

/// A persisted boolean setting.
class BoolSetting extends StateNotifier<bool> {
  BoolSetting(super.initial, this._save);
  final Future<void> Function(bool) _save;
  Future<void> set(bool v) async {
    state = v;
    await _save(v);
  }
}

/// Whether a dropped session is re-logged in silently at all.
final silentReloginEnabledProvider =
    StateNotifierProvider<BoolSetting, bool>((ref) {
  final s = ref.watch(storageProvider);
  return BoolSetting(s.silentReloginEnabled(), s.setSilentReloginEnabled);
});

/// Contested-session guard (off by default) and its window in minutes.
final contestedGuardProvider = StateNotifierProvider<BoolSetting, bool>((ref) {
  final s = ref.watch(storageProvider);
  return BoolSetting(s.contestedGuardEnabled(), s.setContestedGuardEnabled);
});

class IntSetting extends StateNotifier<int> {
  IntSetting(super.initial, this._save);
  final Future<void> Function(int) _save;
  Future<void> set(int v) async {
    state = v;
    await _save(v);
  }
}

final contestedWindowMinutesProvider =
    StateNotifierProvider<IntSetting, int>((ref) {
  final s = ref.watch(storageProvider);
  return IntSetting(s.contestedWindowMinutes(), s.setContestedWindowMinutes);
});

/// Several accounts at once, as tabs. Off by default.
final multiAccountProvider = StateNotifierProvider<BoolSetting, bool>((ref) {
  final s = ref.watch(storageProvider);
  return BoolSetting(s.multiAccountEnabled(), s.setMultiAccountEnabled);
});

/// Keep running after the window closes / the app is backgrounded.
final runInBackgroundProvider = StateNotifierProvider<BoolSetting, bool>((ref) {
  final s = ref.watch(storageProvider);
  return BoolSetting(s.runInBackground(), s.setRunInBackground);
});

/// Keep the device awake while a monitor runs.
final keepAwakeProvider = StateNotifierProvider<BoolSetting, bool>((ref) {
  final s = ref.watch(storageProvider);
  return BoolSetting(s.keepAwake(), s.setKeepAwake);
});

/// The on-device course-list cache (shared by every account, keyed per account).
final courseCacheProvider =
    Provider<CourseCache>((ref) => CourseCache(ref.watch(storageProvider)));

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

/// The monitor cadence/safety config, shared by every session's engine.
class MonitorConfigController extends StateNotifier<MonitorConfig> {
  MonitorConfigController(this._storage) : super(_load(_storage));
  final Storage _storage;

  static MonitorConfig _load(Storage s) {
    final saved = s.monitorConfigJson();
    if (saved == null) return const MonitorConfig();
    try {
      return MonitorConfig.fromJson(jsonDecode(saved) as Map<String, dynamic>);
    } catch (_) {
      return const MonitorConfig();
    }
  }

  Future<void> update(MonitorConfig cfg) async {
    state = cfg;
    await _storage.setMonitorConfigJson(jsonEncode(cfg.toJson()));
  }
}

final monitorConfigProvider =
    StateNotifierProvider<MonitorConfigController, MonitorConfig>(
        (ref) => MonitorConfigController(ref.watch(storageProvider)));

/// A client with no session, for the login screen's captcha. Login itself is
/// sent from the account's own client; the server keys the captcha by its
/// vtoken, not by cookies (verified 2026-09-18).
final anonymousAuthProvider = Provider<AuthService>((ref) =>
    AuthService(ApiClient(origin: ref.watch(storageProvider).origin())));

/// Public-info reads that do not belong to any account.
final publicInfoServiceProvider = Provider<InfoService>((ref) =>
    InfoService(ApiClient(origin: ref.watch(storageProvider).origin())));

/// The deployment's system parameters (tab names, display switches). Loaded
/// once; refreshed when the origin changes.
final sysParamsProvider = FutureProvider<SysParams>(
    (ref) => ref.watch(publicInfoServiceProvider).fetchSysParams());

/// The filter dictionaries (通识类别, 开课单位, …), loaded once.
final dictionaryProvider = FutureProvider<Map<String, List<DictEntry>>>(
    (ref) => ref.watch(publicInfoServiceProvider).fetchDictionary());

// ---------------------------------------------------------------------------
// Per-account scope
// ---------------------------------------------------------------------------

/// Everything one signed-in account owns. Built by [sessionScopeProvider].
class SessionScope {
  SessionScope({
    required this.accountId,
    required this.client,
    required this.auth,
    required this.course,
    required this.enroll,
    required this.info,
    required this.manager,
    required this.engine,
  });

  final String accountId;
  final ApiClient client;
  final AuthService auth;
  final CourseService course;
  final EnrollService enroll;
  final InfoService info;
  final SessionManager manager;
  final MonitorEngine engine;
}

final sessionScopeProvider = Provider.family<SessionScope, String>((ref, id) {
  final storage = ref.watch(storageProvider);
  final client = ApiClient(origin: storage.origin());
  final auth = AuthService(client);
  final course = CourseService(client);
  final enroll = EnrollService(client);
  final info = InfoService(client);
  final manager = SessionManager(
    client: client,
    auth: auth,
    solver: ref.read(captchaSolverProvider),
    info: info,
  );
  ref.listen<CaptchaSolver>(
      captchaSolverProvider, (_, next) => manager.solver = next);
  manager.maxSilentReloginAttempts = ref.read(silentReloginAttemptsProvider);
  ref.listen<int>(silentReloginAttemptsProvider,
      (_, next) => manager.maxSilentReloginAttempts = next);
  manager.silentReloginEnabled = ref.read(silentReloginEnabledProvider);
  ref.listen<bool>(silentReloginEnabledProvider,
      (_, next) => manager.silentReloginEnabled = next);
  manager.contestedGuardEnabled = ref.read(contestedGuardProvider);
  ref.listen<bool>(contestedGuardProvider,
      (_, next) => manager.contestedGuardEnabled = next);
  manager.contestedWindow =
      Duration(minutes: ref.read(contestedWindowMinutesProvider));
  ref.listen<int>(contestedWindowMinutesProvider,
      (_, next) => manager.contestedWindow = Duration(minutes: next));
  manager.onSilentReloginFailed = () =>
      ref.read(sessionControllerProvider(id).notifier).markSessionExpired();
  manager.onSilentReloginSucceeded = () =>
      ref.read(sessionControllerProvider(id).notifier).onSessionRecovered();

  final engine = MonitorEngine(
    courseService: course,
    enrollService: enroll,
    config: ref.read(monitorConfigProvider),
  );
  ref.listen<MonitorConfig>(
      monitorConfigProvider, (_, next) => engine.config = next);
  try {
    engine.loadWatches(storage.watchesJson(id));
  } catch (_) {
    // A corrupt blob must not block sign-in.
  }
  ref.onDispose(engine.dispose);
  return SessionScope(
    accountId: id,
    client: client,
    auth: auth,
    course: course,
    enroll: enroll,
    info: info,
    manager: manager,
    engine: engine,
  );
});

/// Monotonic signal for server-backed selection data of one account. Every
/// successful enrollment mutation or batch switch increments it; dependent
/// providers refetch instead of leaving stale state until a manual refresh.
final selectionDataRevisionProvider =
    StateProvider.family<int, String>((ref, id) => 0);

void bumpSelectionRevision(Ref ref, String accountId) =>
    ref.read(selectionDataRevisionProvider(accountId).notifier).state++;

/// Same as [bumpSelectionRevision], for widgets, on the shown account.
void bumpCurrentSelectionRevision(WidgetRef ref) {
  final id = ref.read(activeAccountIdProvider);
  if (id != null) ref.read(selectionDataRevisionProvider(id).notifier).state++;
}

// ---------------------------------------------------------------------------
// Session state
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

  /// The name shown in account switchers: the student's name, else the login.
  String get displayName {
    final n = student?.name ?? '';
    if (n.isNotEmpty) return n;
    return account?.displayName ?? account?.loginName ?? '';
  }

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
  SessionController(this._ref, this.accountId) : super(SessionState());

  final Ref _ref;
  final String accountId;

  SessionScope get _scope => _ref.read(sessionScopeProvider(accountId));
  SessionManager get _mgr => _scope.manager;
  Storage get _storage => _ref.read(storageProvider);

  Timer? _heartbeat;

  /// Whether the monitor was running when the session dropped, so a
  /// successful re-login can start it again.
  bool _resumeMonitorAfterRelogin = false;

  /// Fetches a fresh captcha challenge from this account's client.
  Future<CaptchaChallenge> fetchCaptcha() => _mgr.auth.fetchCaptcha();

  /// Periodic cheap authenticated call. Verified 2026-09-18: a session pinged
  /// every 45 s stays alive for over 16 minutes, while one left idle is gone
  /// within about 12; and a login elsewhere kills it at once. The ping either
  /// keeps the session alive or trips the client's silent re-login, so a
  /// dropped session is noticed within a minute instead of at the next tap.
  Future<void> heartbeat() async {
    if (state.phase != AuthPhase.loggedIn) return;
    final code = state.student?.studentCode;
    if (code == null || code.isEmpty) return;
    try {
      await _scope.client.getJson(Api.studentInfo(code));
    } catch (_) {
      // Network blips are not session losses; expiry is signalled separately.
    }
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat =
        Timer.periodic(const Duration(seconds: 45), (_) => heartbeat());
  }

  /// Called when the API client detected an expired session and the silent
  /// re-login budget is spent. Pauses the monitor (without failing watches),
  /// notifies, and flips the phase so the shell shows the re-login dialog.
  void markSessionExpired() {
    if (state.phase != AuthPhase.loggedIn) return;
    final engine = _scope.engine;
    _resumeMonitorAfterRelogin = engine.isRunning || engine.haltedForSession;
    engine.haltForSession();
    state = state.copyWith(
      phase: AuthPhase.expired,
      error: _mgr.lastFailure.isEmpty ? '登录已失效' : _mgr.lastFailure,
    );
    NotificationService.instance.sessionExpired(who: state.displayName);
  }

  /// A silent re-login recovered the session. The old monitor timers are
  /// still ticking; nothing to restart.
  void onSessionRecovered() {}

  /// Interactive re-login from the expired-session dialog. Keeps the shell
  /// (phase stays [AuthPhase.expired] until success), keeps the active round
  /// when it still exists, and restarts the monitor if it had been running.
  Future<void> relogin({
    required String password,
    required String verifyCode,
    required String vtoken,
  }) async {
    final account = state.account;
    final loginName =
        account?.loginName ?? state.student?.studentCode ?? accountId;
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
    final updated = account ??
        Account(
          id: accountId,
          loginName: loginName,
          displayName: _mgr.student?.name ?? loginName,
          studentCode: _mgr.studentCode ?? '',
        );
    await _storage.upsertAccount(updated, password: password);
    state = SessionState(
      phase: AuthPhase.loggedIn,
      student: _mgr.student,
      batches: _mgr.batches,
      activeBatch: active,
      account: updated,
    );
    _startHeartbeat();
    bumpSelectionRevision(_ref, accountId);
    if (_resumeMonitorAfterRelogin) {
      _resumeMonitorAfterRelogin = false;
      _scope.engine.start();
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
      final saved = _storage.accounts().where((a) => a.id == accountId);
      final previousBatch = saved.isEmpty ? '' : saved.first.lastBatchCode;
      ElectiveBatch? active = _mgr.activeBatch;
      for (final b in _mgr.batches) {
        if (b.code == previousBatch && b.canSelect) active = b;
      }
      _mgr.activeBatch = active;
      final account = Account(
        id: accountId,
        loginName: loginName,
        displayName: _mgr.student?.name.isNotEmpty == true
            ? _mgr.student!.name
            : loginName,
        studentCode: _mgr.studentCode ?? '',
        lastBatchCode: active?.code ?? '',
      );
      if (remember) {
        await _storage.upsertAccount(account, password: password);
        await _storage.setActiveAccount(account.id);
      }
      state = SessionState(
        phase: AuthPhase.loggedIn,
        student: _mgr.student,
        batches: _mgr.batches,
        activeBatch: active,
        account: account,
      );
      _startHeartbeat();
      // Native platforms can request from the signed-in flow. Browsers require
      // a direct, explicit action, exposed in Settings.
      if (!kIsWeb) await NotificationService.instance.requestPermission();
    } catch (e) {
      state = state.copyWith(phase: AuthPhase.loggedOut, error: _describe(e));
      rethrow;
    }
  }

  Future<void> setActiveBatch(ElectiveBatch batch) async {
    final changed = state.activeBatch?.code != batch.code;
    _mgr.activeBatch = batch;
    state = state.copyWith(activeBatch: batch);
    final account = state.account;
    if (account != null && account.lastBatchCode != batch.code) {
      final updated = account.copyWith(lastBatchCode: batch.code);
      state = state.copyWith(account: updated);
      await _storage.upsertAccount(updated);
    }
    await _confirmBatchIfOpen(batch);
    // Re-picking the same batch (the post-login dialog usually confirms the
    // auto-selected one) changes no server-side data, so don't refetch.
    if (changed) bumpSelectionRevision(_ref, accountId);
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
      await _scope.auth.confirmBatch(
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
    bumpSelectionRevision(_ref, accountId);
  }

  /// Signs this account out: stops its monitor, tells the server, drops the
  /// token and cookies. The account list decides what the UI shows next.
  Future<void> logout() async {
    _heartbeat?.cancel();
    _scope.engine.stop();
    final code = state.student?.studentCode;
    if (code != null && code.isNotEmpty) {
      try {
        await _scope.auth.logout(code);
      } catch (_) {
        // local cleanup below is unconditional.
      }
    }
    _scope.client.token = null;
    await _scope.client.clearCookies();
    state = SessionState();
  }

  String _describe(Object e) {
    if (e is AppError) {
      return e.hint != null ? '${e.message}，${e.hint}' : e.message;
    }
    if (e is LoginException) return e.message;
    return e.toString();
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    super.dispose();
  }
}

final sessionControllerProvider =
    StateNotifierProvider.family<SessionController, SessionState, String>(
        (ref, id) => SessionController(ref, id));

// ---------------------------------------------------------------------------
// Signed-in accounts and the one the UI shows
// ---------------------------------------------------------------------------

/// Ids of the accounts currently signed in, in sign-in order.
final signedInAccountsProvider = StateProvider<List<String>>((ref) => const []);

/// The account whose pages the shell shows; null when nobody is signed in.
final activeAccountIdProvider = StateProvider<String?>((ref) => null);

/// Adds [id] to the signed-in list (after a successful login) and shows it.
void enterAccount(WidgetRef ref, String id) {
  final list = ref.read(signedInAccountsProvider);
  if (!list.contains(id)) {
    ref.read(signedInAccountsProvider.notifier).state = [...list, id];
  }
  ref.read(activeAccountIdProvider.notifier).state = id;
}

/// Signs [id] out and shows the next signed-in account, or the login screen.
Future<void> leaveAccount(WidgetRef ref, String id) async {
  await ref.read(sessionControllerProvider(id).notifier).logout();
  final remaining =
      ref.read(signedInAccountsProvider).where((e) => e != id).toList();
  ref.read(signedInAccountsProvider.notifier).state = remaining;
  if (ref.read(activeAccountIdProvider) == id) {
    ref.read(activeAccountIdProvider.notifier).state =
        remaining.isEmpty ? null : remaining.first;
  }
  // Drop the scope so a later sign-in of the same account starts clean.
  ref.invalidate(sessionScopeProvider(id));
  ref.invalidate(sessionControllerProvider(id));
}

/// Drives the platform keep-alive from the monitors: any running engine keeps
/// the app alive (tray / foreground service / wakelock) per the settings.
/// Read once from the shell.
final backgroundDriverProvider = Provider<void>((ref) {
  final ids = ref.watch(signedInAccountsProvider);
  final runInBackground = ref.watch(runInBackgroundProvider);
  final keepAwake = ref.watch(keepAwakeProvider);
  final subs = <StreamSubscription<void>>[];
  void apply() {
    var running = 0;
    var watching = 0;
    for (final id in ids) {
      final e = ref.read(sessionScopeProvider(id)).engine;
      if (e.isRunning) {
        running++;
        watching +=
            e.watches.where((w) => w.status == WatchStatus.watching).length;
      }
    }
    AppBackground.instance.setMonitoring(running > 0,
        runInBackground: runInBackground, keepAwake: keepAwake);
    AppBackground.instance
        .updateStatus(running == 0 ? '' : '$running 个账号监控中，$watching 门课');
  }

  for (final id in ids) {
    subs.add(ref
        .read(sessionScopeProvider(id))
        .engine
        .changes
        .listen((_) => apply()));
  }
  AppBackground.instance.setCloseToTray(runInBackground);
  apply();
  ref.onDispose(() {
    for (final s in subs) {
      s.cancel();
    }
  });
});

// ---------------------------------------------------------------------------
// "Current account" views, so pages read one thing
// ---------------------------------------------------------------------------

/// Session state of the shown account (an empty logged-out state when none).
final sessionProvider = Provider<SessionState>((ref) {
  final id = ref.watch(activeAccountIdProvider);
  if (id == null) return SessionState();
  return ref.watch(sessionControllerProvider(id));
});

/// The shown account's controller. Only valid while an account is shown.
final currentSessionControllerProvider = Provider<SessionController>((ref) {
  final id = ref.watch(activeAccountIdProvider);
  if (id == null) throw StateError('no account is signed in');
  return ref.watch(sessionControllerProvider(id).notifier);
});

final currentScopeProvider = Provider<SessionScope>((ref) {
  final id = ref.watch(activeAccountIdProvider);
  if (id == null) throw StateError('no account is signed in');
  return ref.watch(sessionScopeProvider(id));
});

final courseServiceProvider =
    Provider<CourseService>((ref) => ref.watch(currentScopeProvider).course);
final enrollServiceProvider =
    Provider<EnrollService>((ref) => ref.watch(currentScopeProvider).enroll);
final infoServiceProvider =
    Provider<InfoService>((ref) => ref.watch(currentScopeProvider).info);
final monitorEngineProvider =
    Provider<MonitorEngine>((ref) => ref.watch(currentScopeProvider).engine);

/// The shown account's selection-data revision (see
/// [selectionDataRevisionProvider]).
final currentSelectionRevisionProvider = Provider<int>((ref) {
  final id = ref.watch(activeAccountIdProvider);
  if (id == null) return 0;
  return ref.watch(selectionDataRevisionProvider(id));
});

// ---------------------------------------------------------------------------
// Theme
// ---------------------------------------------------------------------------

class ThemeSettings {
  ThemeSettings(
      {required this.mode, required this.seed, this.useDynamic = false});
  final ThemeMode mode;
  final Color seed;

  /// Use the platform accent instead of [seed].
  final bool useDynamic;

  ThemeSettings copyWith({ThemeMode? mode, Color? seed, bool? useDynamic}) =>
      ThemeSettings(
        mode: mode ?? this.mode,
        seed: seed ?? this.seed,
        useDynamic: useDynamic ?? this.useDynamic,
      );
}

class ThemeController extends StateNotifier<ThemeSettings> {
  ThemeController(this._storage)
      : super(ThemeSettings(
          mode: _modeFromIndex(_storage.themeModeIndex()),
          seed: Color(_storage.seedColor()),
          useDynamic: _storage.useDynamicColor(),
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
    // Picking a colour is an explicit choice; it must win over the accent.
    state = state.copyWith(seed: seed, useDynamic: false);
    await _storage.setSeedColor(seed.toARGB32());
    await _storage.setUseDynamicColor(false);
  }

  Future<void> setUseDynamic(bool v) async {
    state = state.copyWith(useDynamic: v);
    await _storage.setUseDynamicColor(v);
  }
}

final themeControllerProvider =
    StateNotifierProvider<ThemeController, ThemeSettings>(
        (ref) => ThemeController(ref.watch(storageProvider)));

class TextScaleController extends StateNotifier<double> {
  TextScaleController(this.storage) : super(storage.textScale());
  final Storage storage;
  Future<void> set(double value) async {
    state = value.clamp(0.85, 1.6);
    await storage.setTextScale(state);
  }
}

final textScaleProvider = StateNotifierProvider<TextScaleController, double>(
    (ref) => TextScaleController(ref.watch(storageProvider)));

// ---------------------------------------------------------------------------
// Saved accounts
// ---------------------------------------------------------------------------

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
