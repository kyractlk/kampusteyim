import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../constants/app_assets.dart';
import '../theme/app_colors.dart';
import 'app_circle_logo.dart';

/// AYS markası — logo ortada, "bir AYS ürünüdür" ifadesi.
class AysProductBadge extends StatelessWidget {
  const AysProductBadge({
    super.key,
    this.logoSize = 26,
    this.opacity = 0.62,
    this.compact = false,
  });

  final double logoSize;
  final double opacity;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppColors.textSecondary,
          fontSize: compact ? 11 : 12,
          letterSpacing: 0.15,
        );
    return Opacity(
      opacity: opacity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppCircleLogo(
            logo: AppLogo.ays,
            size: logoSize,
            showBorder: false,
          ),
          SizedBox(height: compact ? 5 : 7),
          Text.rich(
            TextSpan(
              style: base,
              children: [
                const TextSpan(text: 'bir '),
                TextSpan(
                  text: 'AYS',
                  style: base?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: AppColors.navy,
                    letterSpacing: 0.6,
                  ),
                ),
                const TextSpan(text: ' ürünüdür'),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

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
          AysProductBadge(compact: compact, logoSize: 22)
              .animate()
              .fadeIn(delay: 280.ms),
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
