import Flutter
import UIKit
import UserNotifications
import FirebaseCore
import FirebaseMessaging

/// iOS 26.5 + ProMotion App Store review crash (Guideline 2.1):
/// `VSyncClient` / `createTouchRateCorrectionVSyncClientIfNeeded`
/// (flutter#187565 / #190030).
///
/// Strateji:
/// 1) VSyncCrashGuard.m — +load ile touch-rate VSync no-op (en erken)
/// 2) Explicit FlutterEngine (AppFlutterHost) — shell VC’den önce hazır
/// 3) UIScene + SceneDelegate — window’u storyboard/implicit engine’siz kur
/// 4) AppDelegate window oluşturmaz (UIWindowScene sahipliği SceneDelegate’de)
@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Plist yoksa FirebaseApp.configure() NSException atıp uygulamayı öldürür;
    // Dart tarafı DefaultFirebaseOptions ile zaten init ediyor.
    if FirebaseApp.app() == nil,
      Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
      FirebaseApp.configure()
    } else if FirebaseApp.app() == nil {
      NSLog("[KampüsteyimAPP] GoogleService-Info.plist bundle’da yok — native Firebase atlandı")
    }

    AppFlutterHost.prepare()

    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }
    application.registerForRemoteNotifications()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    if FirebaseApp.app() != nil {
      Messaging.messaging().apnsToken = deviceToken
    }
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
