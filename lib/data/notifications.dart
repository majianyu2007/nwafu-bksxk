/// Local system notifications for grab/seat events (desktop + mobile).
///
/// Wraps flutter_local_notifications behind a tiny surface so the rest of the
/// app fires semantic events ("grabbed", "seat open", "stopped") without knowing
/// platform details. Initialization is best-effort: if a platform lacks support
/// or permission, calls degrade to no-ops rather than throwing.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'background_sync.dart' show EduAlerts;
import 'browser_notifications.dart';

class NotificationService implements EduAlerts {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();
  static final NotificationService instance = NotificationService();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;
  int _id = 0;
  Future<void>? _initializing;
  final BrowserNotifications _browser = BrowserNotifications();
  NotificationTapCallback? _onTap;
  String? _pendingPayload;

  /// Initializes the platform backend. Repeated calls update the tap handler,
  /// allowing the signed-in shell to take over navigation after app startup.
  Future<void> init({NotificationTapCallback? onTap}) async {
    if (onTap != null) {
      _onTap = onTap;
      final pending = _pendingPayload;
      _pendingPayload = null;
      if (pending != null) onTap(pending);
    }
    if (_ready) return;
    final pending = _initializing;
    if (pending != null) return pending;
    final initialization = _initialize();
    _initializing = initialization;
    try {
      await initialization;
    } finally {
      if (identical(_initializing, initialization)) _initializing = null;
    }
  }

  Future<void> _initialize() async {
    if (kIsWeb) {
      _ready = true;
      return;
    }
    const android = AndroidInitializationSettings('@drawable/ic_notification');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const linux = LinuxInitializationSettings(defaultActionName: '打开');
    const windows = WindowsInitializationSettings(
      appName: '西农本科选课',
      appUserModelId: 'cn.edu.nwafu.nwafuBksxk',
      guid: '6f1e2c3a-7b4d-4e5f-9a80-1c2d3e4f5a6b',
    );
    const settings = InitializationSettings(
      android: android,
      iOS: darwin,
      macOS: darwin,
      linux: linux,
      windows: windows,
    );
    try {
      final initialized = await _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: (response) =>
            _dispatchTap(response.payload),
      );
      _ready = initialized != false;
      if (!_ready) return;
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        _dispatchTap(launch?.notificationResponse?.payload);
      }
    } catch (_) {
      _ready = false;
    }
  }

  /// Forgets [handler] if it is the active tap handler, so later taps are
  /// buffered until the next [init] with a handler instead of being dropped.
  void detachTapHandler(NotificationTapCallback handler) {
    if (identical(_onTap, handler)) _onTap = null;
  }

  void _dispatchTap(String? payload) {
    final onTap = _onTap;
    if (onTap != null) {
      onTap(payload);
    } else {
      _pendingPayload = payload;
    }
  }

  String get browserPermission => kIsWeb ? _browser.permission : 'native';

  /// Requests notification permission from a direct user action.
  Future<bool> requestPermission() async {
    if (!_ready) await init();
    if (kIsWeb) {
      try {
        return await _browser.requestPermission();
      } catch (_) {
        return false;
      }
    }
    if (!_ready) return false;
    try {
      final ios = await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, sound: true);
      final macos = await _plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, sound: true);
      final android = await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      return ios != false && macos != false && android != false;
    } catch (_) {
      return false;
    }
  }

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'grab_events',
      '抢课通知',
      channelDescription: '选课成功、退课、余量变动等提醒',
      importance: Importance.max,
      priority: Priority.high,
      icon: '@drawable/ic_notification',
    ),
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
    linux: LinuxNotificationDetails(urgency: LinuxNotificationUrgency.critical),
    windows: WindowsNotificationDetails(),
  );

  Future<void> _show(
    String title,
    String body, {
    required String payload,
    required String tag,
    NotificationDetails details = _details,
  }) async {
    if (!_ready) await init();
    if (kIsWeb) {
      _browser.show(
        title: title,
        body: body,
        tag: tag,
        payload: payload,
        onTap: _onTap,
      );
      return;
    }
    if (!_ready) return;
    try {
      await _plugin.show(
        id: _id++,
        title: title,
        body: body,
        notificationDetails: details,
        payload: payload,
      );
    } catch (_) {
      // Best-effort.
    }
  }

  /// A course was successfully grabbed.
  Future<void> grabbed({
    required String courseName,
    required String className,
    String? place,
    String who = '',
  }) => _show(
    who.isEmpty ? '抢课成功' : '$who 抢课成功',
    '$courseName $className${place != null && place.isNotEmpty ? '\n$place' : ''}',
    payload: 'selected',
    tag: 'grabbed',
  );

  /// A drop succeeded.
  Future<void> dropped({
    required String courseName,
    required String className,
  }) => _show(
    '已退选',
    '$courseName $className',
    payload: 'selected',
    tag: 'dropped',
  );

  /// The session dropped and silent re-login failed; the user must log in.
  Future<void> sessionExpired({String who = ''}) => _show(
    who.isEmpty ? '登录已失效' : '$who 登录已失效',
    '自动重新登录未成功，请回到应用重新登录，监控已暂停',
    payload: 'home',
    tag: 'session-expired',
  );

  /// 落选 rows the student has not acknowledged yet.
  Future<void> unsuccessful({required int count, required String first}) =>
      _show('有 $count 门课程落选', first, payload: 'selected', tag: 'unsuccessful');

  /// Monitoring auto-stopped (maintenance/throttle/abnormal).
  Future<void> monitorStopped(String reason, {String who = ''}) => _show(
    who.isEmpty ? '监控已停止' : '$who 的监控已停止',
    reason,
    payload: 'monitor',
    tag: 'monitor-stopped',
  );

  // ---- Timetable / grade updates (from the auto refresh) ----

  static const _updateDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'timetable_updates',
      '课表与成绩更新',
      channelDescription: '课表变动、新成绩等自动更新提醒',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@drawable/ic_notification',
    ),
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
    linux: LinuxNotificationDetails(),
    windows: WindowsNotificationDetails(),
  );

  @override
  Future<void> timetableUpdated(String body) => _show(
    '课表有更新',
    body,
    payload: 'timetable',
    tag: 'timetable-updated',
    details: _updateDetails,
  );

  @override
  Future<void> gradesUpdated(String body) => _show(
    '有新成绩',
    body,
    payload: 'grades',
    tag: 'grades-updated',
    details: _updateDetails,
  );

  // ---- Class reminders (scheduled by the OS) ----

  static const _reminderDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'class_reminders',
      '上课提醒',
      channelDescription: '课前提醒：课程、时间与教室',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_notification',
      category: AndroidNotificationCategory.reminder,
    ),
    iOS: DarwinNotificationDetails(
      interruptionLevel: InterruptionLevel.timeSensitive,
    ),
    macOS: DarwinNotificationDetails(),
    windows: WindowsNotificationDetails(),
  );

  bool _tzReady = false;
  final _scheduled = <int>{};
  Future<void> _reminderMutations = Future.value();
  int _reminderGeneration = 0;

  /// Whether the platform can hand reminders to the OS. Linux and the web
  /// have no scheduler; there the shell fires due reminders while running.
  bool get canSchedule =>
      !kIsWeb && defaultTargetPlatform != TargetPlatform.linux;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  /// Android 12+: whether exact alarms are allowed (null off Android).
  Future<bool?> canScheduleExactAlarms() async {
    if (!_isAndroid) return null;
    if (!_ready) await init();
    try {
      return await _android?.canScheduleExactNotifications();
    } catch (_) {
      return false;
    }
  }

  /// Opens the system "闹钟和提醒" page; returns whether access is granted.
  Future<bool> requestExactAlarms() async {
    if (!_isAndroid) return false;
    if (!_ready) await init();
    try {
      return await _android?.requestExactAlarmsPermission() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// What the last successful schedule handed to the OS.
  ({int count, DateTime? until, bool exact})? lastSchedule;

  /// Replaces every scheduled class reminder with [plans]. Ids not in
  /// [plans] (dropped or changed classes) are cancelled. Returns how many
  /// were scheduled.
  Future<int> scheduleClassReminders(
    List<({int id, DateTime at, String title, String body})> plans,
  ) {
    final generation = ++_reminderGeneration;
    final next = _reminderMutations.then(
      (_) => _replaceClassReminders(plans, generation),
    );
    _reminderMutations = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  Future<int> _replaceClassReminders(
    List<({int id, DateTime at, String title, String body})> plans,
    int generation,
  ) async {
    if (generation != _reminderGeneration) return 0;
    if (!_ready) await init();
    if (!_ready || !canSchedule) return 0;
    if (!_tzReady) {
      tzdata.initializeTimeZones();
      _tzReady = true;
    }
    final shanghai = tz.getLocation('Asia/Shanghai');
    final wanted = {for (final p in plans) p.id};
    final known = {..._scheduled};
    try {
      final pending = await _plugin.pendingNotificationRequests();
      known.addAll(pending.where((p) => p.id >= _reminderIdBase).map((p) => p.id));
    } catch (_) {
      // Keep our successful writes when the OS cannot enumerate its queue.
    }
    for (final id in known.difference(wanted)) {
      try {
        await _plugin.cancel(id: id);
        _scheduled.remove(id);
      } catch (_) {
        // Retain failed cancellations so a later plan can retry them.
        _scheduled.add(id);
      }
    }
    var mode = AndroidScheduleMode.inexactAllowWhileIdle;
    if (_isAndroid && plans.isNotEmpty) {
      try {
        if (await _android?.canScheduleExactNotifications() ?? false) {
          mode = AndroidScheduleMode.exactAllowWhileIdle;
        }
      } catch (_) {}
    }
    var count = 0;
    DateTime? until;
    for (final p in plans) {
      if (generation != _reminderGeneration) break;
      try {
        await _plugin.zonedSchedule(
          id: p.id,
          title: p.title,
          body: p.body,
          scheduledDate: tz.TZDateTime.from(p.at, shanghai),
          notificationDetails: _reminderDetails,
          androidScheduleMode: mode,
          payload: 'timetable',
        );
        count++;
        if (until == null || p.at.isAfter(until)) until = p.at;
        _scheduled.add(p.id);
      } catch (_) {
        // Best-effort; a platform without scheduling simply gets none.
      }
    }
    if (generation == _reminderGeneration) {
      lastSchedule = (
        count: count,
        until: until,
        exact: mode == AndroidScheduleMode.exactAllowWhileIdle,
      );
    }
    return count;
  }

  Future<void> cancelClassReminders() => scheduleClassReminders(const []);

  /// Shows a reminder now (Linux/web fallback, or a test from Settings).
  Future<void> classReminderNow(String title, String body) =>
      _show(title, body, payload: 'timetable', tag: 'class-reminder');

  static const _reminderIdBase = 1 << 30;
}
