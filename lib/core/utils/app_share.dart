import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/models.dart';
import '../constants/app_info.dart';

/// Harici paylaşım linkleri (web + APK aynı URL).
class AppShare {
  AppShare._();

  static String get baseUrl => AppInfo.webBaseUrl;

  static String post(String id) => '$baseUrl/post/${Uri.encodeComponent(id)}';

  /// Profil URL — mümkünse kullanıcı adı (`/user/aystech`).
  static String user(String idOrUsername) {
    final clean = idOrUsername.trim().replaceFirst(RegExp(r'^@'), '');
    return '$baseUrl/user/${Uri.encodeComponent(clean)}';
  }

  static String userOf(AppUser u) {
    final uname = u.username?.trim();
    if (uname != null && uname.isNotEmpty) {
      return user(uname.replaceFirst(RegExp(r'^@'), ''));
    }
    return user(u.id);
  }

  /// Paylaşım / navigasyon için tercih edilen profil anahtarı.
  static String userKey(AppUser u) {
    final uname = u.username?.trim();
    if (uname != null && uname.isNotEmpty) {
      return uname.replaceFirst(RegExp(r'^@'), '');
    }
    return u.id;
  }

  static String announcement(String id) =>
      '$baseUrl/announcement/${Uri.encodeComponent(id)}';
  static String event(String id) =>
      '$baseUrl/event/${Uri.encodeComponent(id)}';

  /// Web’de panoya kopyalar; native’de sistem paylaşımını dener.
  static Future<void> shareLink({
    required BuildContext context,
    required String url,
    String? subject,
    String? preview,
  }) async {
    final text = [
      if (preview != null && preview.trim().isNotEmpty) preview.trim(),
      url,
    ].join('\n\n');

    var copied = false;

    if (kIsWeb) {
      await Clipboard.setData(ClipboardData(text: url));
      copied = true;
    } else {
      try {
        await SharePlus.instance.share(
          ShareParams(
            text: text,
            subject: subject ?? AppInfo.appName,
          ),
        );
      } catch (e) {
        debugPrint('[share] $e');
        await Clipboard.setData(ClipboardData(text: url));
        copied = true;
      }
    }

    if (!context.mounted) return;
    if (copied) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bağlantı kopyalandı'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  static Future<void> sharePost({
    required BuildContext context,
    required String id,
    String? authorName,
    String? content,
  }) {
    // Twitter tarzı: gövdede link yok; paylaşınca link eklenir.
    return shareLink(
      context: context,
      url: post(id),
      subject: 'KampüsteyimAPP',
      preview: null,
    );
  }

  static Future<void> shareUser({
    required BuildContext context,
    required AppUser user,
  }) {
    return shareLink(
      context: context,
      url: userOf(user),
      subject: '${user.fullName} · KampüsteyimAPP',
      preview: '${user.fullName} (${user.handle})',
    );
  }
}
