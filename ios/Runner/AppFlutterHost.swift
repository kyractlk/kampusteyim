import Flutter
import Foundation

/// Tek paylaşılan explicit FlutterEngine.
/// Implicit / storyboard engine yolu ProMotion + iOS 26’da VSyncClient SIGSEGV
/// üretir (flutter#190030). Engine, SceneDelegate VC’den önce `run` edilmeli.
enum AppFlutterHost {
  static let engine = FlutterEngine(name: "kampusteyim_engine")

  private static var didPrepare = false

  static func prepare() {
    guard !didPrepare else { return }
    engine.run()
    GeneratedPluginRegistrant.register(with: engine)
    didPrepare = true
  }
}
