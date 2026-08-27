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
}
