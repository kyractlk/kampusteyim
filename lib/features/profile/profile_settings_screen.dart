import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_provider.dart';
import '../auth/data/auth_provider.dart';
import '../jobs/jobs_provider.dart';
import '../plus/plus_widgets.dart';
import 'profile_screen.dart' show openThemePicker;

/// Instagram tarzı profil ayarları — gizlilik, tema, hesap vb.
class ProfileSettingsScreen extends StatelessWidget {
  const ProfileSettingsScreen({super.key});

  Future<void> _changePassword(BuildContext context) async {
    final currentCtrl = TextEditingController();
    final nextCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Şifre değiştir'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: currentCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Mevcut şifre',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: nextCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Yeni şifre (min. 6)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final user = fa.FirebaseAuth.instance.currentUser;
    final email = user?.email;
    if (user == null || email == null || email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Oturum bulunamadı')),
      );
      return;
    }
    final next = nextCtrl.text.trim();
    if (next.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Yeni şifre en az 6 karakter olmalı')),
      );
      return;
    }
    try {
      final cred = fa.EmailAuthProvider.credential(
        email: email,
        password: currentCtrl.text,
      );
      await user.reauthenticateWithCredential(cred);
      await user.updatePassword(next);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Şifre güncellendi')),
        );
      }
    } on fa.FirebaseAuthException catch (e) {
      if (!context.mounted) return;
      final msg = switch (e.code) {
        'wrong-password' || 'invalid-credential' => 'Mevcut şifre hatalı',
        'weak-password' => 'Yeni şifre çok zayıf',
        'requires-recent-login' => 'Tekrar giriş yapıp dene',
        _ => e.message ?? 'Şifre değiştirilemedi',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ayarlar')),
        body: const Center(child: Text('Giriş gerekli')),
      );
    }
    final incoming = user.incomingFollowRequests.length;

    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const PlusPrivilegesCard(),
          const SizedBox(height: 12),
          _tile(
            icon: Icons.person_add_alt_1_rounded,
            title: 'Gelen istekler',
            subtitle: incoming > 0
                ? '$incoming bekleyen istek'
                : 'Takip isteklerini yönet',
            badge: incoming > 0 ? incoming : null,
            onTap: () => context.push('/follow-requests'),
          ),
          _tile(
            icon: Icons.lock_outline,
            title: 'Gizlilik',
            subtitle: 'Gizli hesap, arama, engeller, izleyici modu',
            onTap: () => context.push('/privacy'),
          ),
          _tile(
            icon: Icons.password_rounded,
            title: 'Şifre değiştir',
            subtitle: 'Mevcut şifrenle yeni şifre belirle',
            onTap: () => _changePassword(context),
          ),
          _tile(
            icon: Icons.palette_outlined,
            title: 'Tema',
            subtitle: context.watch<ThemeProvider>().style.label,
            onTap: () => openThemePicker(context),
          ),
          _tile(
            icon: Icons.notifications_active_outlined,
            title: 'Bildirim izinleri',
            subtitle: 'Push, ilan, beğeni ve daha fazlası',
            onTap: () => context.push('/profile/notifications'),
          ),
          _tile(
            icon: Icons.confirmation_number_outlined,
            title: 'Biletlerim',
            subtitle: 'Satın alınan etkinlik biletleri',
            onTap: () => context.push('/tickets'),
          ),
          _tile(
            icon: Icons.timer_outlined,
            title: 'Çalışma odası',
            subtitle: 'Oda aç, katıl, chat + sayaç',
            onTap: () => context.push('/profile/study-timer'),
          ),
          _tile(
            icon: Icons.feedback_outlined,
            title: 'Geri bildirim',
            subtitle: 'Öneri / hata · admin paneline düşer',
            onTap: () => context.push('/profile/feedback'),
          ),
          if (user.panelAccess && (user.panelOrgId ?? '').isNotEmpty)
            _tile(
              icon: Icons.dashboard_customize_outlined,
              title: '${user.panelOrgName ?? 'Organizasyon'} paneli',
              subtitle: 'Kadro erişimin var',
              onTap: () {
                if (user.panelOrgType == 'community') {
                  context.push('/community');
                } else {
                  context.push('/firma/dashboard');
                }
              },
            ),
          if (user.isCompany)
            _tile(
              icon: Icons.business_center_outlined,
              title: 'Firma paneli',
              subtitle: 'İlan, başvuru, teklif',
              onTap: () async {
                await context.read<JobsProvider>().bindCompanyFromUser(user);
                if (context.mounted) context.push('/firma/dashboard');
              },
            ),
          _tile(
            icon: Icons.info_outline,
            title: 'Uygulama bilgisi',
            subtitle: 'AYS Tech · Kayra Çatalkaya',
            onTap: () => context.push('/about'),
          ),
          const SizedBox(height: 8),
          _tile(
            icon: Icons.delete_forever_outlined,
            title: 'Hesabımı sil',
            subtitle: 'E-posta kodu ile çift onay',
            danger: true,
            onTap: () => context.push('/profile/delete-account'),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () async {
              context.read<JobsProvider>().companyLogout();
              await auth.signOut();
              if (context.mounted) context.go('/home');
            },
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Çıkış yap'),
          ),
        ],
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    int? badge,
    bool danger = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: danger ? AppColors.crimson : AppColors.border,
          ),
        ),
        leading: badge != null
            ? Badge(
                label: Text('$badge'),
                child: Icon(icon, color: danger ? AppColors.crimson : null),
              )
            : Icon(icon, color: danger ? AppColors.crimson : null),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}
