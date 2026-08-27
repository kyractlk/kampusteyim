import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../core/storage/media_warm_helper.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Arka plan — sistem tray / APNs gösterir
}

class PushService {
  PushService._();
  static final instance = PushService._();

  final _messaging = FirebaseMessaging.instance;
  final _local = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  void Function(String token)? onTokenRefresh;
  /// Deep link / rota (örn. /post/xxx)
  void Function(String routeOrLink)? onNotificationTap;

  Future<void> init() async {
    if (_ready) return;
    try {
      if (!kIsWeb) {
        FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      }

      if (!kIsWeb) {
        const androidInit =
            AndroidInitializationSettings('@drawable/ic_notification_ays');
        const iosInit = DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
          requestCriticalPermission: false,
          defaultPresentAlert: true,
          defaultPresentBadge: true,
          defaultPresentSound: true,
        );
        await _local.initialize(
          settings: const InitializationSettings(
            android: androidInit,
            iOS: iosInit,
          ),
          onDidReceiveNotificationResponse: (resp) {
            final payload = resp.payload;
            if (payload != null && payload.isNotEmpty) {
              onNotificationTap?.call(payload);
            }
          },
        );

        final androidPlugin = _local.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        await androidPlugin?.createNotificationChannel(
          const AndroidNotificationChannel(
            'mt_mobil_social',
            'Sosyal & Kampüs',
            description: 'Beğeni, yorum, takip, ilan, admin duyuru',
            importance: Importance.high,
          ),
        );
        await androidPlugin?.createNotificationChannel(
          const AndroidNotificationChannel(
            'mt_mobil_admin',
            'Admin Duyuruları',
            description: 'Platform admin push bildirimleri',
            importance: Importance.max,
          ),
        );
        // Android 13+ bildirim izni
        await androidPlugin?.requestNotificationsPermission();
      }

      // Her platformda izin iste (Android FCM token için zorunlu değil ama gösterim için şart)
      try {
        final settings = await _messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          announcement: true,
          carPlay: false,
          criticalAlert: false,
          provisional: false,
        );
        debugPrint('[push] permission: ${settings.authorizationStatus}');
      } catch (e) {
        debugPrint('[push] requestPermission: $e');
      }

      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      FirebaseMessaging.onMessage.listen((msg) {
        final n = msg.notification;
        final data = msg.data;
        final title = n?.title ?? data['title'] ?? 'KampüsteyimAPP';
        final body = n?.body ?? data['body'] ?? '';
        if (body.isEmpty && title == 'KampüsteyimAPP') return;
        final isAdmin = data['type'] == 'admin_broadcast';
        final link = '${data['link'] ?? ''}';
        final targetId = '${data['targetId'] ?? ''}';
        final type = '${data['type'] ?? ''}';
        final payload = _payloadFor(
          link: link,
          targetId: targetId,
          type: type,
          title: '$title',
          body: '$body',
          actorId: '${data['actorId'] ?? ''}',
        );
        showLocal(
          title: title,
          body: body,
          channelId: isAdmin ? 'mt_mobil_admin' : 'mt_mobil_social',
          payload: payload,
        );
        // Hikâye / reels push'u → arka planda medyayı hemen ısıt.
        if (type.contains('story') ||
            type.contains('reel') ||
            type == 'promo' ||
            type == 'activity') {
          unawaited(MediaWarmHelper.instance.kick(reason: 'fcm:$type'));
        }
      });

      FirebaseMessaging.onMessageOpenedApp.listen((msg) {
        _handleMessageTap(msg.data);
      });
      unawaited(_messaging.getInitialMessage().then((msg) {
        if (msg != null) _handleMessageTap(msg.data);
      }));

      _messaging.onTokenRefresh.listen((token) {
        debugPrint('[push] token refresh: ${token.substring(0, 12)}…');
        onTokenRefresh?.call(token);
      });

      _ready = true;
    } catch (e, st) {
      debugPrint('[push] init failed: $e\n$st');
      _ready = true;
    }
  }

  void _handleMessageTap(Map<String, dynamic> data) {
    final link = '${data['link'] ?? ''}';
    final targetId = '${data['targetId'] ?? ''}';
    final type = '${data['type'] ?? ''}';
    final payload = _payloadFor(
      link: link,
      targetId: targetId,
      type: type,
      title: '${data['title'] ?? ''}',
      body: '${data['body'] ?? ''}',
      actorId: '${data['actorId'] ?? ''}',
    );
    if (payload.isNotEmpty) {
      onNotificationTap?.call(payload);
    }
  }

  String _payloadFor({
    required String link,
    required String targetId,
    required String type,
    String title = '',
    String body = '',
    String actorId = '',
  }) {
    if (link.trim().isNotEmpty) return link.trim();
    final path = _pathForTarget(
      type: type,
      targetId: targetId,
      title: title,
      body: body,
      actorId: actorId,
    );
    return path ?? '';
  }

  /// type + target → uygulama içi path (CF ile aynı mantık).
  static String? _pathForTarget({
    required String type,
    required String targetId,
    String title = '',
    String body = '',
    String actorId = '',
  }) {
    final tid = targetId.trim();
    final t = type.toLowerCase().trim();
    final blob = '$title $body'.toLowerCase();
    final aid = actorId.trim();

    if (t == 'reel' || t.startsWith('reel_')) {
      if (tid.isEmpty) return '/reels';
      return '/reels?id=${Uri.encodeComponent(tid)}';
    }
    if (t == 'follow' || t == 'follow_request' || t == 'follow_accepted') {
      final u = aid.isNotEmpty ? aid : tid;
      if (u.isEmpty) return null;
      return '/user/${Uri.encodeComponent(u)}';
    }
    if (t == 'story' || t == 'story_like') {
      final u = aid.isNotEmpty ? aid : tid;
      if (u.isEmpty) return null;
      return '/stories/view/${Uri.encodeComponent(u)}';
    }
    if (t == 'event' || (tid.isNotEmpty && tid.startsWith('e_'))) {
      if (tid.isEmpty) return '/events';
      return '/event/${Uri.encodeComponent(tid)}';
    }
    if (t == 'announcement' ||
        tid.startsWith('a_') ||
        tid.startsWith('ann_')) {
      if (tid.isEmpty) return '/announcements';
      return '/announcement/${Uri.encodeComponent(tid)}';
    }
    if (t == 'community') {
      if (tid.isEmpty) return null;
      if (blob.contains('duyuru')) {
        return '/announcement/${Uri.encodeComponent(tid)}';
      }
      return '/event/${Uri.encodeComponent(tid)}';
    }
    if (t == 'job') {
      if (tid.isEmpty) return '/staj-ai';
      final postId = tid.startsWith('job_') ? tid : 'job_$tid';
      return '/post/${Uri.encodeComponent(postId)}';
    }
    if (t == 'application' || t == 'offer') {
      if (tid.isEmpty) return '/firma';
      return '/firma/job/${Uri.encodeComponent(tid)}';
    }
    if (blob.contains('hikâye') || blob.contains('hikaye')) {
      final u = aid.isNotEmpty ? aid : tid;
      if (u.isNotEmpty) return '/stories/view/${Uri.encodeComponent(u)}';
    }
    if (tid.isEmpty) return null;
    return '/post/${Uri.encodeComponent(tid)}';
  }

  bool _loggedPermissionBlock = false;

  Future<bool> _pushAllowed() async {
    final s = await _messaging.getNotificationSettings();
    return s.authorizationStatus == AuthorizationStatus.authorized ||
        s.authorizationStatus == AuthorizationStatus.provisional;
  }

  /// Token denemeye değer mi? (web/iOS izin yoksa false)
  Future<bool> canRequestToken() async {
    final isApple = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);
    if (!(kIsWeb || isApple)) return true;
    if (!await _pushAllowed()) {
      if (kDebugMode && !_loggedPermissionBlock) {
        _loggedPermissionBlock = true;
        debugPrint('[push] bildirim izni yok — token alınmayacak');
      }
      return false;
    }
    return true;
  }

  /// Android’de token izin olmadan da alınır; iOS/Web’de izin gerekir.
  Future<String?> getToken() async {
    try {
      final isApple = !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.macOS);
      if (kIsWeb || isApple) {
        if (!await canRequestToken()) {
          return null;
        }
      }
      if (isApple) {
        // APNs token bazen 10–20 sn gecikir; kısa denemede vazgeçme.
        String? apns;
        for (var i = 0; i < 25; i++) {
          apns = await _messaging.getAPNSToken();
          if (apns != null) break;
          await Future<void>.delayed(
            Duration(milliseconds: i < 10 ? 500 : 800),
          );
        }
        if (apns == null) {
          if (kDebugMode) {
            debugPrint('[push] APNs token henüz yok');
          }
          return null;
        }
      }
      final token = await _messaging.getToken();
      if (token != null && kDebugMode) {
        debugPrint('[push] token ok ${token.substring(0, 12)}…');
      }
      return token;
    } catch (e) {
      final msg = '$e';
      if (msg.contains('permission-blocked') ||
          msg.contains('permission-denied') ||
          msg.contains('messaging/permission-blocked')) {
        _loggedPermissionBlock = true;
        return null;
      }
      if (kDebugMode) {
        debugPrint('[push] getToken: $e');
      }
      return null;
    }
  }

  Future<void> showLocal({
    required String title,
    required String body,
    String channelId = 'mt_mobil_social',
    String? payload,
  }) async {
    if (kIsWeb) return;
    final android = AndroidNotificationDetails(
      channelId,
      channelId == 'mt_mobil_admin' ? 'Admin Duyuruları' : 'Sosyal & Kampüs',
      channelDescription: 'KampüsteyimAPP bildirimleri',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_notification_ays',
      color: const Color(0xFF33C5D1),
    );
    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.active,
    );
    await _local.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(android: android, iOS: ios),
      payload: payload,
    );
  }

  Future<void> dispatch({
    required String toUserId,
    required String title,
    required String body,
    required String emoji,
    required String type,
    String? actorId,
    String? targetId,
    String? linkPath,
    bool personalize = false,
  }) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('dispatchPush');
      await callable.call({
        'toUserId': toUserId,
        'title': '$emoji $title',
        'body': body,
        'emoji': emoji,
        'type': type,
        'actorId': actorId,
        'targetId': targetId,
        'linkPath': linkPath,
        'personalize': personalize,
      });
    } catch (e) {
      // Çevrimiçi değilken / CF hata verince yerel bildirim ASLA gösterme:
      // aksi halde beğeni/takip yapan kişi kendi telefonunda “X seni takip etti”
      // gibi bildirim görür (alıcıya gitmesi gereken mesaj).
      debugPrint('[push] dispatch skipped (offline/error): $e');
    }
  }
}
