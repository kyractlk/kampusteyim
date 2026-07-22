import 'package:flutter/material.dart';

import '../constants/app_assets.dart';
import '../theme/app_colors.dart';

enum AppLogo { gaun, mt, ays }

/// Aynı boyutta, kesin daire kırpımlı logo.
class AppCircleLogo extends StatelessWidget {
  const AppCircleLogo({
    super.key,
    required this.logo,
    this.size = 48,
    this.showBorder = true,
  });

  final AppLogo logo;
  final double size;
  final bool showBorder;

  String get _asset => switch (logo) {
        AppLogo.gaun => AppAssets.gaunLogo,
        AppLogo.mt => AppAssets.mtLogo,
        AppLogo.ays => AppAssets.aysLogo,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: showBorder
            ? Border.all(
                color: AppColors.border.withValues(alpha: 0.9),
                width: 1.2,
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.10),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipOval(
        clipBehavior: Clip.antiAliasWithSaveLayer,
        child: Image.asset(
          _asset,
          width: size,
          height: size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
          gaplessPlayback: true,
        ),
      ),
    );
  }
}
