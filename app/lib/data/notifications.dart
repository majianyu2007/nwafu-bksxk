/// Local system notifications for grab/seat events (desktop + mobile).
///
/// Wraps flutter_local_notifications behind a tiny surface so the rest of the
/// app fires semantic events ("grabbed", "seat open", "stopped") without knowing
/// platform details. Initialization is best-effort: if a platform lacks support
/// or permission, calls degrade to no-ops rather than throwing.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  int _id = 0;

  /// Initializes the plugin for the current platform. Safe to call more than
  /// once. Notifications are unsupported on web, where this is a no-op.
  Future<void> init() async {
    if (_ready || kIsWeb) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: false,
      requestSoundPermission: true,
    );
    const linux = LinuxInitializationSettings(defaultActionName: '打开');
    const settings = InitializationSettings(
      android: android,
      iOS: darwin,
      macOS: darwin,
      linux: linux,
    );
    try {
      await _plugin.initialize(settings);
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  /// Requests notification permission where the OS requires an explicit prompt
  /// (iOS/macOS/Android 13+). Best-effort.
  Future<void> requestPermission() async {
    if (!_ready || kIsWeb) return;
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, sound: true);
      await _plugin
          .resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, sound: true);
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (_) {
      // Ignore — notifications simply won't show.
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

  Future<void> _show(String title, String body) async {
    if (!_ready || kIsWeb) return;
    try {
      await _plugin.show(_id++, title, body, _details);
    } catch (_) {
      // Best-effort.
    }
  }

  /// A course was successfully grabbed.
  Future<void> grabbed({required String courseName, required String className, String? place}) =>
      _show('🎉 抢课成功', '$courseName · $className${place != null && place.isNotEmpty ? '\n$place' : ''}');

  /// A seat opened for a watched class (before/independent of grabbing).
  Future<void> seatOpen({required String courseName, required String className, required int remaining}) =>
      _show('有余量了', '$courseName · $className 余 $remaining');

  /// A drop succeeded.
  Future<void> dropped({required String courseName, required String className}) =>
      _show('已退选', '$courseName · $className');

  /// Monitoring auto-stopped (maintenance/throttle/abnormal).
  Future<void> monitorStopped(String reason) => _show('监控已自动停止', reason);
}
