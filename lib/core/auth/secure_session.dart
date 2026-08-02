import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tab_session_stub.dart'
    if (dart.library.html) 'tab_session_web.dart' as tab_session;

/// Oturum meta verisi — **asla** idToken / refreshToken saklamaz.
///
/// Güvenlik modeli:
/// - Kimlik: Firebase Auth (web’de **SESSION** = sekme izole; diğer sekmeler karışmaz)
/// - Web: sessionStorage’da sekme UID kilidi (SharedPreferences sekmeler arası
///   paylaşılsa bile yanlış hesaba yapışmaz)
/// - SharedPreferences: uid + e-posta + HMAC parmak izi + nonce
/// - Token’lar yalnızca Firebase SDK içinde kalır
class SecureSession {
  SecureSession._();

  static const _kUid = 'mt_sess_uid';
  static const _kEmail = 'mt_sess_email';
  static const _kStarted = 'mt_sess_started';
  static const _kFp = 'mt_sess_fp';
  static const _kNonce = 'mt_sess_nonce';
  static const _kVersion = 'mt_sess_v';
  static const _sessionVersion = '2';

  /// Web: SESSION — sekme/pencereye özel oturum (başka sekmede farklı hesap
  /// girmek bu sekmeyi ezmez). Yenilemede aynı sekmede kalır.
  static Future<void> ensureAuthPersistence() async {
    if (!kIsWeb) return;
    try {
      await fa.FirebaseAuth.instance.setPersistence(fa.Persistence.SESSION);
    } catch (e) {
      debugPrint('[session] setPersistence: $e');
    }
  }

  static String _fingerprint(String uid, String nonce) {
    final platform = kIsWeb ? 'web' : defaultTargetPlatform.name;
    final raw = '$uid|$platform|kampusteyim_v2|$nonce';
    return sha256.convert(utf8.encode(raw)).toString();
  }

  static String _newNonce() {
    final r = Random.secure();
    final bytes = List<int>.generate(24, (_) => r.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static Future<void> saveMeta({
    required String uid,
    required String email,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    // Her girişte yeni nonce — parmak izi yeniden üretilir.
    final nonce = _newNonce();
    await prefs.setString(_kUid, uid);
    await prefs.setString(_kEmail, email.trim().toLowerCase());
    await prefs.setString(_kStarted, DateTime.now().toIso8601String());
    await prefs.setString(_kNonce, nonce);
    await prefs.setString(_kFp, _fingerprint(uid, nonce));
    await prefs.setString(_kVersion, _sessionVersion);
    if (kIsWeb) tab_session.tabSetUid(uid);
  }

  static Future<Map<String, String>?> readMeta() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString(_kUid);
    if (uid == null || uid.isEmpty) return null;
    // Web: sekme kilidi varsa prefs’teki UID ile çakışmayı yakala.
    if (kIsWeb) {
      final tabUid = tab_session.tabGetUid();
      if (tabUid != null && tabUid.isNotEmpty && tabUid != uid) {
        // Başka sekme prefs’i ezmiş; bu sekmenin kilidine güven.
        return {
          'uid': tabUid,
          'email': '',
          'started': '',
          'fp': '',
          'nonce': '',
          'version': _sessionVersion,
          'tabOnly': '1',
        };
      }
    }
    return {
      'uid': uid,
      'email': prefs.getString(_kEmail) ?? '',
      'started': prefs.getString(_kStarted) ?? '',
      'fp': prefs.getString(_kFp) ?? '',
      'nonce': prefs.getString(_kNonce) ?? '',
      'version': prefs.getString(_kVersion) ?? '',
    };
  }

  static Future<String?> boundUid() async {
    if (kIsWeb) {
      final tabUid = tab_session.tabGetUid();
      if (tabUid != null && tabUid.isNotEmpty) return tabUid;
    }
    final m = await readMeta();
    return m?['uid'];
  }

  /// Meta yoksa `null` (henüz bağlanmadı). Uyumsuzsa `false`.
  static Future<bool?> checkIntegrity(String authUid) async {
    if (kIsWeb) {
      final tabUid = tab_session.tabGetUid();
      // Bu sekmede daha önce bağlanmış UID varsa Auth ile eşleşmeli.
      if (tabUid != null && tabUid.isNotEmpty && tabUid != authUid) {
        return false;
      }
    }
    final meta = await readMeta();
    if (meta == null) return null;
    // Yalnızca sekme kilidi varsa (prefs başka sekmeden) — Auth ↔ tab eşleşmesi yeter.
    if (meta['tabOnly'] == '1') {
      return meta['uid'] == authUid ? true : false;
    }
    if (meta['uid'] != authUid) return false;
    final nonce = meta['nonce'] ?? '';
    if (nonce.isEmpty) return false;
    final expected = _fingerprint(authUid, nonce);
    if (meta['fp'] != expected) return false;
    // Eski v1 oturumları bir kez yenilet.
    if (meta['version'] != _sessionVersion) return false;
    // Web’de sekme kilidi yoksa (ilk yükleme) Auth ile hizala.
    if (kIsWeb && (tab_session.tabGetUid() == null || tab_session.tabGetUid()!.isEmpty)) {
      tab_session.tabSetUid(authUid);
    }
    return true;
  }

  @Deprecated('Use checkIntegrity')
  static Future<bool> isIntegrityOk(String authUid) async {
    final r = await checkIntegrity(authUid);
    return r != false;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    final tabUid = kIsWeb ? tab_session.tabGetUid() : null;
    final prefsUid = prefs.getString(_kUid);
    // Web: prefs başka sekmeye aitse silme — sadece bu sekmenin kilidini temizle.
    if (kIsWeb &&
        tabUid != null &&
        prefsUid != null &&
        tabUid.isNotEmpty &&
        prefsUid != tabUid) {
      tab_session.tabClearUid();
      return;
    }
    await prefs.remove(_kUid);
    await prefs.remove(_kEmail);
    await prefs.remove(_kStarted);
    await prefs.remove(_kFp);
    await prefs.remove(_kNonce);
    await prefs.remove(_kVersion);
    if (kIsWeb) tab_session.tabClearUid();
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
