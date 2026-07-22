import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/about/about_screen.dart';
import '../features/admin/admin_portal.dart';
import '../features/announcements/announcement_detail_screen.dart';
import '../features/announcements/announcements_screen.dart';
import '../features/auth/data/auth_provider.dart';
import '../features/auth/presentation/forgot_password_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/pending_approval_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/auth/presentation/reset_password_screen.dart';
import '../features/community/community_portal.dart';
import '../features/cv/cv_ai_screen.dart';
import '../features/events/event_detail_screen.dart';
import '../features/events/events_screen.dart';
import '../features/feed/feed_screen.dart';
import '../features/feed/post_detail_screen.dart';
import '../features/feedback/feedback_screen.dart';
import '../features/home/home_shell.dart';
import '../features/jobs/company_portal.dart';
import '../features/jobs/staj_ai_screen.dart';
import '../features/legal/account_delete_screen.dart';
import '../features/notifications/notification_settings_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/privacy/privacy_settings_screen.dart';
import '../features/profile/follow_list_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/search/search_screen.dart';
import '../features/stories/story_viewer_screen.dart';
import '../features/study/study_lobby_screen.dart';
import '../features/study/study_room_screen.dart';

/// Root navigator — detay URL’leri (/post/…) tarayıcı çubuğunda görünsün.
final GlobalKey<NavigatorState> appRootNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'root');

GoRouter createRouter(AuthProvider auth) {
  return GoRouter(
    navigatorKey: appRootNavigatorKey,
    initialLocation: '/home',
    refreshListenable: auth,
    redirect: (context, state) {
      final loggedIn = auth.isAuthenticated;
      final loc = state.matchedLocation;
      final user = auth.user;
      final pendingGate = loggedIn &&
          user != null &&
          !user.canAccessAdmin &&
          !user.isCompany &&
          !user.isCommunity &&
          (user.isAccountPending || user.isAccountRejected);
      if (pendingGate && loc != '/pending-approval' && loc != '/login') {
        return '/pending-approval';
      }
      if (loggedIn &&
          !pendingGate &&
          (loc == '/login' ||
              loc == '/register' ||
              loc == '/pending-approval')) {
        return AuthProvider.homeRouteFor(user);
      }
      if (loggedIn && (loc == '/login' || loc == '/register')) {
        return AuthProvider.homeRouteFor(user);
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        parentNavigatorKey: appRootNavigatorKey,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const LoginScreen(),
          transitionsBuilder: (context, animation, secondary, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      ),
      GoRoute(
        path: '/sifremi-unuttum',
        parentNavigatorKey: appRootNavigatorKey,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: ForgotPasswordScreen(
            initialEmail: state.uri.queryParameters['email'] ?? '',
          ),
          transitionsBuilder: (context, animation, secondary, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      ),
      GoRoute(
        path: '/r/:code',
        parentNavigatorKey: appRootNavigatorKey,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: ResetPasswordScreen(
            code: state.pathParameters['code'] ?? '',
          ),
          transitionsBuilder: (context, animation, secondary, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      ),
      GoRoute(
        path: '/sifre-sifirla',
        redirect: (context, state) {
          final token = state.uri.queryParameters['token'] ?? '';
          if (token.isNotEmpty) return '/r/$token';
          return '/sifremi-unuttum';
        },
      ),
      GoRoute(
        path: '/register',
        parentNavigatorKey: appRootNavigatorKey,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const RegisterScreen(),
          transitionsBuilder: (context, animation, secondary, child) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.08, 0),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              )),
              child: FadeTransition(opacity: animation, child: child),
            );
          },
        ),
      ),
      GoRoute(
        path: '/pending-approval',
        parentNavigatorKey: appRootNavigatorKey,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const PendingApprovalScreen(),
          transitionsBuilder: (context, animation, secondary, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      ),
      GoRoute(
        path: '/search',
        parentNavigatorKey: appRootNavigatorKey,
        builder: (context, state) {
          final q = state.uri.queryParameters['q'] ?? '';
          return SearchScreen(initialQuery: q);
        },
      ),
      GoRoute(
        path: '/notifications',
        parentNavigatorKey: appRootNavigatorKey,
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/about',
        parentNavigatorKey: appRootNavigatorKey,
        builder: (context, state) => const AboutScreen(),
      ),
      GoRoute(
        path: '/admin',
        parentNavigatorKey: appRootNavigatorKey,
        builder: (context, state) => const AdminPortalScreen(),
      ),
      GoRoute(
        path: '/community',
        parentNavigatorKey: appRootNavigatorKey,
        builder: (context, state) => const CommunityPortalScreen(),
      ),
      // Twitter tarzı: gaunengineering.com.tr/post/{id}
      GoRoute(
        path: '/post/:id',
        parentNavigatorKey: appRootNavigatorKey,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          name: '/post/${state.pathParameters['id']}',
          child: PostDetailScreen(postId: state.pathParameters['id']!),
          transitionsBuilder: (context, animation, secondary, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      ),
      GoRoute(
        path: '/user/:id',
        parentNavigatorKey: appRootNavigatorKey,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          name: '/user/${state.pathParameters['id']}',
          child: UserProfileView(userId: state.pathParameters['id']!),
          transitionsBuilder: (context, animation, secondary, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      ),
      GoRoute(
        path: '/user/:id/followers',
        parentNavigatorKey: appRootNavigatorKey,
        builder: (context, state) => FollowListScreen(
          userId: state.pathParameters['id']!,
          mode: FollowListMode.followers,
        ),
      ),
      GoRoute(
        path: '/user/:id/following',
        parentNavigatorKey: appRootNavigatorKey,
        builder: (context, state) => FollowListScreen(
          userId: state.pathParameters['id']!,
          mode: FollowListMode.following,
        ),
      ),
      GoRoute(
        path: '/stories/view/:userId',
        parentNavigatorKey: appRootNavigatorKey,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          name: '/stories/view/${state.pathParameters['userId']}',
          child: StoryViewerScreen(
            userId: state.pathParameters['userId']!,
          ),
          transitionsBuilder: (context, animation, secondary, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      ),
      GoRoute(
        path: '/privacy',
        parentNavigatorKey: appRootNavigatorKey,
        builder: (context, state) => const PrivacySettingsScreen(),
      ),
      GoRoute(
        path: '/announcement/:id',
        parentNavigatorKey: appRootNavigatorKey,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          name: '/announcement/${state.pathParameters['id']}',
          child: AnnouncementDetailScreen(
            announcementId: state.pathParameters['id']!,
          ),
          transitionsBuilder: (context, animation, secondary, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      ),
      GoRoute(
        path: '/event/:id',
        parentNavigatorKey: appRootNavigatorKey,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          name: '/event/${state.pathParameters['id']}',
          child: EventDetailScreen(eventId: state.pathParameters['id']!),
          transitionsBuilder: (context, animation, secondary, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      ),
      GoRoute(
        path: '/profile/edit',
        parentNavigatorKey: appRootNavigatorKey,
        builder: (context, state) => const EditProfileScreen(),
      ),
      GoRoute(
        path: '/profile/notifications',
        parentNavigatorKey: appRootNavigatorKey,
        builder: (context, state) => const NotificationSettingsScreen(),
      ),
      GoRoute(
        path: '/profile/feedback',
        parentNavigatorKey: appRootNavigatorKey,
        builder: (context, state) => const FeedbackScreen(),
      ),
      GoRoute(
        path: '/profile/study-timer',
        parentNavigatorKey: appRootNavigatorKey,
        builder: (context, state) => const StudyLobbyScreen(),
      ),
      GoRoute(
        path: '/profile/delete-account',
        parentNavigatorKey: appRootNavigatorKey,
        builder: (context, state) => const AccountDeleteScreen(),
      ),
      GoRoute(
        path: '/study/solo',
        parentNavigatorKey: appRootNavigatorKey,
        builder: (context, state) {
          final m = int.tryParse(state.uri.queryParameters['m'] ?? '') ?? 25;
          return StudySoloTimerScreen(initialMinutes: m);
        },
      ),
      GoRoute(
        path: '/study/:id',
        parentNavigatorKey: appRootNavigatorKey,
        builder: (context, state) => StudyRoomScreen(
          roomId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/cv-ai',
        parentNavigatorKey: appRootNavigatorKey,
        builder: (context, state) => const CvAiScreen(),
      ),
      GoRoute(
        path: '/staj-ai',
        parentNavigatorKey: appRootNavigatorKey,
        builder: (context, state) => const StajAiScreen(),
      ),
      GoRoute(
        path: '/firma',
        parentNavigatorKey: appRootNavigatorKey,
        builder: (_, _) => const CompanyLoginScreen(),
      ),
      GoRoute(
        path: '/firma/dashboard',
        parentNavigatorKey: appRootNavigatorKey,
        builder: (_, _) => const CompanyDashboardScreen(),
      ),
      GoRoute(
        path: '/firma/job/:id',
        parentNavigatorKey: appRootNavigatorKey,
        builder: (context, state) =>
            CompanyJobEditorScreen(jobId: state.pathParameters['id']),
      ),
      GoRoute(
        path: '/firma/students',
        parentNavigatorKey: appRootNavigatorKey,
        builder: (_, _) => const CompanyStudentsScreen(),
      ),
      GoRoute(
        path: '/firma/ai',
        parentNavigatorKey: appRootNavigatorKey,
        builder: (_, _) => const CompanyAiScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return HomeShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) => const FeedScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/announcements',
                builder: (context, state) => const AnnouncementsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/events',
                builder: (context, state) => const EventsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
