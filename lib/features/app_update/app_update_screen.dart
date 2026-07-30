import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_circle_logo.dart';
import 'app_update_provider.dart';

/// Zorunlu güncelleme — bakım ekranı gibi uygulamayı kilitler.
class AppUpdateForceScreen extends StatelessWidget {
  const AppUpdateForceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final upd = context.watch<AppUpdateProvider>();
    final g = upd.gate;
    return Scaffold(
      backgroundColor: AppColors.navy,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              const Center(
                child: AppCircleLogo(logo: AppLogo.mt, size: 88, showBorder: false),
              ),
              const SizedBox(height: 28),
              Text(
                g.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 26,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                g.message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.78),
                  height: 1.45,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                ),
                child: Column(
                  children: [
                    _verRow('Senin sürümün', upd.localVersion ?? g.currentVersion),
                    if (g.storeVersion.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _verRow('Mağaza sürümü', g.storeVersion),
                    ],
                    if (g.minVersion.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _verRow('Zorunlu minimum', g.minVersion),
                    ],
                  ],
                ),
              ),
              const Spacer(),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.cyan,
                  foregroundColor: AppColors.navy,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () => upd.openStore(),
                child: const Text(
                  'Mağazadan güncelle',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: upd.loading ? null : () => upd.check(refresh: true),
                child: Text(
                  'Tekrar kontrol et',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.75)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _verRow(String label, String value) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 13,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.cyan,
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}

/// Soft güncelleme — kapatılabilir alt kart.
class AppUpdateSoftBanner extends StatelessWidget {
  const AppUpdateSoftBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final upd = context.watch<AppUpdateProvider>();
    if (!upd.showSoftBanner) return const SizedBox.shrink();
    final g = upd.gate;
    return Material(
      color: AppColors.navy,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.system_update_alt, color: AppColors.cyan, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      g.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      g.storeVersion.isNotEmpty
                          ? 'Yeni sürüm: ${g.storeVersion}. Mağazadan güncelleyebilirsin.'
                          : g.message,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => upd.openStore(),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.cyan,
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            'Güncelle',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 12),
                        TextButton(
                          onPressed: () => upd.dismissSoft(),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white70,
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('Sonra'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Kapat',
                onPressed: () => upd.dismissSoft(),
                icon: const Icon(Icons.close, color: Colors.white70, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
