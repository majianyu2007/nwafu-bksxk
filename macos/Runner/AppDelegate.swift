import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationWillFinishLaunching(_ notification: Notification) {
    if let bundleIdentifier = Bundle.main.bundleIdentifier {
      let currentPID = ProcessInfo.processInfo.processIdentifier
      let existing = NSRunningApplication
        .runningApplications(withBundleIdentifier: bundleIdentifier)
        .first { $0.processIdentifier != currentPID && !$0.isTerminated }
      if let existing {
        existing.activate(options: [.activateAllWindows])
        NSApp.terminate(nil)
        return
      }
    }
    super.applicationWillFinishLaunching(notification)
  }

  override func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    if !flag {
      sender.windows.first?.makeKeyAndOrderFront(nil)
    }
    sender.activate()
    return true
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
