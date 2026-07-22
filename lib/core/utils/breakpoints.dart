import 'package:flutter/material.dart';

/// Ortak responsive kırılımlar — mobil ≠ PC (Twitter-benzeri).
class AppBreakpoints {
  AppBreakpoints._();

  /// 3 kolon shell
  static const double wide = 900;

  /// Sol rail etiketleri açılır
  static const double railLabels = 1100;

  static const double feedMax = 600;
  static const double railWidth = 72;
  static const double railExpanded = 240;
  static const double sidebarWidth = 320;
  static const double shellMax = 1280;

  static bool isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= wide;

  static bool isDesktop(BuildContext context) => isWide(context);

  /// Geniş ekranda ikon+metin rail (Twitter expanded)
  static bool showRailLabels(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= railLabels;
}
