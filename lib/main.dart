import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'core/auth/secure_session.dart';
import 'core/constants/app_info.dart';
import 'core/permissions/app_permissions.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/keyboard_dismiss.dart';
import 'features/admin/admin_provider.dart';
import 'features/ads/ads_provider.dart';
import 'features/app_update/app_update_provider.dart';
import 'features/app_update/app_update_screen.dart';
import 'features/auth/data/auth_provider.dart';
import 'features/feed/feed_provider.dart';
import 'features/jobs/jobs_provider.dart';
import 'features/maintenance/maintenance_provider.dart';
import 'features/maintenance/maintenance_screen.dart';
import 'features/notifications/notification_provider.dart';
import 'features/notifications/push_service.dart';
import 'features/plus/plus_provider.dart';
import 'features/reels/reels_provider.dart';
import 'features/stories/stories_provider.dart';
import 'firebase_options.dart';
import 'routing/app_router.dart';
import 'package:go_router/go_router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    usePathUrlStrategy();
  } else {
    // Tam ekran: sistem navigasyon çubuğunu gizle (immersive).
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
    );
  }
  await initializeDateFormatting('tr');

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e, st) {
    debugPrint('[boot] firebase: $e\n$st');
  }

  try {
    await SecureSession.ensureAuthPersistence();
  } catch (e) {
    debugPrint('[boot] session: $e');
  }

  try {
    await PushService.instance.init();
    PushService.instance.onNotificationTap = (raw) {
      final ctx = appRootNavigatorKey.currentContext;
      if (ctx == null) return;
      var path = raw.trim();
      if (path.startsWith('https://')) {
        try {
          final uri = Uri.parse(path);
          final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
          if (segs.length >= 2) {
            path = '/${segs[0]}/${Uri.encodeComponent(segs[1])}';
          } else {
            path = '/home';
          }
        } catch (_) {
          return;
        }
      }
      if (!path.startsWith('/')) path = '/$path';
      GoRouter.of(ctx).push(path);
    };
  } catch (e, st) {
    debugPrint('[boot] push: $e\n$st');
  }

  // Bildirim + kamera + galeri / dosya izinleri (APK)
  unawaited(AppPermissions.requestStartupPermissions());

  runApp(const MtMobilApp());
}

class MtMobilApp extends StatefulWidget {
  const MtMobilApp({super.key});

  @override
  State<MtMobilApp> createState() => _MtMobilAppState();
}

class _MtMobilAppState extends State<MtMobilApp> {
  late final AuthProvider _auth;
  late final FeedProvider _feed;
  late final NotificationProvider _notifications;
  late final JobsProvider _jobs;
  late final AdminProvider _admin;
  late final MaintenanceProvider _maintenance;
  late final AppUpdateProvider _appUpdate;
  late final StoriesProvider _stories;
  late final ReelsProvider _reels;
  late final PlusProvider _plus;
  late final AdsProvider _ads;
  late final router = createRouter(_auth);

  @override
  void initState() {
    super.initState();
    _auth = AuthProvider();
    _feed = FeedProvider();
    _notifications = NotificationProvider();
    _feed.attachNotifications(_notifications);
    _jobs = JobsProvider();
    unawaited(_jobs.bindJobsFromFirestore());
    _admin = AdminProvider();
    _maintenance = MaintenanceProvider();
    _appUpdate = AppUpdateProvider();
    _stories = StoriesProvider()..attachAuth(_auth);
    _reels = ReelsProvider()
      ..attachAuth(_auth)
      ..attachFeed(_feed);
    _plus = PlusProvider()..bind();
    _ads = AdsProvider();
    unawaited(_plus.ensureConfigSeeded());
    _auth.addListener(_onAuth);
    unawaited(_ads.refresh());
  }

  void _onAuth() {
    _notifications.bindUser(_auth.user?.id, profile: _auth.user);
    final u = _auth.user;
    if (u != null) {
      unawaited(_admin.loadRolesFromFirestore());
      unawaited(_ads.refresh(city: u.city, university: u.university));
    }
    if (u != null && u.isCompany) {
      unawaited(_jobs.bindCompanyFromUser(u));
    } else {
      _jobs.companyLogout();
    }
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuth);
    _auth.dispose();
    _feed.dispose();
    _notifications.dispose();
    _jobs.dispose();
    _admin.dispose();
    _maintenance.dispose();
    _appUpdate.dispose();
    _stories.dispose();
    _reels.dispose();
    _plus.dispose();
    _ads.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _auth),
        ChangeNotifierProvider.value(value: _feed),
        ChangeNotifierProvider.value(value: _notifications),
        ChangeNotifierProvider.value(value: _jobs),
        ChangeNotifierProvider.value(value: _admin),
        ChangeNotifierProvider.value(value: _maintenance),
        ChangeNotifierProvider.value(value: _appUpdate),
        ChangeNotifierProvider.value(value: _stories),
        ChangeNotifierProvider.value(value: _reels),
        ChangeNotifierProvider.value(value: _plus),
        ChangeNotifierProvider.value(value: _ads),
      ],
      child: MaterialApp.router(
        title: AppInfo.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        routerConfig: router,
        locale: const Locale('tr'),
        supportedLocales: const [Locale('tr'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) {
          final maint = context.watch<MaintenanceProvider>();
          final upd = context.watch<AppUpdateProvider>();
          final auth = context.watch<AuthProvider>();
          final bypass =
              context.read<AdminProvider>().canAccessDuringMaintenance(auth.user);

          // Bakımda personel kapısı — web’de Uri.base, mobilde GoRouter (güvenli).
          final path = _currentAppPath(context);
          final staffPath = path == '/admin' ||
              path.startsWith('/admin/') ||
              path == '/login' ||
              path == '/sifremi-unuttum' ||
              path == '/sifre-sifirla' ||
              path.startsWith('/r/');

          if (upd.blocksApp && !staffPath) {
            return const AppUpdateForceScreen();
          }

          if (maint.blocksApp && !bypass && !staffPath) {
            return const MaintenanceScreen();
          }
          // Klavye açılınca içerik yukarı kaysın; notch / gesture inset korunur.
          // Boş alana / başka widget’a dokununca klavye kapanır (odak alanı hariç).
          final media = MediaQuery.maybeOf(context);
          Widget content = KeyboardDismissOnTap(
            child: child ?? const SizedBox.shrink(),
          );
          if (upd.showSoftBanner) {
            content = Column(
              children: [
                Expanded(child: content),
                const AppUpdateSoftBanner(),
              ],
            );
          }
          if (media == null) return content;
          return MediaQuery(
            data: media.copyWith(
              textScaler: media.textScaler.clamp(
                minScaleFactor: 0.9,
                maxScaleFactor: 1.25,
              ),
            ),
            child: content,
          );
        },
      ),
    );
  }
}

String _currentAppPath(BuildContext context) {
  if (kIsWeb) {
    final p = Uri.base.path;
    if (p.isNotEmpty) {
      return p.endsWith('/') && p.length > 1 ? p.substring(0, p.length - 1) : p;
    }
  }
  try {
    final router = GoRouter.maybeOf(context);
    if (router == null) return '';
    final matches = router.routerDelegate.currentConfiguration.matches;
    if (matches.isEmpty) return '';
    return router.state.uri.path;
  } catch (_) {
    return '';
  }
}
