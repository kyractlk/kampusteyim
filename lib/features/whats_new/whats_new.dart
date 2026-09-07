import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_info.dart';
import '../../core/theme/app_colors.dart';

/// Mağaza sürümüyle eşleşen yenilik listesi — ilk açılışta bir kez gösterilir.
class WhatsNewCatalog {
  static const releaseVersion = AppInfo.versionLabel;

  static const items = <WhatsNewItem>[
    WhatsNewItem(
      icon: Icons.swap_horiz_rounded,
      title: 'Hesaplar arası geçiş',
      body:
          'Topluluk ve firma hesapların arasında çıkış yapmadan geç. Ayarlar → Bağlı hesaplar.',
      route: '/profile/settings',
    ),
    WhatsNewItem(
      icon: Icons.qr_code_2_rounded,
      title: 'Tanıtım kartı',
      body:
          'Dikey kart + QR indir. Okutulma ve takip sayıları stüdyoda görünür.',
      route: '/tanitimkarti',
    ),
    WhatsNewItem(
      icon: Icons.campaign_outlined,
      title: 'Resmi hesap yetkileri',
      body:
          '@kampusteyim hem duyuru hem Firma Online hem bilet açabilir. Topluluk ve firma panelleri yan yana.',
    ),
    WhatsNewItem(
      icon: Icons.photo_outlined,
      title: 'Profil fotoğrafı',
      body:
          'Yüklenen foto kareye ezilmeden sığar. Şeffaf kenar korunur, logo bozulmaz.',
    ),
    WhatsNewItem(
      icon: Icons.delete_forever_outlined,
      title: 'Hesap silme',
      body:
          'Silinen hesap takipçi listesinde hayalet isim bırakmaz. Kalıntı tamamen gider.',
    ),
  ];
}

class WhatsNewItem {
  const WhatsNewItem({
    required this.icon,
    required this.title,
    required this.body,
    this.route,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? route;
}

class WhatsNew {
  static const _prefKey = 'whats_new_seen_version';

  static Future<bool> shouldShow() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_prefKey) != WhatsNewCatalog.releaseVersion;
    } catch (_) {
      return false;
    }
  }

  static Future<void> markSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, WhatsNewCatalog.releaseVersion);
    } catch (_) {}
  }

  static Future<void> maybeShow(BuildContext context) async {
    if (!context.mounted) return;
    if (!await shouldShow()) return;
    if (!context.mounted) return;
    await show(context);
  }

  static Future<void> show(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => const WhatsNewSheet(),
    );
    await markSeen();
  }
}

class WhatsNewSheet extends StatelessWidget {
  const WhatsNewSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Yenilikler · ${WhatsNewCatalog.releaseVersion}',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'KampüsteyimAPP bu sürümde neler getirdi',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            ...WhatsNewCatalog.items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: AppColors.navy.withValues(alpha: 0.08),
                      child: Icon(item.icon, size: 18, color: AppColors.navy),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 2),
                          Text(item.body),
                          if (item.route != null)
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                                context.push(item.route!);
                              },
                              child: const Text('Aç'),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Tamam'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ana kabukta bir kez yenilikleri açar.
class WhatsNewHost extends StatefulWidget {
  const WhatsNewHost({super.key, required this.child});

  final Widget child;

  @override
  State<WhatsNewHost> createState() => _WhatsNewHostState();
}

class _WhatsNewHostState extends State<WhatsNewHost> {
  bool _scheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) WhatsNew.maybeShow(context);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
