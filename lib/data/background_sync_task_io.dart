/// Background entrypoint. Runs in a headless isolate started by the OS, so
/// it rebuilds only what a refresh needs: [Storage], a CAS client over the
/// saved (secure) cookie jar, and a silent re-login with the saved password
/// or passkey. This app's bound device passkey is used without a biometric
/// prompt only when the user turned on `backgroundUseDeviceKey`. MFA is
/// never answered here; the task just gives up until the next run.
library;

import 'dart:convert';
import 'dart:io' show Platform;

import 'package:cookie_jar/cookie_jar.dart' show PersistCookieJar;
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;
import 'package:workmanager/workmanager.dart';

import '../core/crypto/passkey.dart';
import 'background_sync.dart';
import 'background_sync_task.dart' show kBackgroundRefreshTask;
import 'calendar_sync.dart';
import 'cas_client.dart';
import 'edu_models.dart';
import 'ehall_service.dart';
import 'home_widget_sync.dart';
import 'notifications.dart';
import 'secure_cookie_storage.dart';
import 'storage.dart';

bool get backgroundRefreshSupported => Platform.isAndroid || Platform.isIOS;

bool _initialized = false;

Future<void> initBackgroundRefresh() async {
  if (!backgroundRefreshSupported || _initialized) return;
  try {
    await Workmanager().initialize(eduBackgroundDispatcher);
    _initialized = true;
  } catch (_) {
    // A platform without the native side keeps the in-app refresh only.
  }
}

Future<void> applyBackgroundRefresh(int hours) async {
  if (!backgroundRefreshSupported) return;
  await initBackgroundRefresh();
  if (!_initialized) return;
  try {
    if (hours <= 0) {
      await Workmanager().cancelByUniqueName(kBackgroundRefreshTask);
      return;
    }
    await Workmanager().registerPeriodicTask(
      kBackgroundRefreshTask,
      kBackgroundRefreshTask,
      frequency: Duration(hours: hours),
      // iOS ignores frequency; earliestBeginDate comes from initialDelay.
      // It is only a lower bound: iOS picks the actual time from usage and
      // battery, and may skip days. AppDelegate.swift uses the same delay
      // for the follow-up runs it schedules itself.
      initialDelay: Platform.isIOS ? iosEarliestBegin(hours) : null,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  } catch (_) {}
}

/// The earliest-begin delay for the iOS BGAppRefreshTask: the sync
/// interval, clamped to 1–24 h (keep in step with AppDelegate.swift).
Duration iosEarliestBegin(int hours) => Duration(hours: hours.clamp(1, 24));

@pragma('vm:entry-point')
void eduBackgroundDispatcher() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      await runBackgroundRefresh();
    } catch (_) {
      // Never ask WorkManager to retry: a failing login would only repeat.
    }
    return true;
  });
}

/// One background refresh. Returns false when nothing was fetched.
Future<bool> runBackgroundRefresh() async {
  final storage = await Storage.open();
  final account = _savedAccount(storage.eduAccount());
  if (account == null) return false;
  final hours = storage.eduSyncIntervalHours();
  if (!refreshDue(
    storage.eduLastSync(account.username),
    hours,
    DateTime.now().toUtc(),
  )) {
    // No network sync yet, but roll the widget's day window forward from
    // the cache so it never runs out of days.
    await updateHomeWidget(_cachedTimetable(storage, account.username));
    return false;
  }
  final cookies = SecureCookieStorage(storage, account.username);
  final cas = CasClient(cookieJar: PersistCookieJar(storage: cookies));
  final ehall = EhallService(cas)..expectedUsername = account.username;
  ehall.onLoginRequired = () => _silentLogin(storage, cas, account);
  final notifications = NotificationService.instance;
  await notifications.init();
  try {
    final EduRefreshResult result;
    try {
      result = await EduSyncCore(
        storage,
        notifications,
      ).refresh(account.username, ehall);
    } catch (_) {
      await updateHomeWidget(_cachedTimetable(storage, account.username));
      rethrow;
    }
    // Also reloads the iOS widget timeline (WidgetCenter) / Android widgets.
    await updateHomeWidget(result.timetable);
    if (storage.calendarSyncEnabled()) {
      try {
        await syncTimetableToCalendar(
          adapter: deviceCalendarAdapter(),
          storage: storage,
          accountId: account.username,
          timetable: result.timetable,
          exams:
              result.exams ??
              cachedExams(
                storage,
                account.username,
                result.timetable.term.code,
              ),
        );
      } catch (_) {}
    }
    return true;
  } finally {
    cas.dio.close(force: true);
    await cookies.close();
  }
}

/// The cached timetable of the account's current term, if any.
TermTimetable? _cachedTimetable(Storage storage, String accountId) {
  try {
    final raw = storage.eduCurrentTerm(accountId);
    if (raw == null) return null;
    final term = EduTerm.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    return TermTimetable.decode(storage.eduTimetable(accountId, term.code));
  } catch (_) {
    return null;
  }
}

Future<bool> _silentLogin(
  Storage storage,
  CasClient cas,
  ({String username, bool usePasskey}) account,
) async {
  PasskeyCredential? passkey;
  String? password;
  if (account.usePasskey) {
    passkey = _passkey(await storage.eduPasskey(account.username));
  } else {
    password = await storage.eduPassword(account.username);
  }
  if (passkey == null &&
      (password == null || password.isEmpty) &&
      storage.backgroundUseDeviceKey()) {
    passkey = _passkey(await storage.eduDeviceKey(account.username));
  }
  if (passkey == null && (password == null || password.isEmpty)) return false;
  try {
    await cas.login(
      service: EmapApp.timetable.indexUrl,
      username: account.username,
      password: password ?? '',
      passkey: passkey,
    );
    return true;
  } on CasMfaRequired {
    await cas.clearSession();
    return false;
  } catch (_) {
    return false;
  }
}

PasskeyCredential? _passkey(String? raw) {
  if (raw == null) return null;
  try {
    return PasskeyCredential.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
}

/// The non-secret account record `EduAccount.encode` writes.
({String username, bool usePasskey})? _savedAccount(String? raw) {
  if (raw == null) return null;
  try {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final u = j['u'] as String?;
    if (u == null || u.isEmpty) return null;
    return (username: u, usePasskey: (j['pk'] as bool?) ?? false);
  } catch (_) {
    return null;
  }
}
