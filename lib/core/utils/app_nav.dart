import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../features/reels/reels_provider.dart';
import '../../models/models.dart';
import 'app_share.dart';

/// Detay sayfaları — web adres çubuğu /post/… olur.
///
/// Web’de [go] URL’yi günceller; mobilde [push] geri yığınını korur.
class AppNav {
  AppNav._();

  static String _norm(String loc) {
    final u = Uri.tryParse(loc) ?? Uri(path: loc);
    var path = u.path;
    if (path.isEmpty) path = '/';
    if (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return path;
  }

  static void open(BuildContext context, String location) {
    final target = _norm(location);
    final here = _norm(GoRouterState.of(context).uri.path);
    if (here == target) return;
    final router = GoRouter.of(context);
    if (kIsWeb) {
      router.go(location);
    } else {
      router.push(location);
    }
  }

  /// Geri: stack varsa pop, yoksa akışa dön.
  static void back(BuildContext context, {String fallback = '/home'}) {
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
    } else {
      router.go(fallback);
    }
  }

  static void openPost(BuildContext context, String id) =>
      open(context, '/post/${Uri.encodeComponent(id)}');

  static void openUser(BuildContext context, String idOrUsername) => open(
        context,
        '/user/${Uri.encodeComponent(idOrUsername.replaceFirst(RegExp(r'^@'), ''))}',
      );

  static void openUserProfile(BuildContext context, AppUser user) =>
      openUser(context, AppShare.userKey(user));

  static void openAnnouncement(BuildContext context, String id) =>
      open(context, '/announcement/${Uri.encodeComponent(id)}');

  static void openEvent(BuildContext context, String id) =>
      open(context, '/event/${Uri.encodeComponent(id)}');

  /// Reels sekmesine git; [reelId] varsa o klipe odaklan.
  static void openReel(BuildContext context, {String? reelId}) {
    final id = reelId?.trim();
    if (id != null && id.isNotEmpty) {
      context.read<ReelsProvider>().requestFocusReel(id);
    }
    GoRouter.of(context).go('/reels');
  }

  /// Push / inbox linkinden Reels aç (`/reels?id=…` veya tam URL).
  static bool tryOpenReelLink(BuildContext context, String raw) {
    final id = reelIdFromLink(raw);
    if (id == null && !_isReelsPath(raw)) return false;
    openReel(context, reelId: id);
    return true;
  }

  static bool _isReelsPath(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return false;
    try {
      final uri = Uri.parse(t.startsWith('http') ? t : 'app://x$t');
      final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      return segs.isNotEmpty && segs.first.toLowerCase() == 'reels';
    } catch (_) {
      return t.contains('/reels');
    }
  }

  static String? reelIdFromLink(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    try {
      final uri = Uri.parse(t.startsWith('http') || t.startsWith('/')
          ? (t.startsWith('/') ? 'app://local$t' : t)
          : t);
      final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segs.isEmpty || segs.first.toLowerCase() != 'reels') return null;
      final q = uri.queryParameters['id']?.trim();
      if (q != null && q.isNotEmpty) return q;
      if (segs.length >= 2 && segs[1].isNotEmpty) return segs[1];
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Ham URL / path → uygulama içi rota (post, event, duyuru, reels, profil…).
  static bool openDeepLink(BuildContext context, String raw) {
    final t = raw.trim();
    if (t.isEmpty) return false;

    if (tryOpenReelLink(context, t)) return true;

    Uri? uri;
    try {
      if (t.startsWith('http://') || t.startsWith('https://')) {
        uri = Uri.parse(t);
      } else if (t.startsWith('/')) {
        uri = Uri.parse('app://local$t');
      } else {
        uri = Uri.parse('app://local/$t');
      }
    } catch (_) {
      return false;
    }

    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segs.isEmpty) {
      GoRouter.of(context).go('/home');
      return true;
    }

    final head = segs.first.toLowerCase();
    final id = segs.length >= 2 ? segs[1] : null;

    switch (head) {
      case 'post':
        if (id != null && id.isNotEmpty) {
          openPost(context, id);
          return true;
        }
        break;
      case 'event':
      case 'events':
        if (id != null && id.isNotEmpty) {
          openEvent(context, id);
          return true;
        }
        GoRouter.of(context).go('/events');
        return true;
      case 'announcement':
      case 'announcements':
        if (id != null && id.isNotEmpty) {
          openAnnouncement(context, id);
          return true;
        }
        GoRouter.of(context).go('/announcements');
        return true;
      case 'user':
        if (id != null && id.isNotEmpty) {
          openUser(context, id);
          return true;
        }
        break;
      case 'stories':
        if (segs.length >= 3 && segs[1].toLowerCase() == 'view') {
          open(context, '/stories/view/${Uri.encodeComponent(segs[2])}');
          return true;
        }
        break;
      case 'firma':
        if (segs.length >= 3 && segs[1].toLowerCase() == 'job') {
          open(context, '/firma/job/${Uri.encodeComponent(segs[2])}');
          return true;
        }
        GoRouter.of(context).go('/firma');
        return true;
      case 'jobs':
      case 'staj-ai':
        GoRouter.of(context).go('/staj-ai');
        return true;
      case 'reels':
        openReel(context, reelId: uri.queryParameters['id']);
        return true;
      case 'home':
      case 'notifications':
      case 'profile':
      case 'market':
      case 'search':
        GoRouter.of(context).go('/$head');
        return true;
      default:
        if (segs.length >= 2) {
          open(context, '/$head/${Uri.encodeComponent(id!)}');
          return true;
        }
        GoRouter.of(context).go('/$head');
        return true;
    }
    return false;
  }

  /// Inbox / FCM bildirimi → ilgili içerik.
  static void openNotification(
    BuildContext context, {
    required String type,
    String? targetId,
    String? actorId,
    String? link,
    String title = '',
    String body = '',
  }) {
    final rawLink = link?.trim();
    if (rawLink != null &&
        rawLink.isNotEmpty &&
        openDeepLink(context, rawLink)) {
      return;
    }

    final t = type.toLowerCase().trim();
    final tid = targetId?.trim();
    final aid = actorId?.trim();
    final blob = '$title $body'.toLowerCase();

    if (t == 'reel' || t.startsWith('reel_') || blob.contains('reels')) {
      openReel(context, reelId: tid);
      return;
    }

    if (t == 'follow' ||
        t == 'follow_request' ||
        t == 'follow_accepted') {
      final u = aid ?? tid;
      if (u != null && u.isNotEmpty) openUser(context, u);
      return;
    }

    if (t == 'story' || t == 'story_like') {
      final u = aid ?? tid;
      if (u != null && u.isNotEmpty) {
        open(context, '/stories/view/${Uri.encodeComponent(u)}');
      }
      return;
    }

    if (t == 'event' ||
        t == 'event_application' ||
        (tid != null && tid.startsWith('e_'))) {
      if (tid != null && tid.isNotEmpty) {
        openEvent(context, tid);
        return;
      }
    }

    if (t == 'announcement' ||
        (tid != null && (tid.startsWith('a_') || tid.startsWith('ann_')))) {
      if (tid != null && tid.isNotEmpty) {
        openAnnouncement(context, tid);
        return;
      }
    }

    if (t == 'community') {
      if (tid == null || tid.isEmpty) return;
      if (blob.contains('etkinlik') ||
          blob.contains('başvuru') ||
          blob.contains('basvuru') ||
          blob.contains('kadro')) {
        openEvent(context, tid);
        return;
      }
      if (blob.contains('duyuru')) {
        openAnnouncement(context, tid);
        return;
      }
      // Topluluk hedefi çoğunlukla etkinlik; duyuru link’i varsa zaten yukarıda açıldı.
      openEvent(context, tid);
      return;
    }

    if (t == 'job') {
      if (tid == null || tid.isEmpty) {
        GoRouter.of(context).go('/staj-ai');
        return;
      }
      final postId = tid.startsWith('job_') ? tid : 'job_$tid';
      openPost(context, postId);
      return;
    }

    if (t == 'application' || t == 'offer') {
      if (tid != null && tid.isNotEmpty) {
        // Firma tarafı: ilan editörü; öğrenci tarafında da post yedek.
        open(context, '/firma/job/${Uri.encodeComponent(tid)}');
        return;
      }
      GoRouter.of(context).go('/firma');
      return;
    }

    if (t == 'like' ||
        t == 'comment' ||
        t == 'repost' ||
        t == 'mention' ||
        t == 'activity' ||
        t == 'promo') {
      if (blob.contains('hikâye') || blob.contains('hikaye')) {
        final u = aid ?? tid;
        if (u != null && u.isNotEmpty) {
          open(context, '/stories/view/${Uri.encodeComponent(u)}');
          return;
        }
      }
      if (tid != null && tid.isNotEmpty) {
        openPost(context, tid);
        return;
      }
    }

    if (tid != null && tid.isNotEmpty) {
      if (tid.startsWith('job_') ||
          tid.startsWith('p_') ||
          tid.contains('post')) {
        openPost(context, tid);
        return;
      }
      if (tid.startsWith('e_')) {
        openEvent(context, tid);
        return;
      }
      if (tid.startsWith('a_') || tid.startsWith('ann_')) {
        openAnnouncement(context, tid);
        return;
      }
      openPost(context, tid);
      return;
    }

    if (aid != null && aid.isNotEmpty) {
      openUser(context, aid);
    }
  }
}
