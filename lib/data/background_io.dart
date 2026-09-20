/// Native keep-alive: desktop tray + close-to-hide + wakelock, Android
/// foreground service, iOS wakelock.
library;

import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';

import 'background.dart';

bool get _desktop => Platform.isMacOS || Platform.isWindows || Platform.isLinux;
bool get supportsTray => _desktop;
bool get supportsForegroundService => Platform.isAndroid;

BackgroundHost? _host;
bool _trayShown = false;
bool _closeToTray = false;
bool _serviceRunning = false;
Future<void> _monitoringUpdate = Future<void>.value();
final _windowListener = _WindowCloser();

Future<void> init() async {
  if (_desktop) {
    await windowManager.ensureInitialized();
    windowManager.addListener(_windowListener);
  }
  if (Platform.isAndroid) {
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'monitor_keepalive',
        channelName: '抢课监控',
        channelDescription: '监控运行时保持应用在后台工作',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions:
          const IOSNotificationOptions(showNotification: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowWifiLock: true,
        autoRunOnBoot: false,
      ),
    );
  }
}

void attach(BackgroundHost host) {
  _host = host;
}

Future<void> setCloseToTray(bool enabled) async {
  if (!_desktop) return;
  _closeToTray = enabled;
  await windowManager.setPreventClose(enabled);
  if (enabled) {
    await _ensureTray();
  } else if (_trayShown) {
    await trayManager.destroy();
    _trayShown = false;
  }
}

Future<void> setMonitoring(bool running,
    {required bool runInBackground, required bool keepAwake}) {
  // A stop must wait for an in-flight permission prompt/start to finish;
  // otherwise it can observe _serviceRunning=false and leave a late start alive.
  final next = _monitoringUpdate.then((_) => _applyMonitoring(running,
      runInBackground: runInBackground, keepAwake: keepAwake));
  _monitoringUpdate = next.catchError((Object _) {});
  return next;
}

Future<void> _applyMonitoring(bool running,
    {required bool runInBackground, required bool keepAwake}) async {
  try {
    if (keepAwake) {
      await WakelockPlus.toggle(enable: running);
    } else if (await WakelockPlus.enabled) {
      await WakelockPlus.disable();
    }
  } catch (_) {
    // wakelock is best effort.
  }
  if (Platform.isAndroid && runInBackground) {
    if (running && !_serviceRunning) {
      try {
        await FlutterForegroundTask.requestNotificationPermission();
        if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
          await FlutterForegroundTask.requestIgnoreBatteryOptimization();
        }
        final res = await FlutterForegroundTask.startService(
          serviceTypes: [ForegroundServiceTypes.dataSync],
          notificationTitle: '西农本科选课',
          notificationText: _host?.statusLine ?? '监控运行中',
          notificationIcon: const NotificationIcon(
              metaDataName: 'cn.edu.nwafu.nwafu_bksxk.NOTIFICATION_ICON'),
        );
        _serviceRunning = res is ServiceRequestSuccess;
      } catch (_) {
        _serviceRunning = false;
      }
    } else if (!running && _serviceRunning) {
      try {
        await FlutterForegroundTask.stopService();
      } catch (_) {}
      _serviceRunning = false;
    }
  } else if (Platform.isAndroid && _serviceRunning) {
    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}
    _serviceRunning = false;
  }
  if (_trayShown) await updateStatus(_host?.statusLine ?? '');
}

Future<void> updateStatus(String text) async {
  if (_trayShown) {
    try {
      await trayManager.setToolTip(text.isEmpty ? '西农本科选课' : '西农本科选课：$text');
    } catch (_) {}
  }
  if (_serviceRunning) {
    try {
      await FlutterForegroundTask.updateService(
          notificationTitle: '西农本科选课', notificationText: text);
    } catch (_) {}
  }
}

Future<void> _ensureTray() async {
  if (_trayShown) return;
  try {
    if (Platform.isMacOS) {
      await trayManager.setIcon('assets/icons/tray_template.png',
          isTemplate: true);
    } else if (Platform.isWindows) {
      await trayManager.setIcon('assets/icons/tray.ico');
    } else {
      await trayManager.setIcon('assets/icons/tray_color.png');
    }
    await trayManager.setToolTip('西农本科选课');
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(key: 'show', label: '打开窗口'),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: '退出'),
    ]));
    trayManager.addListener(_TrayHandler());
    _trayShown = true;
  } catch (_) {
    _trayShown = false;
  }
}

class _WindowCloser with WindowListener {
  @override
  void onWindowClose() async {
    if (_closeToTray && await windowManager.isPreventClose()) {
      await windowManager.hide();
      if (Platform.isMacOS) {
        // Keep the Dock icon; a click brings the window back (AppDelegate).
      }
    }
  }
}

class _TrayHandler with TrayListener {
  @override
  void onTrayIconMouseDown() {
    if (Platform.isWindows || Platform.isLinux) {
      _show();
    } else {
      trayManager.popUpContextMenu();
    }
  }

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        _show();
      case 'quit':
        _host?.quitApp();
        windowManager
            .setPreventClose(false)
            .then((_) => windowManager.destroy());
    }
  }

  Future<void> _show() async {
    await windowManager.show();
    await windowManager.focus();
    _host?.showApp();
  }
}
