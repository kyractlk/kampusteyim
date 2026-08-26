import 'package:flutter/material.dart';

/// KampüsteyimAPP marka renkleri + kampüs paleti.
class AppColors {
  AppColors._();

  static const brandPurple = Color(0xFF2D1B4E);
  static const brandCyan = Color(0xFF00D4C8);

  static const navy = Color(0xFF0B1F3A);
  static const navySoft = Color(0xFF163356);
  static const crimson = Color(0xFFC8102E);
  static const cyan = brandCyan;
  static const lime = Color(0xFF89C741);
  static const gold = Color(0xFFD9B31E);

  static const background = Color(0xFFF7F9FC);
  static const surface = Color(0xFFFFFFFF);
  /// Feed / önerilenler ortak yumuşak zemin — soğuk “çimento” gri değil.
  static const surfaceMuted = Color(0xFFF2F5FA);
  static const textPrimary = Color(0xFF0B1F3A);
  static const textSecondary = Color(0xFF5A6A7C);
  static const border = Color(0xFFE2E8F0);
  static const success = lime;
  static const warning = gold;
  static const error = crimson;
}
