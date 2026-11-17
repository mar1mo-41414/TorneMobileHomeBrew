import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Native AKE socket channels (IP TTL 3, plan 28).
    let akeRegistrar = engineBridge.pluginRegistry.registrar(forPlugin: "AkeSocketChannels")
    AkeSocketHub.shared.register(messenger: akeRegistrar.messenger)
  }
}
