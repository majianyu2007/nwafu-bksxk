import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    // The layout's narrowest usable state is the phone-style bottom bar; below
    // this the course browser and dialogs start clipping.
    self.minSize = NSSize(width: 480, height: 600)
    // Remember the user's last window size/position across launches.
    self.setFrameAutosaveName("MainFlutterWindow")

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
