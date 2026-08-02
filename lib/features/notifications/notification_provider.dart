import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:flutter/foundation.dart';

import '../../models/models.dart';
import 'notification_models.dart';
import 'push_service.dart';

class NotificationProvider extends ChangeNotifier {
  final List<AppNotification> _items = [];
  String? _userId;
  bool _retrying = false;

  List<AppNotification> get items => List.unmodifiable(_items);
  int get unreadCount => _items.where((n) => !n.read).length;

  /// [userId] tercihen Firebase Auth UID; FCM token Auth UID dokümanına yazılır.
  Future<void> bindUser(String? userId, {AppUser? profile}) async {
    final authUid = fa.FirebaseAuth.instance.currentUser?.uid;
    final docId = (authUid != null && authUid.isNotEmpty) ? authUid : userId;
    if (docId == _userId && docId != null) {
      // Aynı kullanıcı — push’u tekrar spam’leme.
      return;
    }
    _userId = docId;
    _items.clear();
    if (docId == null) {
      PushService.instance.onTokenRefresh = null;
      notifyListeners();
      return;
    }
    await PushService.instance.init();
    PushService.instance.onTokenRefresh = (token) async {
      await _saveToken(docId, token, profile: profile);
    };

    // İzin yoksa (web/iOS) token deneme + retry yok.
    if (!await PushService.instance.canRequestToken()) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(docId).set({
          'updatedAt': DateTime.now().toIso8601String(),
          if (profile != null) ...{
            'email': profile.email,
            'firstName': profile.firstName,
            'lastName': profile.lastName,
            'fullName': profile.fullName,
            'role': profile.role.name,
            'studentNo': profile.studentNo,
            'notificationPrefs': profile.notificationPrefs.toJson(),
            'stableId': profile.id,
          },
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('[push] bindUser profile sync: $e');
      }
      await refresh();
      return;
    }

    final token = await PushService.instance.getToken();
    if (token != null) {
      await _saveToken(docId, token, profile: profile);
    } else if (!kIsWeb) {
      // Yalnızca native’de APNs gecikmesi için retry.
      unawaited(_retryToken(docId, profile: profile));
    }
    await refresh();
  }

  /// iOS APNs gecikmesi için tekrarlı FCM token denemesi.
  Future<void> _retryToken(String docId, {AppUser? profile}) async {
    if (_retrying) return;
    _retrying = true;
    try {
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration(seconds: 2 + i));
        if (_userId != docId) return;
        if (!await PushService.instance.canRequestToken()) return;
        final token = await PushService.instance.getToken();
        if (token != null) {
          await _saveToken(docId, token, profile: profile);
          if (kDebugMode) {
            debugPrint('[push] retryToken ok (attempt ${i + 1})');
          }
          return;
        }
      }
      if (kDebugMode) {
        debugPrint('[push] retryToken: token alınamadı');
      }
    } finally {
      _retrying = false;
    }
  }

  Future<void> _saveToken(
    String docId,
    String token, {
    AppUser? profile,
  }) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(docId).set({
        'fcmTokens': FieldValue.arrayUnion([token]),
        'updatedAt': DateTime.now().toIso8601String(),
        'lastFcmAt': DateTime.now().toIso8601String(),
        if (profile != null) ...{
          'email': profile.email,
          'firstName': profile.firstName,
          'lastName': profile.lastName,
          'fullName': profile.fullName,
          'role': profile.role.name,
          'studentNo': profile.studentNo,
          'notificationPrefs': profile.notificationPrefs.toJson(),
          'stableId': profile.id,
        },
      }, SetOptions(merge: true));
      if (kDebugMode) {
        debugPrint('[push] token saved → users/$docId');
      }
    } catch (e) {
      debugPrint('[push] token save failed: $e');
    }
  }

  Future<void> refresh() async {
    if (_userId == null) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(_userId)
          .collection('notifications')
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();
      _items
        ..clear()
        ..addAll(snap.docs.map((d) => AppNotification.fromJson(d.id, d.data())));
    } catch (_) {
      if (_items.isEmpty) {
        _items.addAll([
          AppNotification(
            id: 'n1',
            title: 'Hoş geldin',
            body: 'KampüsteyimAPP bildirimleri aktif.',
            emoji: '🚀',
            type: 'community',
            createdAt: DateTime.now(),
          ),
        ]);
      }
    }
    notifyListeners();
  }

  Future<void> markAllRead() async {
    for (var i = 0; i < _items.length; i++) {
      _items[i] = _items[i].copyWith(read: true);
    }
    notifyListeners();
    if (_userId == null) return;
    try {
      final batch = FirebaseFirestore.instance.batch();
      final col = FirebaseFirestore.instance
          .collection('users')
          .doc(_userId)
          .collection('notifications');
      final snap = await col.where('read', isEqualTo: false).get();
      for (final d in snap.docs) {
        batch.update(d.reference, {'read': true});
      }
      await batch.commit();
    } catch (_) {}
  }

  Future<void> markRead(String id) async {
    final i = _items.indexWhere((n) => n.id == id);
    if (i < 0) return;
    _items[i] = _items[i].copyWith(read: true);
    notifyListeners();
    if (_userId == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_userId)
          .collection('notifications')
          .doc(id)
          .set({'read': true}, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> pushSocial({
    required String toUserId,
    required String title,
    required String body,
    required String emoji,
    required String type,
    String? actorId,
    String? targetId,
    bool personalize = false,
  }) async {
    if (toUserId == _userId) {
      _items.insert(
        0,
        AppNotification(
          id: 'local_${DateTime.now().millisecondsSinceEpoch}',
          title: title,
          body: body,
          emoji: emoji,
          type: type,
          createdAt: DateTime.now(),
          actorId: actorId,
          targetId: targetId,
        ),
      );
      notifyListeners();
    }
    await PushService.instance.dispatch(
      toUserId: toUserId,
      title: title,
      body: body,
      emoji: emoji,
      type: type,
      actorId: actorId,
      targetId: targetId,
      personalize: personalize,
    );
  }

  @override
  void dispose() {
    PushService.instance.onTokenRefresh = null;
    super.dispose();
  }
}
