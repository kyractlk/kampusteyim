import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:flutter/foundation.dart';

import '../../models/models.dart';
import 'notification_models.dart';
import 'push_service.dart';

class NotificationProvider extends ChangeNotifier {
  final List<AppNotification> _items = [];
  String? _userId;

  List<AppNotification> get items => List.unmodifiable(_items);
  int get unreadCount => _items.where((n) => !n.read).length;

  /// [userId] AppUser.id olabilir; FCM token her zaman Auth UID dokümanına yazılır.
  Future<void> bindUser(String? userId, {AppUser? profile}) async {
    final authUid = fa.FirebaseAuth.instance.currentUser?.uid;
    final docId = (authUid != null && authUid.isNotEmpty) ? authUid : userId;
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
    final token = await PushService.instance.getToken();
    if (token != null) {
      await _saveToken(docId, token, profile: profile);
    } else {
      debugPrint('[push] bindUser: token yok — bildirim izni / Google Play Services?');
      // Profil alanlarını yine de senkronla
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
    }
    await refresh();
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
      debugPrint('[push] token saved → users/$docId');
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
