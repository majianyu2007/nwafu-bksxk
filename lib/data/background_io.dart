/// Native keep-alive: desktop tray + close-to-hide + wakelock, Android
/// foreground service, iOS wakelock.
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' show Size;

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';

import 'background.dart';

const _kWindowWidth = 'ui.window_w.v1';
const _kWindowHeight = 'ui.window_h.v1';
const _kMinWindowSize = Size(360, 520);

bool get _desktop => Platform.isMacOS || Platform.isWindows || Platform.isLinux;
bool get supportsTray => _desktop;
bool get supportsForegroundService => Platform.isAndroid;

BackgroundHost? _host;
bool _trayShown = false;
bool _closeToTray = false;
bool _serviceRunning = false;
Future<void> _monitoringUpdate = Future<void>.value();
Future<void> _trayUpdate = Future<void>.value();
final _windowListener = _WindowCloser();
final _trayListener = _TrayHandler();

Future<void> init() async {
  if (_desktop) {
    await windowManager.ensureInitialized();
    try {
      await windowManager.setMinimumSize(_kMinWindowSize);
      final prefs = await SharedPreferences.getInstance();
      final w = prefs.getDouble(_kWindowWidth);
      final h = prefs.getDouble(_kWindowHeight);
      if (w != null && h != null) {
        final size = Size(w.clamp(360, 3840), h.clamp(520, 2160));
        await windowManager.setSize(size);
      }
    } catch (_) {
      // Best-effort window geometry restoration.
    }
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
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
      ),
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

void detach(BackgroundHost host) {
  if (identical(_host, host)) _host = null;
}

Future<void> setCloseToTray(bool enabled) {
  final next = _trayUpdate.then((_) => _applyCloseToTray(enabled));
  _trayUpdate = next.catchError((Object _) {});
  return next;
}

Future<void> _applyCloseToTray(bool enabled) async {
  if (!_desktop) return;
  if (enabled) {
    await _ensureTray();
  }
  // Never hide a window if no working tray exists to bring it back.
  _closeToTray = enabled && _trayShown;
  try {
    await windowManager.setPreventClose(_closeToTray);
  } catch (_) {}
  if (!enabled && _trayShown) {
    trayManager.removeListener(_trayListener);
    try {
      await trayManager.destroy();
    } catch (_) {}
    _trayShown = false;
  }
}

Future<void> setMonitoring(
  bool running, {
  required bool runInBackground,
  required bool keepAwake,
}) {
  // A stop must wait for an in-flight permission prompt/start to finish;
  // otherwise it can observe _serviceRunning=false and leave a late start alive.
  final next = _monitoringUpdate.then(
    (_) => _applyMonitoring(
      running,
      runInBackground: runInBackground,
      keepAwake: keepAwake,
    ),
  );
  _monitoringUpdate = next.catchError((Object _) {});
  return next;
}

Future<void> _applyMonitoring(
  bool running, {
  required bool runInBackground,
  required bool keepAwake,
}) async {
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
    final active = _serviceRunning || await _isServiceRunning();
    if (running && !active) {
      try {
        await FlutterForegroundTask.requestNotificationPermission();
        if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
          await FlutterForegroundTask.requestIgnoreBatteryOptimization();
        }
        final res = await FlutterForegroundTask.startService(
          serviceTypes: [ForegroundServiceTypes.dataSync],
          notificationTitle: '西农教务助手',
          notificationText: _host?.statusLine ?? '监控运行中',
          notificationIcon: const NotificationIcon(
            metaDataName: 'cn.edu.nwafu.nwafu_bksxk.NOTIFICATION_ICON',
          ),
        );
        _serviceRunning = res is ServiceRequestSuccess;
      } catch (_) {
        _serviceRunning = false;
      }
    } else if (!running && active) {
      try {
        await FlutterForegroundTask.stopService();
      } catch (_) {}
      _serviceRunning = false;
    }
  } else if (Platform.isAndroid &&
      (_serviceRunning || await _isServiceRunning())) {
    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}
    _serviceRunning = false;
  }
  if (_trayShown) await _doUpdateStatus(_host?.statusLine ?? '');
}

Future<bool> _isServiceRunning() async {
  try {
    return await FlutterForegroundTask.isRunningService;
  } catch (_) {
    return _serviceRunning;
  }
}

Future<void> updateStatus(String text) {
  final next = _monitoringUpdate.then((_) => _doUpdateStatus(text));
  _monitoringUpdate = next.catchError((Object _) {});
  return next;
}

Future<void> _doUpdateStatus(String text) async {
  if (_trayShown) {
    try {
      await trayManager.setToolTip(text.isEmpty ? '西农教务助手' : '西农教务助手：$text');
    } catch (_) {}
  }
  if (_serviceRunning) {
    try {
      await FlutterForegroundTask.updateService(
        notificationTitle: '西农教务助手',
        notificationText: text,
      );
    } catch (_) {}
  }
}

Future<void> _ensureTray() async {
  if (_trayShown) return;
  try {
    if (Platform.isMacOS) {
      await trayManager.setIcon(
        'assets/icons/tray_template.png',
        isTemplate: true,
      );
    } else if (Platform.isWindows) {
      await trayManager.setIcon('assets/icons/tray.ico');
    } else {
      await trayManager.setIcon('assets/icons/tray_color.png');
    }
    await trayManager.setToolTip('西农教务助手');
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show', label: '打开窗口'),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: '退出'),
        ],
      ),
    );
    trayManager.addListener(_trayListener);
    _trayShown = true;
  } catch (_) {
    _trayShown = false;
  }
}

class _WindowCloser with WindowListener {
  Timer? _saveDebounce;

  @override
  void onWindowResized() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        if (await windowManager.isMaximized() ||
            await windowManager.isFullScreen()) {
          return;
        }
        final size = await windowManager.getSize();
        if (size.width >= _kMinWindowSize.width &&
            size.height >= _kMinWindowSize.height) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setDouble(_kWindowWidth, size.width);
          await prefs.setDouble(_kWindowHeight, size.height);
        }
      } catch (_) {}
    });
  }

  @override
  void onWindowClose() async {
    _saveDebounce?.cancel();
    try {
      if (_closeToTray && await windowManager.isPreventClose()) {
        await windowManager.hide();
      }
    } catch (_) {}
  }
}

class _TrayHandler with TrayListener {
  @override
  void onTrayIconMouseDown() {
    if (Platform.isWindows || Platform.isLinux) {
      _show();
    } else {
      try {
        trayManager.popUpContextMenu();
      } catch (_) {}
    }
  }

  @override
  void onTrayIconRightMouseDown() {
    try {
      trayManager.popUpContextMenu();
    } catch (_) {}
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        _show();
      case 'quit':
        _host?.quitApp();
        windowManager
            .setPreventClose(false)
            .then((_) => windowManager.destroy())
            .catchError((Object _) {});
    }
  }

  Future<void> _show() async {
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {}
    _host?.showApp();
  }
}
