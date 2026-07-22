import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Oturum meta verisi — **asla** idToken / refreshToken saklamaz.
///
/// Güvenlik modeli:
/// - Kimlik doğrulama: yalnızca Firebase Auth kalıcılığı (IndexedDB / Keychain)
/// - SharedPreferences: uid, e-posta, oturum parmak izi (hash), başlangıç zamanı
/// - Token’lar cihazda Firebase SDK içinde kalır; uygulama kodu okumaz/yazmaz
class SecureSession {
  SecureSession._();

  static const _kUid = 'mt_sess_uid';
  static const _kEmail = 'mt_sess_email';
  static const _kStarted = 'mt_sess_started';
  static const _kFp = 'mt_sess_fp';
  static const _kNonce = 'mt_sess_nonce';

  /// Web’de LOCAL persistence (sayfa yenilemede oturum kalsın).
  static Future<void> ensureAuthPersistence() async {
    if (!kIsWeb) return;
    try {
      await fa.FirebaseAuth.instance.setPersistence(fa.Persistence.LOCAL);
    } catch (e) {
      debugPrint('[session] setPersistence: $e');
    }
  }

  /// Cihaz/oturum parmak izi — token içermez.
  static String _fingerprint(String uid) {
    final platform = kIsWeb ? 'web' : defaultTargetPlatform.name;
    final raw = '$uid|$platform|kampusteyim_v1';
    return sha256.convert(utf8.encode(raw)).toString().substring(0, 32);
  }

  static String _newNonce() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static Future<void> saveMeta({
    required String uid,
    required String email,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUid, uid);
    await prefs.setString(_kEmail, email);
    await prefs.setString(_kStarted, DateTime.now().toIso8601String());
    await prefs.setString(_kFp, _fingerprint(uid));
    final nonce = prefs.getString(_kNonce) ?? _newNonce();
    await prefs.setString(_kNonce, nonce);
  }

  static Future<Map<String, String>?> readMeta() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString(_kUid);
    if (uid == null || uid.isEmpty) return null;
    return {
      'uid': uid,
      'email': prefs.getString(_kEmail) ?? '',
      'started': prefs.getString(_kStarted) ?? '',
      'fp': prefs.getString(_kFp) ?? '',
      'nonce': prefs.getString(_kNonce) ?? '',
    };
  }

  /// Meta ile Firebase Auth uyumsuzsa veya fp bozuksa temizle.
  static Future<bool> isIntegrityOk(String authUid) async {
    final meta = await readMeta();
    if (meta == null) return true; // henüz yazılmamış
    if (meta['uid'] != authUid) return false;
    final expected = _fingerprint(authUid);
    return meta['fp'] == expected;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kUid);
    await prefs.remove(_kEmail);
    await prefs.remove(_kStarted);
    await prefs.remove(_kFp);
    await prefs.remove(_kNonce);
  }

  /// Sessiz token yenileme — değeri uygulamaya/log’a yazılmaz.
  static Future<bool> silentRefresh() async {
    final u = fa.FirebaseAuth.instance.currentUser;
    if (u == null) return false;
    try {
      await u.getIdToken(true);
      return true;
    } catch (e) {
      debugPrint('[session] refresh failed');
      return false;
    }
  }
}
