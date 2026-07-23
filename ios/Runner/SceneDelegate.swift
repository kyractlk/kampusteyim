import Flutter
import UIKit

/// Explicit FlutterEngine — viewDidLoad öncesi engine hazır olur.
/// Implicit / storyboard yolu ProMotion + iOS 26.5’te VSyncClient crash’ine yol açıyor.
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?
  private let flutterEngine = FlutterEngine(name: "kampusteyim_engine")

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    guard let windowScene = scene as? UIWindowScene else { return }

    flutterEngine.run()
    GeneratedPluginRegistrant.register(with: flutterEngine)

    let flutterViewController = FlutterViewController(
      engine: flutterEngine,
      nibName: nil,
      bundle: nil
    )

    let window = UIWindow(windowScene: windowScene)
    window.rootViewController = flutterViewController
    window.makeKeyAndVisible()
    self.window = window
  }
}
