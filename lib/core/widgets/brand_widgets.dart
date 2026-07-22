import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../constants/app_assets.dart';
import '../theme/app_colors.dart';
import 'app_circle_logo.dart';

class BrandHeader extends StatelessWidget {
  const BrandHeader({
    super.key,
    this.showAys = true,
    this.compact = false,
  });

  final bool showAys;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final wideH = compact ? 88.0 : 120.0;
    return Column(
      children: [
        Image.asset(
          AppAssets.kampusWideLogo,
          height: wideH,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        )
            .animate()
            .fadeIn(duration: 450.ms)
            .scale(
              begin: const Offset(0.92, 0.92),
              curve: Curves.easeOutBack,
            ),
        const SizedBox(height: 8),
        Text(
          'Kampüsün sosyal ağı',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
        ).animate().fadeIn(delay: 180.ms),
        if (showAys) ...[
          const SizedBox(height: 14),
          Opacity(
            opacity: 0.55,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Altyapı',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
                const SizedBox(width: 6),
                const AppCircleLogo(
                  logo: AppLogo.ays,
                  size: 20,
                  showBorder: false,
                ),
              ],
            ),
          ).animate().fadeIn(delay: 280.ms),
        ],
      ],
    );
  }
}

class GradientScaffold extends StatelessWidget {
  const GradientScaffold({
    super.key,
    required this.child,
    this.appBar,
    this.floatingActionButton,
    this.bottomNavigationBar,
  });

  final Widget child;
  final PreferredSizeWidget? appBar;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFEDE8F5),
              AppColors.background,
            ],
          ),
        ),
        child: child,
      ),
    );
  }
}

class AppPrimaryButton extends StatelessWidget {
  const AppPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: loading ? null : onPressed,
      child: loading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: Colors.white,
              ),
            )
          : Text(label),
    );
  }
}
