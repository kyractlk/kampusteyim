import 'package:flutter/foundation.dart';

/// Ana shell UI (alt menü vb.) — modal/sheet açılınca geçici gizleme.
class ShellChrome {
  ShellChrome._();

  static final ValueNotifier<bool> hideBottomNav = ValueNotifier(false);

  static void setBottomNavHidden(bool hidden) {
    if (hideBottomNav.value == hidden) return;
    hideBottomNav.value = hidden;
  }
}
