/// Persistent storage: saved accounts (with secure password), session tokens,
/// monitor watch-list, and app preferences.
///
/// Passwords live in flutter_secure_storage (Keychain / Keystore / libsecret).
/// Everything else (non-secret account metadata, watch-list, prefs) lives in
/// SharedPreferences as JSON. Cookies are persisted separately by the cookie jar.
library;

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A saved login. The password is stored securely and referenced by [id];
/// it is never serialised into SharedPreferences.
class Account {
  Account({
    required this.id,
    required this.loginName,
    required this.displayName,
    this.studentCode = '',
    this.lastBatchCode = '',
    this.lastToken = '',
  });

  /// Stable local id (loginName is used as the id — one entry per login name).
  final String id;
  final String loginName;
  final String displayName;
  final String studentCode;
  final String lastBatchCode;

  /// Last known token, used to attempt a warm start before full re-login.
  final String lastToken;

  Account copyWith({
    String? displayName,
    String? studentCode,
    String? lastBatchCode,
    String? lastToken,
  }) =>
      Account(
        id: id,
        loginName: loginName,
        displayName: displayName ?? this.displayName,
        studentCode: studentCode ?? this.studentCode,
        lastBatchCode: lastBatchCode ?? this.lastBatchCode,
        lastToken: lastToken ?? this.lastToken,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'loginName': loginName,
        'displayName': displayName,
        'studentCode': studentCode,
        'lastBatchCode': lastBatchCode,
        'lastToken': lastToken,
      };

  factory Account.fromJson(Map<String, dynamic> j) => Account(
        id: j['id'] as String,
        loginName: j['loginName'] as String,
        displayName: (j['displayName'] as String?) ?? j['loginName'] as String,
        studentCode: (j['studentCode'] as String?) ?? '',
        lastBatchCode: (j['lastBatchCode'] as String?) ?? '',
        lastToken: (j['lastToken'] as String?) ?? '',
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
  static const _kOrigin = 'api_origin.v1';
  static const _kMonitorConfig = 'monitor_config.v1';
  static const _kOcrApi = 'ocr_api.v1';
  static String _pwKey(String id) => 'pw::$id';

  static Future<Storage> open() async => Storage(await SharedPreferences.getInstance());

  // ---- Accounts ----
  List<Account> accounts() {
    final raw = _prefs.getString(_kAccounts);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list.map((e) => Account.fromJson((e as Map).cast<String, dynamic>())).toList();
  }

  Future<void> _saveAccounts(List<Account> list) async {
    await _prefs.setString(_kAccounts, jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  /// Set false when a secure-storage operation throws (e.g. missing keychain
  /// entitlement on an unsigned macOS build, errSecMissingEntitlement/-34018).
  /// The app keeps working; the password just isn't persisted this session.
  bool secureStorageAvailable = true;

  /// The last secure-storage error message, for diagnostics.
  String? secureStorageError;

  Future<void> _secureWrite(String key, String value) async {
    try {
      await _secure.write(key: key, value: value);
    } catch (e) {
      secureStorageAvailable = false;
      secureStorageError = '$e';
    }
  }

  Future<String?> _secureRead(String key) async {
    try {
      return await _secure.read(key: key);
    } catch (e) {
      secureStorageAvailable = false;
      secureStorageError = '$e';
      return null;
    }
  }

  Future<void> _secureDelete(String key) async {
    try {
      await _secure.delete(key: key);
    } catch (e) {
      secureStorageAvailable = false;
      secureStorageError = '$e';
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
    if (activeAccountId() == id) {
      await setActiveAccount(list.isEmpty ? null : list.first.id);
    }
  }

  Future<String?> passwordFor(String id) => _secureRead(_pwKey(id));

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
    final list = accounts();
    for (final a in list) {
      if (a.id == id) return a;
    }
    return null;
  }

  // ---- Watch list (monitor targets) ----
  String watchesJson() => _prefs.getString(_kWatches) ?? '[]';
  Future<void> setWatchesJson(String json) async => _prefs.setString(_kWatches, json);

  // ---- Preferences ----
  /// 0 system, 1 light, 2 dark.
  int themeModeIndex() => _prefs.getInt(_kThemeMode) ?? 0;
  Future<void> setThemeModeIndex(int v) async => _prefs.setInt(_kThemeMode, v);

  int seedColor() => _prefs.getInt(_kSeedColor) ?? 0xFF3B6FE0;
  Future<void> setSeedColor(int v) async => _prefs.setInt(_kSeedColor, v);

  String origin() => _prefs.getString(_kOrigin) ?? 'https://bksxk.nwafu.edu.cn';
  Future<void> setOrigin(String v) async => _prefs.setString(_kOrigin, v);

  /// Monitor config JSON (cadence + rush mode). Null until the user customizes.
  String? monitorConfigJson() => _prefs.getString(_kMonitorConfig);
  Future<void> setMonitorConfigJson(String v) async => _prefs.setString(_kMonitorConfig, v);

  /// OCR-API config JSON. Null means use the built-in on-device model.
  String? ocrApiConfigJson() => _prefs.getString(_kOcrApi);
  Future<void> setOcrApiConfigJson(String? v) async {
    if (v == null) {
      await _prefs.remove(_kOcrApi);
    } else {
      await _prefs.setString(_kOcrApi, v);
    }
  }
}
