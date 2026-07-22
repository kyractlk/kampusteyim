import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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
        final link = data['link'] ?? '';
        final targetId = data['targetId'] ?? '';
        final payload = link.isNotEmpty
            ? link
            : (targetId.isNotEmpty ? '/post/$targetId' : '');
        showLocal(
          title: title,
          body: body,
          channelId: isAdmin ? 'mt_mobil_admin' : 'mt_mobil_social',
          payload: payload,
        );
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
    if (link.isNotEmpty) {
      onNotificationTap?.call(link);
    } else if (targetId.isNotEmpty) {
      onNotificationTap?.call('/post/$targetId');
    }
  }

  Future<bool> _pushAllowed() async {
    final s = await _messaging.getNotificationSettings();
    return s.authorizationStatus == AuthorizationStatus.authorized ||
        s.authorizationStatus == AuthorizationStatus.provisional;
  }

  /// Android’de token izin olmadan da alınır; iOS/Web’de izin gerekir.
  Future<String?> getToken() async {
    try {
      final isApple = !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.macOS);
      if (kIsWeb || isApple) {
        if (!await _pushAllowed()) {
          debugPrint('[push] getToken blocked — permission');
          return null;
        }
      }
      if (isApple) {
        String? apns;
        for (var i = 0; i < 8; i++) {
          apns = await _messaging.getAPNSToken();
          if (apns != null) break;
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }
        if (apns == null) {
          debugPrint('[push] APNs token henüz yok');
          return null;
        }
      }
      final token = await _messaging.getToken();
      if (token == null) {
        debugPrint('[push] getToken null');
      } else {
        debugPrint('[push] token ok ${token.substring(0, 12)}…');
      }
      return token;
    } catch (e) {
      final msg = '$e';
      if (msg.contains('permission-blocked') ||
          msg.contains('permission-denied') ||
          msg.contains('messaging/permission-blocked')) {
        debugPrint('[push] getToken permission: $e');
        return null;
      }
      debugPrint('[push] getToken: $e');
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
        'personalize': personalize,
      });
    } catch (e) {
      debugPrint('[push] dispatch fallback local: $e');
      await showLocal(title: '$emoji $title', body: body);
    }
  }
}
