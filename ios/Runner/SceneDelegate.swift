import UIKit

/// UIScene kullanılmıyor (iOS 26.5 ProMotion VSync crash — flutter#187565).
/// AppDelegate klasik window lifecycle ile çalışır; bu sınıf bilinçli olarak boş.
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?
}
