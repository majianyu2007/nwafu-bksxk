/// Persistent storage: saved accounts (with secure password), the per-account
/// monitor watch-lists, and app preferences.
///
/// Passwords live in flutter_secure_storage (Keychain / Keystore / libsecret).
/// Everything else (non-secret account metadata, watch-lists, prefs) lives in
/// SharedPreferences as JSON. Cookies are held by each session's cookie jar.
library;

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';

/// A saved login. The password is stored securely and referenced by [id];
/// it is never serialised into SharedPreferences.
class Account {
  Account({
    required this.id,
    required this.loginName,
    required this.displayName,
    this.studentCode = '',
    this.lastBatchCode = '',
  });

  /// Stable local id (loginName is used as the id — one entry per login name).
  final String id;
  final String loginName;
  final String displayName;
  final String studentCode;

  /// The round the account last worked in, restored on the next sign-in.
  final String lastBatchCode;

  Account copyWith({
    String? displayName,
    String? studentCode,
    String? lastBatchCode,
  }) =>
      Account(
        id: id,
        loginName: loginName,
        displayName: displayName ?? this.displayName,
        studentCode: studentCode ?? this.studentCode,
        lastBatchCode: lastBatchCode ?? this.lastBatchCode,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'loginName': loginName,
        'displayName': displayName,
        'studentCode': studentCode,
        'lastBatchCode': lastBatchCode,
      };

  factory Account.fromJson(Map<String, dynamic> j) => Account(
        id: j['id'] as String,
        loginName: j['loginName'] as String,
        displayName: (j['displayName'] as String?) ?? j['loginName'] as String,
        studentCode: (j['studentCode'] as String?) ?? '',
        lastBatchCode: (j['lastBatchCode'] as String?) ?? '',
      );
}

class Storage {
  Storage(this._prefs);

  final SharedPreferences _prefs;
  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    // macOS: use the legacy file-based keychain instead of the data-protection
    // keychain. The data-protection keychain requires a real code signature
    // (Apple Developer team); without one it throws errSecMissingEntitlement
    // (-34018). The file-based keychain works on unsigned/ad-hoc local builds,
    // which is what most users of an unsigned .app will run.
    mOptions: MacOsOptions(useDataProtectionKeyChain: false),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const _kAccounts = 'accounts.v1';
  static const _kActiveAccount = 'active_account.v1';
  static const _kWatches = 'watches.v1';
  static const _kThemeMode = 'theme_mode.v1';
  static const _kSeedColor = 'seed_color.v1';
  static const _kUseDynamicColor = 'use_dynamic_color.v1';
  static const _kOrigin = 'api_origin.v1';
  static const _kMonitorConfig = 'monitor_config.v1';
  static const _kOcrApi = 'ocr_api.v1';
  static const _kAutoOcr = 'auto_ocr.v1';
  static const _kSilentRelogin = 'silent_relogin_attempts.v1';
  static const _kAckedUnsuccessful = 'acked_unsuccessful.v1';
  static const _kSilentReloginOn = 'silent_relogin_enabled.v1';
  static const _kContestedGuard = 'contested_guard.v1';
  static const _kContestedMinutes = 'contested_minutes.v1';
  static const _kMultiAccount = 'multi_account.v1';
  static const _kRunInBackground = 'run_in_background.v1';
  static const _kKeepAwake = 'keep_awake.v1';
  static const _kCache = 'cache.v1';
  static String _pwKey(String id) => 'pw::$id';
  static String _watchesKey(String accountId) => '$_kWatches::$accountId';

  static Future<Storage> open() async =>
      Storage(await SharedPreferences.getInstance());

  // ---- Accounts ----
  List<Account> accounts() {
    final raw = _prefs.getString(_kAccounts);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => Account.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<void> _saveAccounts(List<Account> list) async {
    await _prefs.setString(
        _kAccounts, jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  /// Set false when a secure-storage operation throws (e.g. missing keychain
  /// entitlement on an unsigned macOS build, errSecMissingEntitlement/-34018).
  /// The app keeps working; the password just isn't persisted this session.
  bool secureStorageAvailable = true;

  Future<void> _secureWrite(String key, String value) async {
    try {
      await _secure.write(key: key, value: value);
    } catch (_) {
      secureStorageAvailable = false;
    }
  }

  Future<String?> _secureRead(String key) async {
    try {
      return await _secure.read(key: key);
    } catch (_) {
      secureStorageAvailable = false;
      return null;
    }
  }

  Future<void> _secureDelete(String key) async {
    try {
      await _secure.delete(key: key);
    } catch (_) {
      secureStorageAvailable = false;
    }
  }

  /// Upserts an account (matched by id) and stores its password securely when given.
  Future<void> upsertAccount(Account account, {String? password}) async {
    final list = accounts();
    final idx = list.indexWhere((a) => a.id == account.id);
    if (idx >= 0) {
      list[idx] = account;
    } else {
      list.add(account);
    }
    await _saveAccounts(list);
    if (password != null) {
      await _secureWrite(_pwKey(account.id), password);
    }
  }

  Future<void> removeAccount(String id) async {
    final list = accounts()..removeWhere((a) => a.id == id);
    await _saveAccounts(list);
    await _secureDelete(_pwKey(id));
    await _prefs.remove(_watchesKey(id));
    if (activeAccountId() == id) {
      await setActiveAccount(list.isEmpty ? null : list.first.id);
    }
  }

  Future<String?> passwordFor(String id) => _secureRead(_pwKey(id));

  /// The account the login screen offers first.
  String? activeAccountId() => _prefs.getString(_kActiveAccount);

  Future<void> setActiveAccount(String? id) async {
    if (id == null) {
      await _prefs.remove(_kActiveAccount);
    } else {
      await _prefs.setString(_kActiveAccount, id);
    }
  }

  Account? activeAccount() {
    final id = activeAccountId();
    if (id == null) return null;
    for (final a in accounts()) {
      if (a.id == id) return a;
    }
    return null;
  }

  // ---- Watch lists (monitor targets), one per account ----
  String watchesJson(String accountId) =>
      _prefs.getString(_watchesKey(accountId)) ??
      // Lists saved before watch-lists were per account belong to whoever
      // signs in first; the legacy key is dropped once claimed.
      _prefs.getString(_kWatches) ??
      '[]';

  Future<void> setWatchesJson(String accountId, String json) async {
    await _prefs.setString(_watchesKey(accountId), json);
    if (_prefs.containsKey(_kWatches)) await _prefs.remove(_kWatches);
  }

  // ---- 落选 acknowledgements (so the popup shows once per row) ----
  Set<String> acknowledgedUnsuccessful(String accountId) =>
      (_prefs.getStringList('$_kAckedUnsuccessful::$accountId') ?? const [])
          .toSet();

  Future<void> addAcknowledgedUnsuccessful(
      String accountId, Iterable<String> wids) async {
    final all = {...acknowledgedUnsuccessful(accountId), ...wids};
    await _prefs.setStringList(
        '$_kAckedUnsuccessful::$accountId', all.toList());
  }

  // ---- Preferences ----
  /// 0 system, 1 light, 2 dark.
  int themeModeIndex() => _prefs.getInt(_kThemeMode) ?? 0;
  Future<void> setThemeModeIndex(int v) async => _prefs.setInt(_kThemeMode, v);

  double textScale() =>
      (_prefs.getDouble('text_scale.v1') ?? 1).clamp(0.85, 1.6);
  Future<void> setTextScale(double value) =>
      _prefs.setDouble('text_scale.v1', value.clamp(0.85, 1.6));

  int seedColor() => _prefs.getInt(_kSeedColor) ?? 0xFF3B6FE0;
  Future<void> setSeedColor(int v) async => _prefs.setInt(_kSeedColor, v);

  /// Follow the platform accent colour (Android 12+ / macOS) instead of the
  /// chosen seed. Off by default so the theme colour picker actually works.
  bool useDynamicColor() => _prefs.getBool(_kUseDynamicColor) ?? false;
  Future<void> setUseDynamicColor(bool v) async =>
      _prefs.setBool(_kUseDynamicColor, v);

  /// A build/run-time override for temporary backends. This deliberately wins
  /// over persisted settings so `flutter run --dart-define=BKSXK_API_ORIGIN=…`
  /// cannot accidentally contact production during a simulator session.
  static const defaultOrigin = Env.defaultOrigin;
  static const _definedOrigin = String.fromEnvironment('BKSXK_API_ORIGIN');

  static bool get originLockedByBuild => _definedOrigin.isNotEmpty;

  String origin() => _definedOrigin.isNotEmpty
      ? _definedOrigin
      : (_prefs.getString(_kOrigin) ?? defaultOrigin);
  Future<void> setOrigin(String v) async => _prefs.setString(_kOrigin, v);

  /// Monitor config JSON (cadence + rush mode). Null until the user customizes.
  String? monitorConfigJson() => _prefs.getString(_kMonitorConfig);
  Future<void> setMonitorConfigJson(String v) async =>
      _prefs.setString(_kMonitorConfig, v);

  /// OCR-API config JSON. Null means use the built-in on-device model.
  String? ocrApiConfigJson() => _prefs.getString(_kOcrApi);
  Future<void> setOcrApiConfigJson(String? v) async {
    if (v == null) {
      await _prefs.remove(_kOcrApi);
    } else {
      await _prefs.setString(_kOcrApi, v);
    }
  }

  /// How many captcha-solving attempts the silent re-login makes when the
  /// session drops before giving up and asking the user. 0 = always ask.
  static const defaultSilentReloginAttempts = 3;
  int silentReloginAttempts() =>
      _prefs.getInt(_kSilentRelogin) ?? defaultSilentReloginAttempts;
  Future<void> setSilentReloginAttempts(int v) async =>
      _prefs.setInt(_kSilentRelogin, v);

  /// Whether captcha auto-recognition is on. Defaults to true (the OCR solver
  /// is bundled; the user can opt out on the login screen).
  bool autoOcr() => _prefs.getBool(_kAutoOcr) ?? true;
  Future<void> setAutoOcr(bool v) async => _prefs.setBool(_kAutoOcr, v);

  /// Whether a dropped session is re-logged in silently at all. Off = every
  /// drop goes straight to the re-login dialog.
  bool silentReloginEnabled() => _prefs.getBool(_kSilentReloginOn) ?? true;
  Future<void> setSilentReloginEnabled(bool v) async =>
      _prefs.setBool(_kSilentReloginOn, v);

  /// Contested-session guard: stop re-logging in when the account keeps being
  /// kicked (someone else is using it). Off by default.
  bool contestedGuardEnabled() => _prefs.getBool(_kContestedGuard) ?? false;
  Future<void> setContestedGuardEnabled(bool v) async =>
      _prefs.setBool(_kContestedGuard, v);
  int contestedWindowMinutes() => _prefs.getInt(_kContestedMinutes) ?? 3;
  Future<void> setContestedWindowMinutes(int v) async =>
      _prefs.setInt(_kContestedMinutes, v);

  /// Several accounts signed in at once, as tabs. Off by default.
  bool multiAccountEnabled() => _prefs.getBool(_kMultiAccount) ?? false;
  Future<void> setMultiAccountEnabled(bool v) async =>
      _prefs.setBool(_kMultiAccount, v);

  /// Keep running after the window is closed (desktop: tray; Android:
  /// foreground service while the monitor runs).
  bool runInBackground() => _prefs.getBool(_kRunInBackground) ?? true;
  Future<void> setRunInBackground(bool v) async =>
      _prefs.setBool(_kRunInBackground, v);

  /// Keep the device awake while the monitor runs.
  bool keepAwake() => _prefs.getBool(_kKeepAwake) ?? true;
  Future<void> setKeepAwake(bool v) async => _prefs.setBool(_kKeepAwake, v);

  // Calendar calibration and update preferences are not disposable course data.
  String? academicCalendarJson(String termKey) =>
      _prefs.getString('academic_calendar.v1::$termKey');
  Future<void> setAcademicCalendarJson(String termKey, String value) =>
      _prefs.setString('academic_calendar.v1::$termKey', value);

  int? updateLastCheckMillis() => _prefs.getInt('updates.last_check.v1');
  Future<void> setUpdateLastCheckMillis(int value) =>
      _prefs.setInt('updates.last_check.v1', value);

  // ---- Course cache (gzip+base64 JSON blobs, see CourseCache) ----
  String? cacheGet(String key) => _prefs.getString('$_kCache::$key');
  Future<void> cacheSet(String key, String value) =>
      _prefs.setString('$_kCache::$key', value);
  Future<void> cacheRemove(String key) => _prefs.remove('$_kCache::$key');
  Future<void> cacheClear() async {
    for (final k in _prefs.getKeys().where((k) => k.startsWith('$_kCache::'))) {
      await _prefs.remove(k);
    }
  }
}
