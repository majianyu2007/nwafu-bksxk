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
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "cn.edu.nwafu.nwafuBksxk.eduRefresh",
      earliestBeginInSeconds: nil
    )
    WorkmanagerPlugin.registerLaunchHandlers()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
