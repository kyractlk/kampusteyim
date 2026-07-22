import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/social_widgets.dart';
import '../../models/models.dart';
import '../auth/data/auth_provider.dart';

class PrivacySettingsScreen extends StatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  State<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends State<PrivacySettingsScreen> {
  bool _busy = false;

  Future<void> _update({
    bool? hideFromSearch,
    bool? isPrivateAccount,
    bool? isSpectatorMode,
  }) async {
    setState(() => _busy = true);
    try {
      await context.read<AuthProvider>().updatePrivacySettings(
            hideFromSearch: hideFromSearch,
            isPrivateAccount: isPrivateAccount,
            isSpectatorMode: isSpectatorMode,
          );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmSpectator(bool enable) async {
    if (!enable) {
      await _update(isSpectatorMode: false);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('İzleyici modu'),
        content: const Text(
          'UYARI: Görünmezlik / izleyici modu açıkken gönderi paylaşamaz, '
          'yorum yapamaz, beğenemez, yeniden paylaşamaz, hikâye '
          'görüntüleyemez veya paylaşamazsın.\n\n'
          'Yalnızca içeriği okuyabilirsin. Devam etmek istiyor musun?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.crimson),
            child: const Text('Aç'),
          ),
        ],
      ),
    );
    if (ok == true) await _update(isSpectatorMode: true);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Gizlilik')),
        body: const Center(child: Text('Giriş gerekli')),
      );
    }

    final blocked = user.blockedUserIds
        .map((id) => auth.findUser(id))
        .whereType<AppUser>()
        .toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Gizlilik')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Aramada gizle'),
            subtitle: const Text(
              'Hesabın arama sonuçlarında görünmez.',
            ),
            value: user.hideFromSearch,
            activeThumbColor: AppColors.cyan,
            onChanged: _busy
                ? null
                : (v) => _update(hideFromSearch: v),
          ),
          const Divider(),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Gizli hesap'),
            subtitle: const Text(
              'Instagram kuralları: Gizli hesapta yeni takipçiler önce '
              'onayını bekler. Onaylamadan gönderilerini, takipçi ve '
              'takip listelerini göremezler. Mevcut takipçilerin etkilenmez.',
            ),
            value: user.isPrivateAccount,
            activeThumbColor: AppColors.cyan,
            onChanged: _busy
                ? null
                : (v) => _update(isPrivateAccount: v),
          ),
          const Divider(),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Görünmezlik / izleyici modu'),
            subtitle: Text(
              'UYARI: Açıkken gönderi, yorum, beğeni, repost ve hikâye '
              'kullanılamaz.',
              style: TextStyle(
                color: user.isSpectatorMode
                    ? AppColors.crimson
                    : AppColors.textSecondary,
                fontWeight:
                    user.isSpectatorMode ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
            value: user.isSpectatorMode,
            activeThumbColor: AppColors.crimson,
            onChanged: _busy ? null : _confirmSpectator,
          ),
          const SizedBox(height: 20),
          const Text(
            'Engellenenler',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 8),
          if (user.blockedUserIds.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Engellenen kullanıcı yok.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          else
            ...blocked.map(
              (u) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: UserAvatar(
                  name: u.fullName,
                  photoUrl: u.photoUrl,
                  radius: 22,
                ),
                title: Text(u.fullName),
                subtitle: Text(u.handle),
                trailing: TextButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          await auth.unblockUser(u.id);
                          if (mounted) setState(() => _busy = false);
                        },
                  child: const Text('Engeli kaldır'),
                ),
                onTap: () => context.push('/user/${u.id}'),
              ),
            ),
          if (user.blockedUserIds.isNotEmpty &&
              blocked.length < user.blockedUserIds.length)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${user.blockedUserIds.length - blocked.length} kullanıcı '
                'dizinde bulunamadı; engel yine de kayıtlı.',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
