import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_assets.dart';
import '../../core/constants/app_info.dart';
import '../../core/icons/mt_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/auth_gate.dart';
import '../../core/utils/breakpoints.dart';
import '../../core/widgets/app_circle_logo.dart';
import '../../models/models.dart';
import '../auth/data/auth_provider.dart';
import '../notifications/notification_provider.dart';

class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _onTap(BuildContext context, int index) {
    if (index == 3) {
      final auth = context.read<AuthProvider>();
      if (!auth.isAuthenticated) {
        AuthGate.requireAuth(
          context,
          message: 'Profilini görmek ve düzenlemek için giriş yapmalısın.',
        );
        return;
      }
    }
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  /// Shell’de geri: önce ana sekmeye; zaten oradaysa uygulamadan çık.
  void _onPop(bool didPop, Object? result) {
    if (didPop) return;
    if (navigationShell.currentIndex != 0) {
      navigationShell.goBranch(0);
    } else {
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = context.watch<AuthProvider>().isAuthenticated;
    final wide = AppBreakpoints.isWide(context);
    final index = navigationShell.currentIndex;

    // —— MOBİL: alt nav + tam genişlik içerik ——
    if (!wide) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: _onPop,
        child: Scaffold(
          resizeToAvoidBottomInset: true,
          body: navigationShell,
          bottomNavigationBar: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (i) => _onTap(context, i),
            backgroundColor: AppColors.surface,
            indicatorColor: AppColors.cyan.withValues(alpha: 0.18),
            destinations: _destinations(loggedIn),
          ),
        ),
      );
    }

    // —— PC: Twitter 3 kolon (rail · feed · sidebar) ——
    final labels = AppBreakpoints.showRailLabels(context);
    final railW =
        labels ? AppBreakpoints.railExpanded : AppBreakpoints.railWidth;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _onPop,
      child: Scaffold(
        backgroundColor: AppColors.background,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppBreakpoints.shellMax),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: railW,
                  child: _DesktopRail(
                    selectedIndex: index,
                    loggedIn: loggedIn,
                    showLabels: labels,
                    onSelect: (i) => _onTap(context, i),
                  ),
                ),
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: AppColors.border.withValues(alpha: 0.8),
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: AppBreakpoints.feedMax,
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          border: Border.symmetric(
                            vertical: BorderSide(
                              color: AppColors.border.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                        child: navigationShell,
                      ),
                    ),
                  ),
                ),
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: AppColors.border.withValues(alpha: 0.8),
                ),
                SizedBox(
                  width: AppBreakpoints.sidebarWidth,
                  child: const _DesktopSidebar(),
                ),
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }

  List<NavigationDestination> _destinations(bool loggedIn) => [
        const NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home_rounded),
          label: 'Akış',
        ),
        const NavigationDestination(
          icon: Icon(Icons.campaign_outlined),
          selectedIcon: Icon(Icons.campaign_rounded),
          label: 'Duyurular',
        ),
        const NavigationDestination(
          icon: Icon(Icons.event_outlined),
          selectedIcon: Icon(Icons.event_rounded),
          label: 'Etkinlik',
        ),
        NavigationDestination(
          icon: Icon(loggedIn ? Icons.person_outline : Icons.login_rounded),
          selectedIcon:
              Icon(loggedIn ? Icons.person_rounded : Icons.login_rounded),
          label: loggedIn ? 'Profil' : 'Giriş',
        ),
      ];
}

class _DesktopRail extends StatelessWidget {
  const _DesktopRail({
    required this.selectedIndex,
    required this.loggedIn,
    required this.showLabels,
    required this.onSelect,
  });

  final int selectedIndex;
  final bool loggedIn;
  final bool showLabels;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final unread = context.watch<NotificationProvider>().unreadCount;
    final user = context.watch<AuthProvider>().user;

    return Material(
      color: AppColors.surface,
      child: ListView(
        padding: EdgeInsets.fromLTRB(showLabels ? 12 : 8, 16, showLabels ? 12 : 8, 24),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: showLabels
                ? const MtTitle()
                : Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.asset(
                        AppAssets.kampusIcon,
                        width: 36,
                        height: 36,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          _RailItem(
            selected: selectedIndex == 0,
            icon: Icons.home_outlined,
            selectedIcon: Icons.home_rounded,
            label: 'Akış',
            showLabel: showLabels,
            onTap: () => onSelect(0),
          ),
          _RailItem(
            selected: selectedIndex == 1,
            icon: Icons.campaign_outlined,
            selectedIcon: Icons.campaign_rounded,
            label: 'Duyurular',
            showLabel: showLabels,
            onTap: () => onSelect(1),
          ),
          _RailItem(
            selected: selectedIndex == 2,
            icon: Icons.event_outlined,
            selectedIcon: Icons.event_rounded,
            label: 'Etkinlik',
            showLabel: showLabels,
            onTap: () => onSelect(2),
          ),
          _RailItem(
            selected: selectedIndex == 3,
            icon: loggedIn ? Icons.person_outline : Icons.login_rounded,
            selectedIcon: loggedIn ? Icons.person_rounded : Icons.login_rounded,
            label: loggedIn ? 'Profil' : 'Giriş',
            showLabel: showLabels,
            onTap: () => onSelect(3),
          ),
          const SizedBox(height: 4),
          _RailItem(
            selected: false,
            icon: Icons.search_rounded,
            selectedIcon: Icons.search_rounded,
            label: 'Ara',
            showLabel: showLabels,
            onTap: () => context.push('/search'),
          ),
          if (loggedIn)
            _RailItem(
              selected: false,
              icon: Icons.notifications_none_rounded,
              selectedIcon: Icons.notifications_rounded,
              label: unread > 0 ? 'Bildirimler ($unread)' : 'Bildirimler',
              showLabel: showLabels,
              onTap: () => context.push('/notifications'),
            ),
          if (user != null && user.canAccessAdmin)
            _RailItem(
              selected: false,
              icon: Icons.admin_panel_settings_outlined,
              selectedIcon: Icons.admin_panel_settings_rounded,
              label: 'Admin',
              showLabel: showLabels,
              onTap: () => context.push('/admin'),
            ),
          if (user != null &&
              user.role == UserRole.company &&
              !(user.isBot))
            _RailItem(
              selected: false,
              icon: Icons.business_center_outlined,
              selectedIcon: Icons.business_center_rounded,
              label: 'Firma Online',
              showLabel: showLabels,
              onTap: () => context.push('/firma/dashboard'),
            ),
          const SizedBox(height: 16),
          if (showLabels)
            FilledButton.icon(
              onPressed: () {
                if (!loggedIn) {
                  context.push('/login');
                  return;
                }
                onSelect(0);
              },
              icon: const Icon(Icons.edit_outlined),
              label: Text(loggedIn ? 'Gönderi' : 'Giriş yap'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
                backgroundColor: AppColors.navy,
              ),
            )
          else
            Center(
              child: FloatingActionButton(
                mini: true,
                backgroundColor: AppColors.navy,
                onPressed: () {
                  if (!loggedIn) {
                    context.push('/login');
                    return;
                  }
                  onSelect(0);
                },
                child: Icon(
                  loggedIn ? Icons.edit_outlined : Icons.login_rounded,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.selected,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.onTap,
    this.showLabel = true,
  });

  final bool selected;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final VoidCallback onTap;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    if (!showLabel) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Tooltip(
          message: label,
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: onTap,
            child: Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.cyan.withValues(alpha: 0.16)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Icon(selected ? selectedIcon : icon, size: 26),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: ListTile(
        selected: selected,
        selectedTileColor: AppColors.cyan.withValues(alpha: 0.14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        leading: Icon(selected ? selectedIcon : icon),
        title: Text(
          label,
          style: TextStyle(
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final loggedIn = auth.isAuthenticated;
    final user = auth.user;

    return Material(
      color: AppColors.background,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Kampüs',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                const Text(
                  'KampüsteyimAPP · duyuru, etkinlik ve staj.',
                  style: TextStyle(color: AppColors.textSecondary, height: 1.35),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      label: const Text('Duyurular'),
                      onPressed: () => context.go('/announcements'),
                    ),
                    ActionChip(
                      label: const Text('Etkinlik'),
                      onPressed: () => context.go('/events'),
                    ),
                    if (loggedIn)
                      ActionChip(
                        label: const Text('Staj-AI'),
                        onPressed: () => context.push('/staj-ai'),
                      ),
                    if (loggedIn)
                      ActionChip(
                        label: const Text('CV-AI'),
                        onPressed: () => context.push('/cv-ai'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (user != null && user.canAccessAdmin) ...[
            const SizedBox(height: 14),
            _SidePanel(
              title: 'Platform Admin',
              accent: AppColors.navy,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const MtIcon(MtIcons.admin, size: 22, color: AppColors.navy),
                title: const Text('Yönetim paneli'),
                subtitle: const Text('Kullanıcı · şikayet · ban'),
                onTap: () => context.push('/admin'),
              ),
            ),
          ],
          if (user != null &&
              user.role == UserRole.company &&
              !user.isBot) ...[
            const SizedBox(height: 14),
            _SidePanel(
              title: 'Firma Online',
              accent: AppColors.cyan,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const AppCircleLogo(
                  logo: AppLogo.ays,
                  size: 28,
                  showBorder: false,
                ),
                title: const Text('İşveren paneli'),
                subtitle: const Text('İlan · CV · teklif'),
                onTap: () => context.push('/firma/dashboard'),
              ),
            ),
          ],
          const SizedBox(height: 14),
          _SidePanel(
            title: 'Keşfet',
            accent: AppColors.border,
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const MtIcon(MtIcons.bell, size: 22),
                  title: const Text('Bildirimler'),
                  onTap: () => loggedIn
                      ? context.push('/notifications')
                      : context.push('/login'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.search_rounded),
                  title: const Text('Kullanıcı / etiket ara'),
                  onTap: () => context.push('/search'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.info_outline),
                  title: const Text('Uygulama bilgisi'),
                  onTap: () => context.push('/about'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            '© KampüsteyimAPP · AYS Tech',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _SidePanel extends StatelessWidget {
  const _SidePanel({
    required this.title,
    required this.child,
    required this.accent,
  });

  final String title;
  final Widget child;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class FeedAppBarActions extends StatelessWidget {
  const FeedAppBarActions({super.key});

  @override
  Widget build(BuildContext context) {
    if (AppBreakpoints.isWide(context)) {
      return const SizedBox.shrink();
    }
    final loggedIn = context.watch<AuthProvider>().isAuthenticated;
    final unread = context.watch<NotificationProvider>().unreadCount;
    return Row(
      children: [
        IconButton(
          tooltip: 'Ara',
          onPressed: () => context.push('/search'),
          icon: const Icon(Icons.search_rounded),
        ),
        if (loggedIn)
          IconButton(
            tooltip: 'Bildirimler',
            onPressed: () => context.push('/notifications'),
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text('$unread'),
              child: const MtIcon(MtIcons.bell, size: 22),
            ),
          )
        else
          TextButton(
            onPressed: () => context.push('/login'),
            child: const Text('Giriş'),
          ),
      ],
    );
  }
}

class MtTitle extends StatelessWidget {
  const MtTitle({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.asset(
            AppAssets.kampusIcon,
            width: 32,
            height: 32,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          AppInfo.appName,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
      ],
    );
  }
}
