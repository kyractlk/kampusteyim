import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/models.dart';
import 'app_share.dart';

/// Detay sayfaları — web adres çubuğu Twitter gibi /post/… olur.
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
}
