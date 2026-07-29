import Flutter
import UIKit

/// UIScene lifecycle — iOS 26 review cihazları her zaman scene açar.
/// FlutterSceneDelegate.super KULLANILMAZ (implicit/storyboard VC yaratarak
/// ProMotion VSync crash’ini yeniden tetikler — flutter#183900 / #190030).
/// Explicit engine + FlutterSceneLifeCycleProvider.
class SceneDelegate: UIResponder, UIWindowSceneDelegate, FlutterSceneLifeCycleProvider {
  var window: UIWindow?

  private let flutterSceneLifeCycleDelegate = FlutterPluginSceneLifeCycleDelegate()

  var sceneLifeCycleDelegate: FlutterPluginSceneLifeCycleDelegate {
    flutterSceneLifeCycleDelegate
  }

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    guard let windowScene = scene as? UIWindowScene else { return }

    AppFlutterHost.prepare()
    let engine = AppFlutterHost.engine
    flutterSceneLifeCycleDelegate.registerSceneLifeCycle(with: engine)

    let window = UIWindow(windowScene: windowScene)
    window.rootViewController = FlutterViewController(
      engine: engine,
      nibName: nil,
      bundle: nil
    )
    self.window = window
    window.makeKeyAndVisible()

    flutterSceneLifeCycleDelegate.scene(
      scene,
      willConnectTo: session,
      options: connectionOptions
    )
  }

  func sceneDidDisconnect(_ scene: UIScene) {
    flutterSceneLifeCycleDelegate.sceneDidDisconnect(scene)
  }

  func sceneWillEnterForeground(_ scene: UIScene) {
    flutterSceneLifeCycleDelegate.sceneWillEnterForeground(scene)
  }

  func sceneDidBecomeActive(_ scene: UIScene) {
    flutterSceneLifeCycleDelegate.sceneDidBecomeActive(scene)
  }

  func sceneWillResignActive(_ scene: UIScene) {
    flutterSceneLifeCycleDelegate.sceneWillResignActive(scene)
  }

  func sceneDidEnterBackground(_ scene: UIScene) {
    flutterSceneLifeCycleDelegate.sceneDidEnterBackground(scene)
  }

  func scene(
    _ scene: UIScene,
    openURLContexts URLContexts: Set<UIOpenURLContext>
  ) {
    flutterSceneLifeCycleDelegate.scene(scene, openURLContexts: URLContexts)
  }

  func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    flutterSceneLifeCycleDelegate.scene(scene, continue: userActivity)
  }

  func windowScene(
    _ windowScene: UIWindowScene,
    performActionFor shortcutItem: UIApplicationShortcutItem,
    completionHandler: @escaping (Bool) -> Void
  ) {
    flutterSceneLifeCycleDelegate.windowScene(
      windowScene,
      performActionFor: shortcutItem,
      completionHandler: completionHandler
    )
  }
}
