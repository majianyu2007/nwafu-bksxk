/// Riverpod state for the 教务 side: the unified-identity sign-in, the
/// offline timetable, grades, exams and class reminders.
///
/// This is independent of the course-selection accounts in `providers.dart`:
/// the timetable must open (from cache) with no network and no selection
/// round, and its sign-in is the school's unified identity, not bksxk.
library;

import 'dart:async';
import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart' show CookieJar, PersistCookieJar;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/crypto/passkey.dart';
import '../core/crypto/webauthn_register.dart' show AttestationFormat;
import '../core/errors.dart';
import '../data/academic_calendar.dart' show schoolDate;
import '../data/background_sync.dart';
import '../data/cas_client.dart';
import '../data/device_unlock.dart';
import '../data/edu_models.dart';
import '../data/ehall_service.dart';
import '../data/home_widget_sync.dart';
import '../data/notifications.dart';
import '../data/secure_cookie_storage.dart';
import '../data/storage.dart';
import '../data/timetable_logic.dart';
import 'providers.dart';
import 'sync_providers.dart';

/// The signed-in school identity (non-secret part).
class EduAccount {
  const EduAccount({
    required this.username,
    this.name = '',
    this.dept = '',
    this.major = '',
    this.className = '',
    this.usePasskey = false,
  });
  final String username;
  final String name;
  final String dept;
  final String major;
  final String className;
  final bool usePasskey;

  String get displayName => name.isNotEmpty ? name : username;

  EduAccount copyWith({
    String? name,
    String? dept,
    String? major,
    String? className,
    bool? usePasskey,
  }) => EduAccount(
    username: username,
    name: name ?? this.name,
    dept: dept ?? this.dept,
    major: major ?? this.major,
    className: className ?? this.className,
    usePasskey: usePasskey ?? this.usePasskey,
  );

  String encode() => jsonEncode({
    'u': username,
    'n': name,
    'd': dept,
    'm': major,
    'c': className,
    'pk': usePasskey,
  });

  static EduAccount? decode(String? raw) {
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return EduAccount(
        username: j['u'] as String,
        name: (j['n'] as String?) ?? '',
        dept: (j['d'] as String?) ?? '',
        major: (j['m'] as String?) ?? '',
        className: (j['c'] as String?) ?? '',
        usePasskey: (j['pk'] as bool?) ?? false,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Each identity owns a separate native cookie jar. A retired client's cookie
/// writer is closed before its replacement can read persisted credentials.
class EduClient {
  EduClient(this.storage, {String? accountId}) {
    _cookies = !kIsWeb && accountId != null
        ? SecureCookieStorage(storage, accountId)
        : null;
    jar = _cookies == null ? CookieJar() : PersistCookieJar(storage: _cookies);
    cas = CasClient(cookieJar: jar);
    ehall = EhallService(cas);
  }

  EduClient.withServices(this.storage, this.cas, this.ehall)
    : jar = cas.cookieJar;

  final Storage storage;
  late final CookieJar jar;
  late final CasClient cas;
  late final EhallService ehall;
  SecureCookieStorage? _cookies;

  Future<void> close({bool clearCookies = false}) async {
    cas.dio.close(force: true);
    if (_cookies != null) {
      await _cookies!.close(clear: clearCookies);
    } else if (clearCookies) {
      await jar.deleteAll();
    }
  }
}

final _eduClientAccountProvider = StateProvider<String?>(
  (ref) => EduAccount.decode(ref.read(storageProvider).eduAccount())?.username,
);

final eduClientProvider = Provider<EduClient>((ref) {
  final client = EduClient(
    ref.watch(storageProvider),
    accountId: ref.watch(_eduClientAccountProvider),
  );
  ref.onDispose(() => unawaited(client.close()));
  return client;
});

enum EduPhase { signedOut, signedIn }

class EduState {
  const EduState({required this.phase, this.account});
  final EduPhase phase;
  final EduAccount? account;
  bool get signedIn => phase == EduPhase.signedIn;
}

/// Sign-in / sign-out for the unified identity. Login methods throw
/// [CasMfaRequired] when the AuthServer wants a second factor; the login page
/// then drives [CasClient.sendMfaCode] / [completeMfa].
class EduSessionController extends StateNotifier<EduState> {
  EduSessionController(this._ref)
    : super(_initial(_ref.read(storageProvider))) {
    _bindClient();
  }

  final Ref _ref;
  EduClient get _client => _ref.read(eduClientProvider);
  Storage get _storage => _ref.read(storageProvider);
  Future<bool>? _relogin;
  void _bindClient() {
    _client.ehall.onLoginRequired = silentRelogin;
    _client.ehall.expectedUsername = state.account?.username;
  }

  Future<void> _mutations = Future.value();
  int _epoch = 0;
  _PendingEduLogin? _pending;

  static EduState _initial(Storage s) {
    final a = EduAccount.decode(s.eduAccount());
    return EduState(
      phase: a == null ? EduPhase.signedOut : EduPhase.signedIn,
      account: a,
    );
  }

  bool _current(int epoch) => mounted && epoch == _epoch;

  Future<void> _serial(Future<void> Function() action) {
    final next = _mutations.then((_) => action());
    _mutations = next.catchError((Object _) {});
    return next;
  }

  Future<_PendingEduLogin> _begin(
    String username, {
    String? password,
    PasskeyCredential? passkey,
    bool remember = true,
  }) async {
    CasClient.requireSupportedPlatform();
    username = username.trim();
    if (username.isEmpty) {
      throw AppError(AppErrorKind.account, message: '请输入统一身份认证账号');
    }
    final previousAccount = state.account?.username ?? _pending?.username;
    final epoch = ++_epoch;
    _pending = null;
    _relogin = null;
    state = const EduState(phase: EduPhase.signedOut);
    final reminders = _ref.read(classReminderProvider.notifier).reschedule();
    await _serial(() async {
      if (!_current(epoch)) return;
      final old = _client;
      final oldAccount =
          _ref.read(_eduClientAccountProvider) ?? previousAccount;
      await old.close(clearCookies: oldAccount != username);
      await _storage.setEduAccount(null);
      if (oldAccount != null) {
        await _storage.setEduPassword(oldAccount, null);
        await _storage.setEduPasskey(oldAccount, null);
      }
      if (!_current(epoch)) return;
      _ref.read(_eduClientAccountProvider.notifier).state = username;
      _ref.invalidate(eduClientProvider);
      await _client.cas.clearSession();
      _bindClient();
    });
    await reminders;
    if (!_current(epoch)) throw _cancelled;
    final pending = _PendingEduLogin(
      epoch,
      username,
      _client,
      password,
      passkey,
      remember,
    );
    _pending = pending;
    return pending;
  }

  static AppError get _cancelled =>
      AppError(AppErrorKind.sessionExpired, message: '登录已取消');

  Future<void> loginWithPassword(
    String username,
    String password, {
    bool remember = true,
  }) async {
    final p = await _begin(username, password: password, remember: remember);
    await _authenticate(p);
  }

  Future<void> loginWithPasskey(
    String username,
    PasskeyCredential credential,
  ) async {
    final p = await _begin(username, passkey: credential);
    await _authenticate(p);
  }

  /// Imports only the identity returned by the authenticated school profile.
  /// Browser cookies remain browser-owned; no password or passkey is copied.
  Future<void> connectBrowserSession() async {
    CasClient.requireBrowserSessionBridge();
    final epoch = ++_epoch;
    _pending = null;
    _relogin = null;
    state = const EduState(phase: EduPhase.signedOut);
    final reminders = _ref.read(classReminderProvider.notifier).reschedule();
    await _serial(() async {
      if (!_current(epoch)) return;
      final oldAccount = _ref.read(_eduClientAccountProvider);
      await _client.close(clearCookies: true);
      await _storage.setEduAccount(null);
      if (oldAccount != null) {
        await _storage.setEduPassword(oldAccount, null);
        await _storage.setEduPasskey(oldAccount, null);
      }
      if (!_current(epoch)) return;
      _ref.read(_eduClientAccountProvider.notifier).state = null;
      _ref.invalidate(eduClientProvider);
      _bindClient();
    });
    await reminders;
    if (!_current(epoch)) throw _cancelled;
    final profile = await _client.ehall.profile();
    if (!_current(epoch)) throw _cancelled;
    final account = EduAccount(
      username: profile.username,
      name: profile.name,
      dept: profile.dept,
      major: profile.major,
      className: profile.className,
    );
    await _serial(() async {
      if (!_current(epoch)) return;
      await _storage.setEduAccount(account.encode());
      if (!_current(epoch)) return;
      _ref.read(_eduClientAccountProvider.notifier).state = account.username;
      state = EduState(phase: EduPhase.signedIn, account: account);
      _bindClient();
    });
    if (!_current(epoch)) throw _cancelled;
  }

  Future<void> _authenticate(_PendingEduLogin p) async {
    try {
      await p.client.cas.login(
        service: EmapApp.timetable.indexUrl,
        username: p.username,
        password: p.password ?? '',
        passkey: p.passkey,
      );
    } on CasMfaRequired catch (e) {
      if (!_current(p.epoch)) throw _cancelled;
      p.challenge = e.challenge;
      rethrow;
    }
    await _finish(p);
  }

  /// Pending credentials and auth type survive MFA only in memory. Callers
  /// cannot change the account by submitting a different username/challenge.
  Future<void> completeMfa(
    String username,
    CasMfaChallenge challenge,
    MfaMethod method,
    String code, {
    required bool trustDevice,
    String? password,
    PasskeyCredential? passkey,
    bool remember = true,
  }) async {
    final p = _pending;
    if (p == null ||
        !_current(p.epoch) ||
        username.trim() != p.username ||
        !identical(challenge, p.challenge)) {
      throw _cancelled;
    }
    final inflight = p.completion;
    if (inflight != null) return inflight;
    final completion = () async {
      await p.client.cas.submitMfa(
        challenge,
        method,
        code,
        trustDevice: trustDevice,
      );
      await _finish(p);
    }();
    p.completion = completion;
    try {
      await completion;
    } finally {
      if (identical(p.completion, completion)) p.completion = null;
    }
  }

  Future<void> _finish(_PendingEduLogin p) async {
    if (!_current(p.epoch)) throw _cancelled;
    p.client.ehall.reset();
    var account = EduAccount(
      username: p.username,
      usePasskey: p.passkey != null,
    );
    try {
      final profile = await p.client.ehall.profile();
      if (profile.username != p.username) {
        throw AppError(
          AppErrorKind.sessionExpired,
          message: '教务系统返回的账号与本次登录不一致，请重新登录',
        );
      }
      account = account.copyWith(
        name: profile.name,
        dept: profile.dept,
        major: profile.major,
        className: profile.className,
      );
    } on AppError catch (e) {
      if (e.kind == AppErrorKind.sessionExpired) rethrow;
      // Profile labels are cosmetic; authenticated course data is independent.
    }
    await _serial(() async {
      if (!_current(p.epoch)) return;
      await _storage.setEduPassword(
        p.username,
        p.remember && p.passkey == null ? p.password : null,
      );
      await _storage.setEduPasskey(
        p.username,
        p.passkey == null ? null : jsonEncode(p.passkey!.toJson()),
      );
      if (!_current(p.epoch)) return;
      await _storage.setEduAccount(account.encode());
      if (!_current(p.epoch)) return;
      _pending = null;
      state = EduState(phase: EduPhase.signedIn, account: account);
      _bindClient();
    });
    if (!_current(p.epoch)) throw _cancelled;
  }

  // -------------------------------------------------------------------------
  // This app as a passkey device (个人中心 → 生物识别)
  // -------------------------------------------------------------------------

  /// Whether this install holds a bound passkey for [username].
  Future<bool> hasDeviceKey(String username) async =>
      (await _storage.eduDeviceKey(username.trim())) != null;

  /// Binds this app to the signed-in account: generates a key, registers it
  /// in the personal centre, keeps it in secure storage. [password] answers
  /// the personal centre's re-check when it asks; [solveCaptcha] shows the
  /// re-check captcha image and returns what the user typed (null = cancel).
  Future<void> bindThisDevice({
    required String deviceName,
    required String password,
    required Future<String?> Function(Uint8List image) solveCaptcha,
  }) async {
    final account = state.account;
    if (account == null) {
      throw AppError(AppErrorKind.sessionExpired, message: '请先登录统一身份认证');
    }
    final cas = _client.cas;
    await cas.openPersonalCenter();
    if (await cas.personalCenterNeedsRecheck()) {
      for (var attempt = 0; ; attempt++) {
        final code = await solveCaptcha(await cas.recheckCaptcha());
        if (code == null) throw _cancelled;
        try {
          await cas.recheckPassword(password, code);
          break;
        } on AppError catch (e) {
          if (e.kind != AppErrorKind.captcha || attempt >= 4) rethrow;
        }
      }
    }
    PasskeyCredential credential;
    try {
      credential = await cas.registerDevicePasskey(deviceName);
    } on AppError {
      // Some deployments insist on an attestation statement.
      credential = await cas.registerDevicePasskey(
        deviceName,
        format: AttestationFormat.packedSelf,
      );
    }
    await _storage.setEduDeviceKey(
      account.username,
      jsonEncode({...credential.toJson(), 'deviceName': deviceName}),
    );
  }

  /// Removes this app's binding (server side when reachable) and the key.
  Future<void> unbindThisDevice() async {
    final account = state.account;
    if (account == null) return;
    final raw = await _storage.eduDeviceKey(account.username);
    if (raw == null) return;
    final saved = PasskeyCredential.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
    try {
      final cas = _client.cas;
      await cas.openPersonalCenter();
      for (final d in await cas.boundDevices()) {
        if (d['id']?.toString() == saved.deviceBindingId) {
          await cas.deleteBoundDevice(
            saved.deviceBindingId,
            d['userId']?.toString() ?? account.username,
          );
        }
      }
    } finally {
      await _storage.setEduDeviceKey(account.username, null);
    }
  }

  /// Signs in with this app's bound passkey after the device confirms the
  /// user ([confirm] shows fingerprint / Face ID).
  Future<void> loginWithDeviceKey(
    String username,
    Future<bool> Function() confirm,
  ) async {
    final raw = await _storage.eduDeviceKey(username.trim());
    if (raw == null) {
      throw AppError(AppErrorKind.account, message: '本设备尚未绑定快捷登录');
    }
    if (!await confirm()) throw _cancelled;
    final credential = PasskeyCredential.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
    await loginWithPasskey(username, credential);
  }

  /// One attempt per identity. MFA is never answered automatically.
  Future<bool> silentRelogin() {
    final inflight = _relogin;
    if (inflight != null) return inflight;
    final account = state.account;
    if (account == null || kIsWeb) return Future.value(false);
    final epoch = _epoch;
    final client = _client;
    late final Future<bool> attempt;
    attempt = () async {
      try {
        final pk = account.usePasskey
            ? await _storage.eduPasskey(account.username)
            : null;
        final pw = account.usePasskey
            ? null
            : await _storage.eduPassword(account.username);
        if (!_current(epoch) || (pk == null && (pw == null || pw.isEmpty))) {
          return false;
        }
        await client.cas.login(
          service: EmapApp.timetable.indexUrl,
          username: account.username,
          password: pw ?? '',
          passkey: pk == null
              ? null
              : PasskeyCredential.fromJson(
                  jsonDecode(pk) as Map<String, dynamic>,
                ),
        );
        return _current(epoch);
      } on CasMfaRequired {
        // A silent attempt must not leave a half-authenticated MFA session
        // looking like a reusable CASTGC to the next refresh.
        await _serial(() async {
          if (!_current(epoch)) return;
          await client.cas.clearSession();
          client.ehall.reset();
        });
        return false;
      } catch (_) {
        return false;
      } finally {
        if (identical(_relogin, attempt)) _relogin = null;
      }
    }();
    _relogin = attempt;
    return attempt;
  }

  Future<void> _cacheFor(
    String accountId,
    bool Function() current,
    Future<void> Function() save,
  ) => _serial(() async {
    if (mounted && state.account?.username == accountId && current()) {
      await save();
    }
  });

  Future<void> cancelLogin() =>
      _pending == null && state.signedIn ? Future.value() : logout();

  Future<void> logout() async {
    final previousAccount = state.account?.username ?? _pending?.username;
    ++_epoch;
    _pending = null;
    _relogin = null;
    state = const EduState(phase: EduPhase.signedOut);
    // Cancellation is queued after any in-flight replacement schedule.
    final reminders = _ref.read(classReminderProvider.notifier).reschedule();
    await _serial(() async {
      final account =
          _ref.read(_eduClientAccountProvider) ?? previousAccount;
      await _client.close(clearCookies: true);
      await _storage.setEduAccount(null);
      if (account != null) {
        await _storage.setEduPassword(account, null);
        await _storage.setEduPasskey(account, null);
        await _storage.clearEduData(account);
      }
    });
    await reminders;
  }

  @override
  void dispose() {
    ++_epoch;
    _pending = null;
    super.dispose();
  }
}

class _PendingEduLogin {
  _PendingEduLogin(
    this.epoch,
    this.username,
    this.client,
    this.password,
    this.passkey,
    this.remember,
  );
  final int epoch;
  final String username;
  final EduClient client;
  final String? password;
  final PasskeyCredential? passkey;
  final bool remember;
  CasMfaChallenge? challenge;
  Future<void>? completion;
}

/// Fingerprint / Face ID gate for the bound passkey.
final deviceUnlockProvider = Provider<DeviceUnlock>((ref) => DeviceUnlock());

final eduSessionProvider =
    StateNotifierProvider<EduSessionController, EduState>(
      (ref) => EduSessionController(ref),
    );

// ---------------------------------------------------------------------------
// Timetable
// ---------------------------------------------------------------------------

class TimetableState {
  const TimetableState({
    this.data,
    this.terms = const [],
    this.loading = false,
    this.error,
  });

  /// The shown term's timetable (from cache until a sync returns).
  final TermTimetable? data;
  final List<EduTerm> terms;
  final bool loading;
  final AppError? error;

  TimetableState copyWith({
    TermTimetable? data,
    List<EduTerm>? terms,
    bool? loading,
    AppError? error,
    bool clearError = false,
  }) => TimetableState(
    data: data ?? this.data,
    terms: terms ?? this.terms,
    loading: loading ?? this.loading,
    error: clearError ? null : (error ?? this.error),
  );
}

class TimetableController extends StateNotifier<TimetableState> {
  TimetableController(this._ref, this._accountId)
    : _session = _ref.read(eduSessionProvider.notifier),
      _epoch = _ref.read(eduSessionProvider.notifier)._epoch,
      super(const TimetableState()) {
    _loadCached();
  }

  final Ref _ref;
  final String? _accountId;
  final EduSessionController _session;
  final int _epoch;
  int _request = 0;
  Storage get _storage => _ref.read(storageProvider);

  bool _current(int request) =>
      mounted && request == _request && _session._current(_epoch);

  void _loadCached() {
    final id = _accountId;
    if (id == null) return;
    final raw = _storage.eduCurrentTerm(id);
    if (raw == null) return;
    try {
      final term = EduTerm.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      final t = TermTimetable.decode(_storage.eduTimetable(id, term.code));
      if (t != null) {
        state = TimetableState(data: _withCustom(t), terms: [term]);
      }
    } catch (_) {}
  }

  TermTimetable _withCustom(TermTimetable t) {
    final id = _accountId;
    if (id == null) return t;
    final week1 = DateTime.tryParse(
      _storage.weekOneOverride(id, t.term.code) ?? '',
    );
    if (week1 != null) {
      t = t.copyWith(
        firstMonday: DateTime.utc(week1.year, week1.month, week1.day),
      );
    }
    final raw = _storage.customSessions(id, t.term.code);
    if (raw == null) return t;
    try {
      final custom = [
        for (final s in jsonDecode(raw) as List)
          CourseSession.fromJson(s as Map<String, dynamic>),
      ];
      return t.copyWith(
        sessions: [...t.sessions, ...custom.where((s) => s.custom)],
      );
    } catch (_) {
      return t;
    }
  }

  /// Cached rows stay visible if refreshing that term fails. A term switch
  /// supersedes older requests even when their network calls finish last.
  Future<void> sync({EduTerm? term, bool silent = false}) async {
    final id = _accountId;
    if (id == null || (state.loading && term == null)) return;
    final request = ++_request;
    final ehall = _ref.read(eduClientProvider).ehall;
    final session = _ref.read(eduSessionProvider.notifier);
    state = state.copyWith(loading: true, clearError: true);
    try {
      final target = term ?? await ehall.currentTerm();
      if (!_current(request)) return;
      final fresh = await ehall.timetable(target);
      if (!_current(request)) return;
      var terms = state.terms;
      try {
        terms = await ehall.terms();
        if (!terms.contains(target)) terms = [target, ...terms];
      } on AppError {
        if (terms.isEmpty) terms = [target];
      }
      if (!_current(request)) return;
      await session._cacheFor(id, () => _current(request), () async {
        // Diff against the cached copy before it is overwritten.
        try {
          await _ref.read(eduSyncCoreProvider).recordTimetable(id, fresh);
        } catch (_) {}
        await _storage.setEduTimetable(id, target.code, fresh.encode());
        await _storage.setEduCurrentTerm(id, jsonEncode(target.toJson()));
        await _storage.setEduLastSync(id, DateTime.now());
      });
      if (!_current(request)) return;
      state = TimetableState(data: _withCustom(fresh), terms: terms);
      _ref.read(timetableChangesProvider.notifier).reload();
      unawaited(_ref.read(classReminderProvider.notifier).reschedule());
      _ref.read(calendarSyncProvider.notifier).schedule();
    } catch (e) {
      if (!_current(request)) return;
      if (silent) {
        state = state.copyWith(loading: false);
        return;
      }
      state = state.copyWith(
        loading: false,
        error: e is AppError
            ? e
            : AppError(
                AppErrorKind.schemaOrRedirect,
                message: '课表同步失败',
                raw: e,
              ),
      );
    }
  }

  Future<void> switchTerm(EduTerm term) async {
    final id = _accountId;
    if (id == null) return;
    final cached = TermTimetable.decode(_storage.eduTimetable(id, term.code));
    state = TimetableState(
      data: cached == null ? null : _withCustom(cached),
      terms: state.terms,
    );
    unawaited(_ref.read(classReminderProvider.notifier).reschedule());
    await sync(term: term);
  }

  /// The term's week 1 as stored (server/school), ignoring any override.
  DateTime? serverWeekOne() {
    final id = _accountId;
    final t = state.data;
    if (id == null || t == null) return null;
    return TermTimetable.decode(
      _storage.eduTimetable(id, t.term.code),
    )?.firstMonday;
  }

  /// Sets (or with null clears) the user's week 1 Monday for this term.
  Future<void> setWeekOne(DateTime? monday) async {
    final id = _accountId;
    final t = state.data;
    if (id == null || t == null) return;
    await _storage.setWeekOneOverride(
      id,
      t.term.code,
      monday == null
          ? null
          : DateTime.utc(monday.year, monday.month, monday.day)
                .toIso8601String()
                .substring(0, 10),
    );
    final cached = TermTimetable.decode(_storage.eduTimetable(id, t.term.code));
    if (cached != null && mounted) {
      state = state.copyWith(data: _withCustom(cached));
      unawaited(_ref.read(classReminderProvider.notifier).reschedule());
    }
  }

  Future<void> addCustom(CourseSession s) async {
    final t = state.data;
    if (t == null || !s.custom) return;
    await _saveCustom(t, [...t.sessions.where((e) => e.id != s.id), s]);
  }

  Future<void> removeCustom(String id) async {
    final t = state.data;
    if (t == null) return;
    await _saveCustom(
      t,
      t.sessions.where((e) => !e.custom || e.id != id).toList(),
    );
  }

  Future<void> _saveCustom(
    TermTimetable t,
    List<CourseSession> sessions,
  ) async {
    final id = _accountId;
    if (id == null) return;
    final request = _request;
    await _ref
        .read(eduSessionProvider.notifier)
        ._cacheFor(
          id,
          () => _current(request),
          () => _storage.setCustomSessions(
            id,
            t.term.code,
            jsonEncode([
              for (final c in sessions.where((s) => s.custom)) c.toJson(),
            ]),
          ),
        );
    if (!_current(request)) return;
    state = state.copyWith(data: t.copyWith(sessions: sessions));
    unawaited(_ref.read(classReminderProvider.notifier).reschedule());
  }

  /// Picks up a cache another isolate (the background refresh) wrote.
  void reloadCached() {
    if (state.loading) return;
    final id = _accountId;
    final shown = state.data;
    if (id == null) return;
    final cached = TermTimetable.decode(
      _storage.eduTimetable(id, shown?.term.code ?? _cachedTermCode(id) ?? ''),
    );
    if (cached == null) return;
    if (shown != null && !cached.syncedAt.isAfter(shown.syncedAt)) return;
    state = state.copyWith(data: _withCustom(cached));
  }

  String? _cachedTermCode(String id) {
    final raw = _storage.eduCurrentTerm(id);
    if (raw == null) return null;
    try {
      return EduTerm.fromJson(jsonDecode(raw) as Map<String, dynamic>).code;
    } catch (_) {
      return null;
    }
  }

  void clear() {
    ++_request;
    state = const TimetableState();
  }
}

final timetableProvider =
    StateNotifierProvider<TimetableController, TimetableState>(
      (ref) => TimetableController(
        ref,
        ref.watch(eduSessionProvider.select((s) => s.account?.username)),
      ),
    );

/// Debug builds can shift "now" (from the VM service) to check how the
/// timetable looks during a class.
final debugClockOffsetProvider = StateProvider<Duration>((ref) => Duration.zero);

/// Ticks every 30 s so "now" views (current class, today line) move on.
final clockProvider = StreamProvider<DateTime>((ref) async* {
  final offset = kDebugMode ? ref.watch(debugClockOffsetProvider) : Duration.zero;
  yield DateTime.now().add(offset);
  yield* Stream.periodic(
    const Duration(seconds: 30),
    (_) => DateTime.now().add(offset),
  );
});

class TimetablePrefs {
  const TimetablePrefs({
    required this.showWeekend,
    required this.showOtherWeeks,
  });
  final bool showWeekend;
  final bool showOtherWeeks;
}

class TimetablePrefsController extends StateNotifier<TimetablePrefs> {
  TimetablePrefsController(this._s)
    : super(
        TimetablePrefs(
          showWeekend: _s.timetableShowWeekend(),
          showOtherWeeks: _s.timetableShowOtherWeeks(),
        ),
      );
  final Storage _s;

  Future<void> setShowWeekend(bool v) async {
    await _s.setTimetableShowWeekend(v);
    state = TimetablePrefs(
      showWeekend: v,
      showOtherWeeks: state.showOtherWeeks,
    );
  }

  Future<void> setShowOtherWeeks(bool v) async {
    await _s.setTimetableShowOtherWeeks(v);
    state = TimetablePrefs(showWeekend: state.showWeekend, showOtherWeeks: v);
  }
}

final timetablePrefsProvider =
    StateNotifierProvider<TimetablePrefsController, TimetablePrefs>(
      (ref) => TimetablePrefsController(ref.watch(storageProvider)),
    );

// ---------------------------------------------------------------------------
// Class reminders
// ---------------------------------------------------------------------------

/// Minutes before class (0 = off). Changing it re-plans the OS schedule.
class ClassReminderController extends StateNotifier<int> {
  ClassReminderController(this._ref)
    : super(_ref.read(storageProvider).classReminderMinutes());
  final Ref _ref;
  Timer? _fallback;
  Timer? _rolling;
  final _fired = <int>{};
  String? _identity;
  int _generation = 0;
  int _leadRequest = 0;
  Future<void> _settings = Future.value();

  Future<void> setLead(int minutes) async {
    if (minutes < 0 || minutes > 120) {
      throw ArgumentError.value(
        minutes,
        'minutes',
        'Must be between 0 and 120',
      );
    }
    final request = ++_leadRequest;
    if (minutes > 0 &&
        !await _ref.read(eduNotificationsProvider).requestPermission()) {
      throw AppError(
        AppErrorKind.unknown,
        message: '未获得通知权限',
        hint: '请在系统设置允许通知后再开启提醒。',
      );
    }
    if (!mounted || request != _leadRequest) return;
    final save = _settings.then((_) async {
      if (!mounted || request != _leadRequest) return;
      await _ref.read(storageProvider).setClassReminderMinutes(minutes);
      if (!mounted || request != _leadRequest) return;
      state = minutes;
      await reschedule();
    });
    _settings = save.catchError((Object _) {});
    await save;
  }

  /// A seven-day rolling OS window, refreshed on startup, resume, each day,
  /// and data/account changes. Linux/web only fire while the process runs.
  Future<void> reschedule() async {
    final generation = ++_generation;
    _fallback?.cancel();
    _rolling?.cancel();
    final identity = _ref.read(eduSessionProvider).account?.username;
    if (_identity != identity) {
      _fired.clear();
      _identity = identity;
    }
    final t = _ref.read(timetableProvider).data;
    final service = _ref.read(eduNotificationsProvider);
    if (state <= 0 || t == null || identity == null) {
      await service.cancelClassReminders();
      if (mounted && generation == _generation) {
        _ref.read(reminderStatusProvider.notifier).state = null;
      }
      return;
    }
    final lead = state;
    final now = _ref.read(eduNowProvider)();
    final storage = _ref.read(storageProvider);
    final plans = planReminders(t, now, lead: Duration(minutes: lead), days: 7);
    final examPlans = storage.examReminders()
        ? planExamReminders(
            cachedExams(storage, identity, t.term.code),
            now,
            days: 7,
          )
        : const <ExamReminderPlan>[];
    _fired.retainAll({
      ...t.upcoming(now, days: 7).map(reminderId),
      ...examPlans.map((p) => p.id),
    });
    final all = [
      for (final p in plans)
        (
          id: p.id,
          at: p.at,
          title: reminderTitle(p.occurrence, lead),
          body: reminderBody(p.occurrence),
        ),
      for (final p in examPlans)
        (id: p.id, at: p.at, title: p.title, body: p.body),
    ]..sort((a, b) => a.at.compareTo(b.at));
    if (service.canSchedule) {
      final count = await service.scheduleClassReminders(all);
      if (mounted && generation == _generation) {
        _ref.read(reminderStatusProvider.notifier).state = ReminderStatus(
          count: count,
          until: service.lastSchedule?.until,
          exact: service.lastSchedule?.exact ?? false,
          inApp: false,
        );
      }
    } else {
      await service.cancelClassReminders();
      if (!mounted || generation != _generation) return;
      _ref.read(reminderStatusProvider.notifier).state = ReminderStatus(
        count: all.length,
        until: all.isEmpty ? null : all.last.at,
        exact: false,
        inApp: true,
      );
      void fireDue() {
        final now = _ref.read(eduNowProvider)();
        for (final p in examPlans) {
          if (!now.isBefore(p.at) &&
              now.isBefore(p.at.add(const Duration(minutes: 30))) &&
              _fired.add(p.id)) {
            unawaited(service.classReminderNow(p.title, p.body));
          }
        }
        for (final o in t.upcoming(now, days: 1)) {
          if (!now.isBefore(o.start.subtract(Duration(minutes: lead))) &&
              now.isBefore(o.start) &&
              _fired.add(reminderId(o))) {
            unawaited(
              service.classReminderNow(
                '即将上课：${o.session.displayName}',
                reminderBody(o),
              ),
            );
          }
        }
      }

      fireDue();
      _fallback = Timer.periodic(const Duration(seconds: 30), (_) => fireDue());
    }
    if (!mounted || generation != _generation) return;
    _rolling = Timer(const Duration(hours: 24), () => unawaited(reschedule()));
  }

  @override
  void dispose() {
    ++_generation;
    _fallback?.cancel();
    _rolling?.cancel();
    super.dispose();
  }
}

final eduNotificationsProvider = Provider<NotificationService>(
  (ref) => NotificationService.instance,
);

/// Injectable clock for reminder planning; dates stay absolute UTC instants.
final eduNowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// The shell watches this independently of which tab is visible.
final eduLifecycleProvider = Provider<void>((ref) {
  ref.watch(classReminderProvider);
  // Auto refresh (resume / periodic) and the OS background task follow the
  // shell's lifetime.
  ref.watch(autoRefreshProvider);
  void schedule() =>
      unawaited(ref.read(classReminderProvider.notifier).reschedule());
  ref.listen(timetableProvider, (_, next) {
    schedule();
    unawaited(updateHomeWidget(next.data));
  });
  ref.listen<EduState>(eduSessionProvider, (previous, next) {
    schedule();
    if (next.signedIn &&
        next.account?.username != previous?.account?.username) {
      Future.microtask(() => ref.read(timetableProvider.notifier).sync());
    }
  });
  schedule();
});

String reminderTitle(ClassOccurrence o, int lead) =>
    '$lead 分钟后上课：${o.session.displayName}';

String reminderBody(ClassOccurrence o) {
  final s = o.session;
  final local = o.start.add(const Duration(hours: 8));
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return [
    '$hh:$mm 第${s.startPeriod}-${s.endPeriod}节',
    if (s.room.isNotEmpty) s.room,
    if (s.teacher.isNotEmpty) s.teacher,
  ].join(' · ');
}

final classReminderProvider =
    StateNotifierProvider<ClassReminderController, int>(
      (ref) => ClassReminderController(ref),
    );

// ---------------------------------------------------------------------------
// Grades and exams
// ---------------------------------------------------------------------------

class GradesState {
  const GradesState({this.book, this.loading = false, this.error});
  final GradeBook? book;
  final bool loading;
  final AppError? error;
}

class GradesController extends StateNotifier<GradesState> {
  GradesController(this._ref, this._accountId)
    : _session = _ref.read(eduSessionProvider.notifier),
      _epoch = _ref.read(eduSessionProvider.notifier)._epoch,
      super(
        GradesState(
          book: _accountId == null
              ? null
              : GradeBook.decode(
                  _ref.read(storageProvider).eduGrades(_accountId),
                ),
        ),
      );
  final Ref _ref;
  final String? _accountId;
  final EduSessionController _session;
  final int _epoch;
  int _request = 0;

  bool _current(int request) =>
      mounted && request == _request && _session._current(_epoch);

  Future<void> sync({bool silent = false}) async {
    final id = _accountId;
    if (id == null || state.loading) return;
    final request = ++_request;
    final storage = _ref.read(storageProvider);
    final session = _ref.read(eduSessionProvider.notifier);
    state = GradesState(book: state.book, loading: true);
    try {
      final book = await _ref.read(eduClientProvider).ehall.grades();
      if (!_current(request)) return;
      await session._cacheFor(
        id,
        () => _current(request),
        () async {
          try {
            await _ref.read(eduSyncCoreProvider).recordGrades(id, book);
          } catch (_) {}
          await storage.setEduGrades(id, book.encode());
        },
      );
      if (_current(request)) state = GradesState(book: book);
    } catch (e) {
      if (!_current(request)) return;
      if (silent) {
        state = GradesState(book: state.book, error: state.error);
        return;
      }
      state = GradesState(
        book: state.book,
        error: e is AppError
            ? e
            : AppError(
                AppErrorKind.schemaOrRedirect,
                message: '成绩同步失败',
                raw: e,
              ),
      );
    }
  }

  /// Picks up a book another isolate (the background refresh) wrote.
  void reloadCached() {
    final id = _accountId;
    if (id == null || state.loading) return;
    final cached = GradeBook.decode(_ref.read(storageProvider).eduGrades(id));
    final shown = state.book;
    if (cached == null ||
        (shown != null && !cached.syncedAt.isAfter(shown.syncedAt))) {
      return;
    }
    state = GradesState(book: cached);
  }

  void clear() {
    ++_request;
    state = const GradesState();
  }
}

final gradesProvider = StateNotifierProvider<GradesController, GradesState>(
  (ref) => GradesController(
    ref,
    ref.watch(eduSessionProvider.select((s) => s.account?.username)),
  ),
);

/// Exams for the shown term; a failed refresh falls back only to this identity.
final examsProvider = FutureProvider.autoDispose<List<ExamEntry>>((ref) async {
  final accountId = ref.watch(eduSessionProvider).account?.username;
  final term = ref.watch(timetableProvider.select((s) => s.data?.term));
  if (term == null || accountId == null) return const [];
  final storage = ref.read(storageProvider);
  final session = ref.read(eduSessionProvider.notifier);
  var active = true;
  ref.onDispose(() => active = false);
  try {
    final list = await ref.read(eduClientProvider).ehall.exams(term);
    await session._cacheFor(
      accountId,
      () => active,
      () => storage.setEduExams(
        accountId,
        term.code,
        jsonEncode([for (final e in list) e.toJson()]),
      ),
    );
    if (active) {
      unawaited(ref.read(classReminderProvider.notifier).reschedule());
    }
    return active ? list : const [];
  } on AppError {
    if (!active) return const [];
    final raw = storage.eduExams(accountId, term.code);
    if (raw == null) rethrow;
    try {
      return [
        for (final e in jsonDecode(raw) as List)
          ExamEntry.fromJson(e as Map<String, dynamic>),
      ];
    } catch (_) {
      throw AppError(AppErrorKind.schemaOrRedirect, message: '考试安排缓存损坏，请重新同步');
    }
  }
});

/// Today's date on the school calendar, for widgets that only need the day.
DateTime schoolToday() => schoolDate(DateTime.now());
