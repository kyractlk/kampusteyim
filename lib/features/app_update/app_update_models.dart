import 'package:flutter/foundation.dart';

/// Mağaza / admin sürüm kapısı sonucu.
class AppUpdateGate {
  const AppUpdateGate({
    required this.currentVersion,
    required this.minVersion,
    required this.storeVersion,
    required this.forceUpdate,
    required this.softUpdate,
    required this.title,
    required this.message,
    required this.storeUrl,
    this.iosStoreVersion = '',
    this.androidStoreVersion = '',
    this.appStoreUrl = '',
    this.playStoreUrl = '',
  });

  final String currentVersion;
  final String minVersion;
  final String storeVersion;
  final bool forceUpdate;
  final bool softUpdate;
  final String title;
  final String message;
  final String storeUrl;
  final String iosStoreVersion;
  final String androidStoreVersion;
  final String appStoreUrl;
  final String playStoreUrl;

  bool get updateRequired => forceUpdate || softUpdate;

  factory AppUpdateGate.fromJson(Map<String, dynamic> raw) {
    return AppUpdateGate(
      currentVersion: '${raw['currentVersion'] ?? ''}',
      minVersion: '${raw['minVersion'] ?? ''}',
      storeVersion: '${raw['storeVersion'] ?? ''}',
      forceUpdate: raw['forceUpdate'] == true,
      softUpdate: raw['softUpdate'] == true,
      title: '${raw['title'] ?? 'Güncelleme gerekli'}',
      message:
          '${raw['message'] ?? 'Yeni sürüm yayında. Lütfen mağazadan güncelleyin.'}',
      storeUrl: '${raw['storeUrl'] ?? ''}',
      iosStoreVersion: '${raw['iosStoreVersion'] ?? ''}',
      androidStoreVersion: '${raw['androidStoreVersion'] ?? ''}',
      appStoreUrl: '${raw['appStoreUrl'] ?? ''}',
      playStoreUrl: '${raw['playStoreUrl'] ?? ''}',
    );
  }

  static const empty = AppUpdateGate(
    currentVersion: '',
    minVersion: '',
    storeVersion: '',
    forceUpdate: false,
    softUpdate: false,
    title: 'Güncelleme gerekli',
    message: '',
    storeUrl: '',
  );
}

String appUpdatePlatformLabel() {
  if (kIsWeb) return 'web';
  return switch (defaultTargetPlatform) {
    TargetPlatform.iOS => 'ios',
    TargetPlatform.android => 'android',
    _ => 'other',
  };
}
