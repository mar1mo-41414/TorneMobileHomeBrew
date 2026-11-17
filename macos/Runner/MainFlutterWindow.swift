import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    // Desktop is a large-screen target (plan 37): open at a size
    // where the rail + two-pane layout is in effect from the
    // start, centred on the screen, instead of the template's
    // 800x600.
    self.setContentSize(NSSize(width: 1280, height: 800))
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
