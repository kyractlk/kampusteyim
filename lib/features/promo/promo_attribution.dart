import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// QR tanıtım kartından gelen profil ziyareti — tarama + takip attribution.
class PromoAttribution {
  PromoAttribution._();

  static const _trackUrl =
      'https://europe-west1-ayskampuss.cloudfunctions.net/trackPromoScan';
  static const _kUser = 'promo_attr_user';
  static const _kIds = 'promo_attr_ids';
  static const _kAt = 'promo_attr_at';

  static String? _username;
  static final Set<String> _ids = <String>{};
  static DateTime? _at;
  static bool _loaded = false;
  static final Set<String> _scanned = <String>{};

  static String _norm(String? raw) {
    return (raw ?? '').trim().replaceFirst(RegExp(r'^@'), '').toLowerCase();
  }

  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final atMs = prefs.getInt(_kAt);
      if (atMs == null) return;
      final at = DateTime.fromMillisecondsSinceEpoch(atMs);
      if (DateTime.now().difference(at) > const Duration(hours: 24)) {
        await prefs.remove(_kUser);
        await prefs.remove(_kIds);
        await prefs.remove(_kAt);
        return;
      }
      _username = prefs.getString(_kUser);
      _ids.addAll(prefs.getStringList(_kIds) ?? const []);
      _at = at;
    } catch (e) {
      debugPrint('[promo] attr load: $e');
    }
  }

  static Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_username != null) await prefs.setString(_kUser, _username!);
      await prefs.setStringList(_kIds, _ids.toList());
      if (_at != null) {
        await prefs.setInt(_kAt, _at!.millisecondsSinceEpoch);
      }
    } catch (e) {
      debugPrint('[promo] attr save: $e');
    }
  }

  static void mark(
    String username, {
    String? userId,
    bool countScan = true,
  }) {
    final u = _norm(username);
    if (u.isEmpty && (userId == null || userId.trim().isEmpty)) return;
    if (u.isNotEmpty) {
      _username = u;
      _ids.add(u);
    }
    final id = userId?.trim() ?? '';
    if (id.isNotEmpty) _ids.add(id);
    _at = DateTime.now();
    unawaited(_persist());
    if (countScan && u.isNotEmpty) unawaited(trackScan(u));
  }

  static Future<void> trackScan(String username) async {
    final u = _norm(username);
    if (u.isEmpty || !_scanned.add(u)) return;
    final plat = defaultTargetPlatform == TargetPlatform.iOS
        ? 'ios'
        : defaultTargetPlatform == TargetPlatform.android
            ? 'android'
            : 'other';
    final uri = Uri.parse(_trackUrl).replace(queryParameters: {
      'redirect': '0',
      'source': 'promo_card',
      'username': u,
      'platform': plat,
    });
    try {
      await http.get(uri).timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('[promo] scan: $e');
    }
  }

  static bool matches(String? username, {String? userId}) {
    if (_at == null) return false;
    if (DateTime.now().difference(_at!) > const Duration(hours: 24)) {
      return false;
    }
    final u = _norm(username);
    if (u.isNotEmpty && (_username == u || _ids.contains(u))) return true;
    final id = userId?.trim() ?? '';
    return id.isNotEmpty && _ids.contains(id);
  }
}
