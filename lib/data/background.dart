/// Keeps the app alive while a monitor is running, per platform:
///  - desktop (macOS / Windows / Linux): closing the window hides it to a
///    tray / menu-bar icon instead of quitting, and the display is kept awake;
///  - Android: a foreground service with a persistent notification so the
///    system does not kill the process while it polls;
///  - iOS: the screen is kept awake (iOS has no user-startable background
///    service; the monitor runs while the app is open);
///  - web: nothing (closing the tab ends the page).
///
/// The platform implementation is behind a conditional import so the desktop
/// and Android plugins (dart:io) never reach the web build.
library;

import 'background_stub.dart' if (dart.library.io) 'background_io.dart' as impl;

/// What the tray menu / notification tap should do.
abstract class BackgroundHost {
  /// Show the main window (tray click).
  void showApp();

  /// Quit for real (tray "退出").
  void quitApp();

  /// The label shown in the tray tooltip / service notification.
  String get statusLine;
}

class AppBackground {
  AppBackground._();
  static final AppBackground instance = AppBackground._();

  /// Call once before runApp (desktop window setup).
  Future<void> init() => impl.init();

  /// Wire the host after the shell mounts.
  void attach(BackgroundHost host) => impl.attach(host);

  /// Tell the platform whether any monitor is running; it turns the keep-alive
  /// measures on and off accordingly.
  Future<void> setMonitoring(bool running,
          {required bool runInBackground, required bool keepAwake}) =>
      impl.setMonitoring(running, runInBackground: runInBackground, keepAwake: keepAwake);

  /// Whether closing the window should hide it (desktop) rather than quit.
  Future<void> setCloseToTray(bool enabled) => impl.setCloseToTray(enabled);

  /// Refresh the tray tooltip / service notification text.
  Future<void> updateStatus(String text) => impl.updateStatus(text);

  bool get supportsTray => impl.supportsTray;
  bool get supportsForegroundService => impl.supportsForegroundService;
}
