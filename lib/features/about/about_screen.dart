import 'package:flutter/material.dart';

import '../../core/constants/app_assets.dart';
import '../../core/constants/app_info.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_circle_logo.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Uygulama bilgisi')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: Image.asset(
              AppAssets.kampusWideLogo,
              height: 140,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppInfo.fullName,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          _row('Geliştirici', AppInfo.developer),
          _row('İmza', AppInfo.author),
          _row('Destek', AppInfo.supportEmail),
          _row('Sürüm', AppInfo.versionLabel),
          const SizedBox(height: 28),
          Opacity(
            opacity: 0.5,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Altyapı',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
                const SizedBox(width: 8),
                const AppCircleLogo(logo: AppLogo.ays, size: 28, showBorder: false),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            AppInfo.copyright,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              k,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}
