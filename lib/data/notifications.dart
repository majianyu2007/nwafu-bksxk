/// Local system notifications for grab/seat events (desktop + mobile).
///
/// Wraps flutter_local_notifications behind a tiny surface so the rest of the
/// app fires semantic events ("grabbed", "seat open", "stopped") without knowing
/// platform details. Initialization is best-effort: if a platform lacks support
/// or permission, calls degrade to no-ops rather than throwing.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'browser_notifications.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;
  int _id = 0;
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
    if (kIsWeb) {
      _ready = true;
      return;
    }
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const linux = LinuxInitializationSettings(defaultActionName: '打开');
    const settings = InitializationSettings(
      android: android,
      iOS: darwin,
      macOS: darwin,
      linux: linux,
    );
    try {
      await _plugin.initialize(
        settings,
        onDidReceiveNotificationResponse: (response) =>
            _dispatchTap(response.payload),
      );
      _ready = true;
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

  bool get browserSupported => kIsWeb && _browser.supported;
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
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, sound: true);
      final macos = await _plugin
          .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, sound: true);
      final android = await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
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
    ),
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
    linux: LinuxNotificationDetails(urgency: LinuxNotificationUrgency.critical),
  );

  Future<void> _show(String title, String body,
      {required String payload, required String tag}) async {
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
      await _plugin.show(_id++, title, body, _details, payload: payload);
    } catch (_) {
      // Best-effort.
    }
  }

  /// A course was successfully grabbed.
  Future<void> grabbed(
          {required String courseName,
          required String className,
          String? place}) =>
      _show(
        '抢课成功',
        '$courseName · $className${place != null && place.isNotEmpty ? '\n$place' : ''}',
        payload: 'selected',
        tag: 'grabbed',
      );

  /// A seat opened for a watched class (before/independent of grabbing).
  Future<void> seatOpen(
          {required String courseName,
          required String className,
          required int remaining}) =>
      _show(
        '有余量了',
        '$courseName · $className 余 $remaining',
        payload: 'monitor',
        tag: 'seat-open',
      );

  /// A drop succeeded.
  Future<void> dropped(
          {required String courseName, required String className}) =>
      _show(
        '已退选',
        '$courseName · $className',
        payload: 'selected',
        tag: 'dropped',
      );

  /// Monitoring auto-stopped (maintenance/throttle/abnormal).
  Future<void> monitorStopped(String reason) => _show(
        '监控已自动停止',
        reason,
        payload: 'monitor',
        tag: 'monitor-stopped',
      );
}
