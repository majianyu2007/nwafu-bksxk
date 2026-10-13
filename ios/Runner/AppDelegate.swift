import Flutter
import UIKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // The background timetable refresh runs in a headless engine that needs
    // the same plugins (preferences, secure storage, notifications, network).
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    // BGTaskScheduler only accepts launch handlers before launch finishes and
    // throws (killing the app) otherwise. With the UIScene lifecycle plugins
    // register after that point, so the Dart-side registerPeriodicTask would
    // register too late; do it here, before returning.
    // The delay registered here is also what the plugin uses to re-submit
    // the request after every run, so pass the user's sync interval
    // (shared_preferences key `edu.sync.interval.v1`, default 12 h, clamped
    // to 1–24 h like `iosEarliestBegin` in background_sync_task_io.dart).
    // It is only an earliest-begin hint: iOS decides when the task runs.
    let saved = UserDefaults.standard.object(forKey: "flutter.edu.sync.interval.v1") as? Int
    let hours = min(max(saved ?? 12, 1), 24)
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "cn.edu.nwafu.nwafuBksxk.eduRefresh",
      earliestBeginInSeconds: NSNumber(value: hours * 3600)
    )
    WorkmanagerPlugin.registerLaunchHandlers()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
