import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Required by flutter_local_notifications on iOS to present/handle notifications.
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NeonLiveActivity") {
      LiveActivityBridge.register(messenger: registrar.messenger())
    }
    // Removes widget keys from the App Group. home_widget can't: it stores a
    // null as NSNull, which UserDefaults rejects by crashing the app.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NeonWidgetStore") {
      FlutterMethodChannel(name: "neon/widget_store", binaryMessenger: registrar.messenger())
        .setMethodCallHandler { call, result in
          guard call.method == "remove",
                let args = call.arguments as? [String: Any],
                let group = args["group"] as? String,
                let keys = args["keys"] as? [String] else {
            result(FlutterMethodNotImplemented)
            return
          }
          let defaults = UserDefaults(suiteName: group)
          keys.forEach { defaults?.removeObject(forKey: $0) }
          result(nil)
        }
    }
  }
}
