import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/app_colors.dart';
import '../theme/theme_provider.dart';

/// Apple Liquid Glass yüzey — blur + speküler kenar + yumuşak gölge.
class LiquidGlass extends StatelessWidget {
  const LiquidGlass({
    super.key,
    required this.child,
    this.borderRadius = 28,
    this.padding,
    this.blur = 36,
    this.tint,
    this.borderOpacity,
    this.dark = false,
    this.intensity = 1,
  });

  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final double blur;
  final Color? tint;
  final double? borderOpacity;
  final bool dark;
  final double intensity;

  static bool enabled(BuildContext context) {
    try {
      return context.watch<ThemeProvider>().isLiquidGlass;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final i = intensity.clamp(0.5, 1.5);
    final fill = tint ??
        (dark
            ? Colors.white.withValues(alpha: 0.12 * i)
            : Colors.white.withValues(alpha: 0.52 * i));
    final border = Colors.white.withValues(
      alpha: borderOpacity ?? (dark ? 0.34 : 0.78),
    );
    final r = BorderRadius.circular(borderRadius);

    // Gölge ClipRRect dışında kalsın — cam “havada” dursun.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.55 : 0.18),
            blurRadius: dark ? 36 : 28,
            offset: const Offset(0, 14),
            spreadRadius: -2,
          ),
          if (dark)
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, -2),
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: r,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: dark
                    ? [
                        Colors.white.withValues(alpha: 0.28 * i.clamp(0.8, 1.2)),
                        fill,
                        Colors.black.withValues(alpha: 0.32),
                      ]
                    : [
                        Colors.white.withValues(alpha: 0.92),
                        fill,
                        const Color(0x72C8DCEF),
                      ],
                stops: const [0.0, 0.45, 1.0],
              ),
              border: Border.all(color: border, width: 1.15),
            ),
            child: Stack(
              fit: StackFit.passthrough,
              children: [
                // Speküler üst çizgi
                Positioned(
                  left: 16,
                  right: 16,
                  top: 0.8,
                  child: IgnorePointer(
                    child: Container(
                      height: 1.6,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0),
                            Colors.white.withValues(alpha: dark ? 0.62 : 0.98),
                            Colors.white.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // Sol üst soft highlight
                Positioned(
                  left: -8,
                  top: -12,
                  child: IgnorePointer(
                    child: Container(
                      width: 72,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          colors: [
                            Colors.white.withValues(alpha: dark ? 0.18 : 0.35),
                            Colors.white.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: padding ?? EdgeInsets.zero,
                  child: child,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

ButtonStyle liquidFilledButtonStyle({
  required bool dark,
  Size? minimumSize,
}) {
  return FilledButton.styleFrom(
    backgroundColor: dark
        ? Colors.white.withValues(alpha: 0.20)
        : AppColors.navy.withValues(alpha: 0.86),
    foregroundColor: Colors.white,
    elevation: 0,
    shadowColor: Colors.transparent,
    minimumSize: minimumSize ?? const Size(64, 44),
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
      side: BorderSide(
        color: Colors.white.withValues(alpha: dark ? 0.32 : 0.40),
      ),
    ),
  );
}

ButtonStyle liquidOutlinedButtonStyle({
  required bool dark,
  Size? minimumSize,
  EdgeInsetsGeometry? padding,
  MaterialTapTargetSize? tapTargetSize,
}) {
  return OutlinedButton.styleFrom(
    foregroundColor: dark ? Colors.white : AppColors.navy,
    backgroundColor: dark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.white.withValues(alpha: 0.42),
    side: BorderSide(
      color: Colors.white.withValues(alpha: dark ? 0.42 : 0.62),
      width: 1.1,
    ),
    minimumSize: minimumSize,
    padding: padding,
    tapTargetSize: tapTargetSize,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
  );
}

/// Reels yan aksiyon (beğeni / yorum / ses) için cam daire.
class LiquidGlassIconButton extends StatelessWidget {
  const LiquidGlassIconButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.color = Colors.white,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final glass = LiquidGlass.enabled(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: glass
                ? LiquidGlass(
                    dark: true,
                    blur: 22,
                    borderRadius: 22,
                    intensity: 1.15,
                    borderOpacity: 0.32,
                    padding: const EdgeInsets.all(9),
                    child: Icon(icon, color: color, size: 22),
                  )
                : Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(icon, color: color, size: 26),
                  ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: glass ? 0.88 : 0.7),
            fontSize: 11,
            height: 1.05,
            fontWeight: glass ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    );
  }
}
