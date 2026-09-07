import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_update_models.dart';

/// Açılışta bu platformun mağaza sürümünü kontrol eder.
/// iOS 1.71 ile Android 1.1.0 asla birbirine kıyaslanmaz.
class AppUpdateProvider extends ChangeNotifier {
  AppUpdateProvider() {
    unawaited(check());
  }

  static const _gateUrl =
      'https://europe-west1-ayskampuss.cloudfunctions.net/getAppUpdateGate';
  static const _dismissKey = 'mt_update_dismissed_platform_store';

  AppUpdateGate gate = AppUpdateGate.empty;
  bool loading = false;
  bool softDismissed = false;
  String? localVersion;
  String? localBuild;
  String? status;
  String _platform = 'other';

  bool get blocksApp => gate.forceUpdate;
  bool get showSoftBanner =>
      gate.softUpdate && !gate.forceUpdate && !softDismissed;

  Future<void> check({bool refresh = false}) async {
    if (kIsWeb) return;
    loading = true;
    status = null;
    notifyListeners();
    try {
      final info = await PackageInfo.fromPlatform();
      localVersion = info.version;
      localBuild = info.buildNumber;
      _platform = appUpdatePlatformLabel();
      final uri = Uri.parse(_gateUrl).replace(
        queryParameters: {
          'platform': _platform,
          'currentVersion': info.version,
          'currentBuild': info.buildNumber,
          if (refresh) 'refresh': '1',
        },
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final map = jsonDecode(res.body);
        if (map is Map && map['ok'] == true) {
          gate = AppUpdateGate.fromJson(Map<String, dynamic>.from(map));
          await _loadDismissed();
        }
      }
    } catch (e) {
      debugPrint('[appUpdate] $e');
      status = 'Sürüm kontrolü yapılamadı';
    }
    loading = false;
    notifyListeners();
  }

  Future<void> _loadDismissed() async {
    if (!gate.softUpdate || gate.forceUpdate) {
      softDismissed = false;
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final dismissed = prefs.getString(_dismissKey) ?? '';
      softDismissed = dismissed == '$_platform:${gate.storeVersion}';
    } catch (_) {
      softDismissed = false;
    }
  }

  Future<void> dismissSoft() async {
    if (gate.forceUpdate) return;
    softDismissed = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_dismissKey, '$_platform:${gate.storeVersion}');
    } catch (_) {}
  }

  Future<bool> openStore() async {
    final raw = gate.storeUrl.trim();
    if (raw.isEmpty) return false;
    final uri = Uri.tryParse(raw);
    if (uri == null) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
