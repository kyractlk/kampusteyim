import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_assets.dart';
import '../../core/constants/app_info.dart';
import '../../core/icons/mt_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_provider.dart';
import '../../core/utils/auth_gate.dart';
import '../../core/utils/breakpoints.dart';
import '../../core/widgets/app_circle_logo.dart';
import '../../core/widgets/liquid_glass.dart';
import '../../models/models.dart';
import '../auth/data/auth_provider.dart';
import '../notifications/notification_provider.dart';
import '../reels/reels_provider.dart';

/// Reels alt menü — içerik yüksekliği (home indicator / sistem inset hariç).
const double kReelsBottomNavHeight = 50;

/// Floating Liquid Glass bar yüksekliği (içerik + padding).
const double kGlassNavBarHeight = 64;

/// Alt menü altındaki sistem boşluğu — önce %30, sonra bir %20 daha kısaltıldı.
double shellBottomNavInset(BuildContext context) =>
    MediaQuery.viewPaddingOf(context).bottom * 0.56;

class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _onTap(BuildContext context, int index) {
    // Profil sekmesi (son index)
    if (index == 4) {
      final auth = context.read<AuthProvider>();
      if (!auth.isAuthenticated) {
        AuthGate.requireAuth(
          context,
          message: 'Profilini görmek ve düzenlemek için giriş yapmalısın.',
        );
        return;
      }
    }
    context.read<ReelsProvider>().setTabActive(index == 1);
    if (index == 1) {
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: Colors.black,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
      );
    } else {
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
      );
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

    // Reels sekmesi dışındayken videoyu durdur (indexedStack yüzünden dispose olmaz).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      context.read<ReelsProvider>().setTabActive(index == 1);
    });

    // —— MOBİL: alt nav + tam genişlik içerik ——
    if (!wide) {
      final reelsMode = index == 1;
      final glass = context.watch<ThemeProvider>().isLiquidGlass;
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: _onPop,
        child: Scaffold(
          resizeToAvoidBottomInset: true,
          extendBody: true,
          backgroundColor: reelsMode ? Colors.black : null,
          body: navigationShell,
          bottomNavigationBar: glass || reelsMode
              ? _LiquidGlassNavBar(
                  index: index,
                  reelsMode: reelsMode,
                  onTap: (i) => _onTap(context, i),
                  destinations: _destinations(loggedIn),
                )
              : _ShellBottomNavBar(
                  index: index,
                  reelsMode: reelsMode,
                  onTap: (i) => _onTap(context, i),
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
          icon: Icon(Icons.movie_filter_outlined),
          selectedIcon: Icon(Icons.movie_filter_rounded),
          label: 'Reels',
        ),
        const NavigationDestination(
          icon: Icon(Icons.campaign_outlined),
          selectedIcon: Icon(Icons.campaign_rounded),
          label: 'Duyuru',
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

/// Floating Liquid Glass alt bar — Reels dahil daha belirgin cam.
class _LiquidGlassNavBar extends StatelessWidget {
  const _LiquidGlassNavBar({
    required this.index,
    required this.reelsMode,
    required this.onTap,
    required this.destinations,
  });

  final int index;
  final bool reelsMode;
  final ValueChanged<int> onTap;
  final List<NavigationDestination> destinations;

  @override
  Widget build(BuildContext context) {
    final inset = shellBottomNavInset(context);
    final dark = Theme.of(context).brightness == Brightness.dark || reelsMode;
    final selectedBg = dark
        ? Colors.white.withValues(alpha: 0.28)
        : AppColors.navy.withValues(alpha: 0.90);
    final selectedFg = Colors.white;
    final idleFg = dark
        ? Colors.white.withValues(alpha: 0.72)
        : AppColors.textSecondary.withValues(alpha: 0.9);
    final selectedLabel = dark ? Colors.white : AppColors.navy;

    return SafeArea(
      top: false,
      minimum: EdgeInsets.only(bottom: inset > 0 ? 2 : 8),
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 0, 12, inset > 0 ? 6 : 12),
        child: LiquidGlass(
          dark: dark,
          blur: reelsMode ? 48 : 36,
          borderRadius: 36,
          intensity: reelsMode ? 1.35 : 1.1,
          borderOpacity: dark ? 0.42 : 0.80,
          child: SizedBox(
            height: kGlassNavBarHeight + 2,
            child: Row(
              children: [
                for (var i = 0; i < destinations.length; i++)
                  Expanded(
                    child: _GlassNavItem(
                      destination: destinations[i],
                      selected: i == index,
                      selectedBg: selectedBg,
                      selectedFg: selectedFg,
                      idleFg: idleFg,
                      selectedLabel: selectedLabel,
                      onTap: () => onTap(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassNavItem extends StatelessWidget {
  const _GlassNavItem({
    required this.destination,
    required this.selected,
    required this.selectedBg,
    required this.selectedFg,
    required this.idleFg,
    required this.selectedLabel,
    required this.onTap,
  });

  final NavigationDestination destination;
  final bool selected;
  final Color selectedBg;
  final Color selectedFg;
  final Color idleFg;
  final Color selectedLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = selected
        ? (destination.selectedIcon ?? destination.icon)
        : destination.icon;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        splashColor: Colors.white.withValues(alpha: 0.12),
        highlightColor: Colors.white.withValues(alpha: 0.06),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: selected ? selectedBg : Colors.transparent,
                shape: BoxShape.circle,
                border: selected
                    ? Border.all(
                        color: Colors.white.withValues(alpha: 0.35),
                        width: 1,
                      )
                    : null,
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: selectedBg.withValues(alpha: 0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: IconTheme(
                data: IconThemeData(
                  size: 22,
                  color: selected ? selectedFg : idleFg,
                ),
                child: icon,
              ),
            ),
            const SizedBox(height: 2),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                letterSpacing: selected ? 0.1 : 0,
                color: selected ? selectedLabel : idleFg,
              ),
              child: Text(
                destination.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mobil alt menü — klasik (cam kapalıyken).
class _ShellBottomNavBar extends StatelessWidget {
  const _ShellBottomNavBar({
    required this.index,
    required this.reelsMode,
    required this.onTap,
    required this.destinations,
  });

  final int index;
  final bool reelsMode;
  final ValueChanged<int> onTap;
  final List<NavigationDestination> destinations;

  @override
  Widget build(BuildContext context) {
    final inset = shellBottomNavInset(context);
    final bg = reelsMode ? Colors.black : AppColors.surface;
    final indicator = reelsMode
        ? Colors.white.withValues(alpha: 0.16)
        : AppColors.cyan.withValues(alpha: 0.18);
    final barH = reelsMode ? kReelsBottomNavHeight : 68.0;

    return ColoredBox(
      color: bg,
      child: Padding(
        padding: EdgeInsets.only(bottom: inset),
        child: MediaQuery.removePadding(
          context: context,
          removeBottom: true,
          child: Theme(
            data: Theme.of(context).copyWith(
              navigationBarTheme: NavigationBarThemeData(
                backgroundColor: bg,
                indicatorColor: indicator,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                shadowColor: Colors.transparent,
                height: barH,
                labelTextStyle: WidgetStateProperty.resolveWith((states) {
                  final selected = states.contains(WidgetState.selected);
                  return TextStyle(
                    fontSize: reelsMode ? 10 : 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    height: reelsMode ? 1.0 : null,
                    color: reelsMode
                        ? (selected ? Colors.white : Colors.white60)
                        : (selected
                            ? AppColors.navy
                            : AppColors.textSecondary),
                  );
                }),
                iconTheme: WidgetStateProperty.resolveWith((states) {
                  final selected = states.contains(WidgetState.selected);
                  return IconThemeData(
                    size: reelsMode ? 22 : 24,
                    color: reelsMode
                        ? (selected ? Colors.white : Colors.white60)
                        : (selected
                            ? AppColors.navy
                            : AppColors.textSecondary),
                  );
                }),
              ),
            ),
            child: SizedBox(
              height: barH,
              child: NavigationBar(
                selectedIndex: index,
                onDestinationSelected: onTap,
                backgroundColor: bg,
                indicatorColor: indicator,
                labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                destinations: destinations,
              ),
            ),
          ),
        ),
      ),
    );
  }
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
    final hubUnread = context.watch<NotificationProvider>().unreadCount;
    final user = context.watch<AuthProvider>().user;
    final unread =
        hubUnread + (user?.incomingFollowRequests.length ?? 0);

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
            icon: Icons.movie_filter_outlined,
            selectedIcon: Icons.movie_filter_rounded,
            label: 'Reels',
            showLabel: showLabels,
            onTap: () => onSelect(1),
          ),
          _RailItem(
            selected: selectedIndex == 2,
            icon: Icons.campaign_outlined,
            selectedIcon: Icons.campaign_rounded,
            label: 'Duyurular',
            showLabel: showLabels,
            onTap: () => onSelect(2),
          ),
          _RailItem(
            selected: selectedIndex == 3,
            icon: Icons.event_outlined,
            selectedIcon: Icons.event_rounded,
            label: 'Etkinlik',
            showLabel: showLabels,
            onTap: () => onSelect(3),
          ),
          _RailItem(
            selected: selectedIndex == 4,
            icon: loggedIn ? Icons.person_outline : Icons.login_rounded,
            selectedIcon: loggedIn ? Icons.person_rounded : Icons.login_rounded,
            label: loggedIn ? 'Profil' : 'Giriş',
            showLabel: showLabels,
            onTap: () => onSelect(4),
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
    final hubUnread = context.watch<NotificationProvider>().unreadCount;
    final pending =
        context.watch<AuthProvider>().user?.incomingFollowRequests.length ?? 0;
    final unread = hubUnread + pending;
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
