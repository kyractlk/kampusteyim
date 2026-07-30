import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_update_models.dart';

/// Açılışta mağaza sürümünü kontrol eder; soft / force güncelleme üretir.
class AppUpdateProvider extends ChangeNotifier {
  AppUpdateProvider() {
    if (!kIsWeb) {
      unawaited(check());
    }
  }

  static const _gateUrl =
      'https://europe-west1-ayskampuss.cloudfunctions.net/getAppUpdateGate';
  static const _dismissKey = 'mt_update_dismissed_store_version';

  AppUpdateGate gate = AppUpdateGate.empty;
  bool loading = false;
  bool softDismissed = false;
  String? localVersion;
  String? status;

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
      final platform = appUpdatePlatformLabel();
      final uri = Uri.parse(_gateUrl).replace(
        queryParameters: {
          'platform': platform,
          'currentVersion': info.version,
          if (refresh) 'refresh': '1',
        },
      );
      final res = await http
          .get(uri)
          .timeout(const Duration(seconds: 12));
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
      softDismissed =
          dismissed.isNotEmpty && dismissed == gate.storeVersion;
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
      await prefs.setString(_dismissKey, gate.storeVersion);
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
