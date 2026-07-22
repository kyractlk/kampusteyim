import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// KampüsteyimAPP — uygulama için gereken runtime izinleri.
class AppPermissions {
  AppPermissions._();

  /// İlk açılışta / login sonrası: bildirim + medya + kamera.
  static Future<void> requestStartupPermissions() async {
    if (kIsWeb) return;
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        await Permission.notification.request();
      }
      if (Platform.isAndroid) {
        // Android 13+ foto / video; eski sürümlerde storage
        await [
          Permission.photos,
          Permission.videos,
          Permission.camera,
          Permission.storage,
        ].request();
      } else if (Platform.isIOS) {
        await [
          Permission.photos,
          Permission.camera,
        ].request();
      }
    } catch (e) {
      debugPrint('[perms] startup: $e');
    }
  }

  /// Galeri / dosya seçmeden önce.
  static Future<bool> ensureMediaAccess() async {
    if (kIsWeb) return true;
    try {
      if (Platform.isAndroid) {
        final photos = await Permission.photos.request();
        final videos = await Permission.videos.request();
        final storage = await Permission.storage.request();
        return photos.isGranted ||
            photos.isLimited ||
            videos.isGranted ||
            storage.isGranted;
      }
      if (Platform.isIOS) {
        final photos = await Permission.photos.request();
        return photos.isGranted || photos.isLimited;
      }
    } catch (e) {
      debugPrint('[perms] media: $e');
    }
    return true;
  }

  /// Kamera çekimi öncesi.
  static Future<bool> ensureCameraAccess() async {
    if (kIsWeb) return true;
    try {
      final cam = await Permission.camera.request();
      return cam.isGranted;
    } catch (e) {
      debugPrint('[perms] camera: $e');
      return true;
    }
  }
}
