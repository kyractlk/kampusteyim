import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/auth/secure_session.dart';
import '../../core/security/safe_text.dart';
import 'maintenance_models.dart';

/// Canlı bakım durumu + "haber et" aboneliği.
class MaintenanceProvider extends ChangeNotifier {
  MaintenanceProvider() {
    _bind();
  }

  static const _kEmail = 'mt_maint_notify_email';
  static const _kSession = 'mt_maint_subscribed_session';

  MaintenanceState state = MaintenanceState.empty;
  bool loading = true;
  bool subscribing = false;
  String? status;
  String? cachedEmail;
  bool alreadySubscribed = false;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;

  bool get blocksApp => state.isBlocking;

  void _bind() {
    unawaited(_loadLocal());
    try {
      _sub = FirebaseFirestore.instance
          .collection('app_config')
          .doc('maintenance')
          .snapshots()
          .listen(
        (snap) {
          state = MaintenanceState.fromMap(snap.data());
          loading = false;
          unawaited(_refreshSubscribedFlag());
          notifyListeners();
        },
        onError: (e) {
          debugPrint('[maint] listen: $e');
          loading = false;
          notifyListeners();
        },
      );
    } catch (e) {
      debugPrint('[maint] bind: $e');
      loading = false;
    }
  }

  Future<void> _loadLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var email = prefs.getString(_kEmail)?.trim() ?? '';
      if (email.isEmpty) {
        final meta = await SecureSession.readMeta();
        email = meta?['email']?.trim() ?? '';
      }
      cachedEmail = email.isEmpty ? null : email;
      await _refreshSubscribedFlag();
      notifyListeners();
    } catch (e) {
      debugPrint('[maint] local: $e');
    }
  }

  Future<void> _refreshSubscribedFlag() async {
    final prefs = await SharedPreferences.getInstance();
    final sid = prefs.getString(_kSession);
    alreadySubscribed =
        sid != null && sid.isNotEmpty && sid == (state.sessionId ?? '');
  }

  Future<void> rememberEmail(String email) async {
    final e = email.trim().toLowerCase();
    if (!e.contains('@')) return;
    cachedEmail = e;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kEmail, e);
    notifyListeners();
  }

  /// Bakım bitince haber ver — mobil cache / web e-posta.
  Future<bool> subscribeNotify({
    required String email,
    String? uid,
  }) async {
    final e = email.trim().toLowerCase();
    if (!SafeText.isValidEmail(e)) {
      status = 'Geçerli bir e-posta girin';
      notifyListeners();
      return false;
    }
    if (alreadySubscribed) {
      status = 'Zaten haber listesindesiniz';
      notifyListeners();
      return true;
    }

    subscribing = true;
    status = null;
    notifyListeners();

    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('subscribeMaintenanceNotify');
      await callable.call({
        'email': e,
        'platform': kIsWeb
            ? 'web'
            : defaultTargetPlatform == TargetPlatform.iOS
                ? 'ios'
                : 'android',
        if (uid != null && uid.isNotEmpty) 'uid': uid,
      });
      await rememberEmail(e);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kSession, state.sessionId ?? 'pending');
      alreadySubscribed = true;
      status = kIsWeb
          ? 'Tamam · bakım bitince e-posta göndereceğiz'
          : 'Tamam · bakım bitince bildirim göndereceğiz';
      subscribing = false;
      notifyListeners();
      return true;
    } catch (err) {
      debugPrint('[maint] subscribe: $err');
      status = 'Kayıt başarısız · tekrar deneyin';
      subscribing = false;
      notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
