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

    // Native AKE socket channels (IP TTL 3, plan 28 / 47.5): the
    // nasne refuses AKE connections whose IP TTL exceeds 3, and
    // dart:io cannot set the TTL, so macOS uses the same native
    // socket as iOS.
    let akeRegistrar = flutterViewController.registrar(
      forPlugin: "AkeSocketChannels")
    AkeSocketHub.shared.register(messenger: akeRegistrar.messenger)

    super.awakeFromNib()
  }
}
