import Flutter
import ObjectiveC
import UIKit
import UserNotifications
import FirebaseCore
import FirebaseMessaging

/// iOS 26.5 + ProMotion App Store review: Flutter engine SIGSEGV in
/// `-[VSyncClient initWithTaskRunner:]` via
/// `createTouchRateCorrectionVSyncClientIfNeeded` (flutter/flutter#187565).
///
/// Strateji:
/// 1) UIScene YOK — klasik AppDelegate lifecycle (race kaynağını kaldırır)
/// 2) Explicit FlutterEngine, VC’den önce run
/// 3) Touch-rate VSync client metodunu no-op swizzle (ProMotion null task runner)
@main
@objc class AppDelegate: FlutterAppDelegate {
  private let flutterEngine = FlutterEngine(name: "kampusteyim_engine")

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    Self.installTouchRateCorrectionNoOp()

    if FirebaseApp.app() == nil {
      FirebaseApp.configure()
    }

    flutterEngine.run()
    GeneratedPluginRegistrant.register(with: flutterEngine)

    let flutterVC = FlutterViewController(
      engine: flutterEngine,
      nibName: nil,
      bundle: nil
    )
    window = UIWindow(frame: UIScreen.main.bounds)
    window?.rootViewController = flutterVC
    window?.makeKeyAndVisible()

    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }
    application.registerForRemoteNotifications()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// ProMotion cihazlarda engine shell hazır olmadan VSyncClient oluşmasını engeller.
  private static func installTouchRateCorrectionNoOp() {
    let sel = NSSelectorFromString("createTouchRateCorrectionVSyncClientIfNeeded")
    guard
      let method = class_getInstanceMethod(FlutterViewController.self, sel)
    else {
      NSLog("[KampüsteyimAPP] touch-rate VSync selector missing — skip swizzle")
      return
    }
    let block: @convention(block) (AnyObject) -> Void = { _ in
      // intentionally empty
    }
    method_setImplementation(method, imp_implementationWithBlock(block))
    NSLog("[KampüsteyimAPP] touch-rate VSync client disabled (iOS 26.5 ProMotion workaround)")
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    // Custom FlutterEngine: APNs token’ı FCM’e elle bağla.
    Messaging.messaging().apnsToken = deviceToken
    let hex = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
    NSLog("[KampüsteyimAPP] APNs token ok (\(deviceToken.count) bytes) \(hex.prefix(16))…")
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    NSLog("[KampüsteyimAPP] APNs kayıt hatası: \(error.localizedDescription)")
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }
}
