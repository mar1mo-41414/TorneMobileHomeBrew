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
    if let akeRegistrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "AkeSocketChannels")
    {
      AkeSocketHub.shared.register(messenger: akeRegistrar.messenger())
    }
    // Native wakelock channel (plan 35).
    if let wakelockRegistrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "WakelockChannels")
    {
      WakelockHub.shared.register(messenger: wakelockRegistrar.messenger())
    }
  }
}

/// Native wakelock channel (plan 35): flips
/// `UIApplication.isIdleTimerDisabled` and returns the value read
/// back immediately afterwards, so the Dart side can prove from
/// the debug log whether the setting actually stuck.
///
/// This replaces wakelock_plus: in the build-13 field test
/// (iPhone, LiveContainer) the device slept mid-playback although
/// every enable had reported success — the plugin never reads the
/// value back, so a request the platform ignored was
/// indistinguishable from one that worked. Method channel
/// handlers are delivered on the main thread, so touching
/// UIApplication here is safe.
final class WakelockHub {
  static let shared = WakelockHub()

  func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.markun.tmhb/wakelock", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "setKeepAwake":
        let args = call.arguments as? [String: Any] ?? [:]
        let keepAwake = args["keepAwake"] as? Bool ?? false
        UIApplication.shared.isIdleTimerDisabled = keepAwake
        result(UIApplication.shared.isIdleTimerDisabled)
      case "getKeepAwake":
        result(UIApplication.shared.isIdleTimerDisabled)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
