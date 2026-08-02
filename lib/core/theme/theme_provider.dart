import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Uygulama görünüm stili — profil ayarlarından seçilir.
enum AppVisualStyle {
  classic,
  liquidGlass,
}

extension AppVisualStyleX on AppVisualStyle {
  String get label => switch (this) {
        AppVisualStyle.classic => 'Klasik',
        AppVisualStyle.liquidGlass => 'Liquid Glass',
      };

  String get subtitle => switch (this) {
        AppVisualStyle.classic => 'Açık kampüs teması',
        AppVisualStyle.liquidGlass => 'Buğulu şeffaf cam · Dynamic Island',
      };

  String get storageKey => name;

  static AppVisualStyle fromKey(String? raw) {
    // Eski "dark" tercihi kaldırıldı → Liquid’e düş.
    if (raw == 'dark') return AppVisualStyle.liquidGlass;
    for (final v in AppVisualStyle.values) {
      if (v.name == raw) return v;
    }
    return AppVisualStyle.liquidGlass;
  }
}

class ThemeProvider extends ChangeNotifier {
  ThemeProvider() {
    _load();
  }

  static const _prefsKey = 'mt_visual_style_v1';

  AppVisualStyle _style = AppVisualStyle.liquidGlass;
  bool _ready = false;

  AppVisualStyle get style => _style;
  bool get ready => _ready;
  bool get isLiquidGlass => _style == AppVisualStyle.liquidGlass;

  ThemeMode get themeMode => ThemeMode.light;

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      _style = AppVisualStyleX.fromKey(raw);
      // Eski koyu tema kaydını temizle.
      if (raw == 'dark') {
        await prefs.setString(_prefsKey, _style.storageKey);
      }
    } catch (e) {
      debugPrint('[theme] load: $e');
    }
    _ready = true;
    notifyListeners();
  }

  Future<void> setStyle(AppVisualStyle next) async {
    if (_style == next) return;
    _style = next;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, next.storageKey);
    } catch (e) {
      debugPrint('[theme] save: $e');
    }
  }
}
