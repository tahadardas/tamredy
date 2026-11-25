import 'package:flutter/material.dart';
import 'design/tokens/tam_tokens.dart';

/// Shared design tokens for the patient and nurse apps.
class TamreedyColors {
  static const navy = Color(0xFF0F172A);
  static const deepNavy = Color(0xFF0B1220);
  static const teal = Color(0xFF0F766E);
  static const tealAccent = Color(0xFF0D9488);
  static const tealAlt = Color(0xFF115E59);
  static const secondary = Color(0xFF0EA5E9);
  static const background = Color(0xFFFFFFFF);
  static const canvas = Color(0xFFF8FAFC);
  static const text = Color(0xFF0F172A);
  static const subtext = Color(0xFF64748B);
  static const border = Color(0xFFE2E8F0);
  static const success = Color(0xFF16A34A);
  static const warning = Color(0xFFD97706);
  static const danger = Color(0xFFDC2626);

  // Tinted surfaces used by icon boxes, chips and notices.
  static const tealTint = Color(0xFFCCFBF1);
  static const blueTint = Color(0xFFE0F2FE);
  static const orangeTint = Color(0xFFFEF3C7);
  static const warningTint = Color(0xFFFEF3C7);
  static const dangerTint = Color(0xFFFEE2E2);
  static const mapBase = Color(0xFFE2E8F0);
}

class TamreedyRadii {
  static const double card = 20;
  static const double button = 16;
}

const String kFontFamily = 'NotoSansArabic';
const String kFontPackage = 'tamreedy_core';

TextStyle tamText({
  double size = 14,
  FontWeight weight = FontWeight.w400,
  Color color = TamreedyColors.text,
  double? height,
}) => TextStyle(
  fontFamily: kFontFamily,
  package: kFontPackage,
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: height,
);

ThemeData tamreedyLightTheme() => _buildTheme(TamThemeColors.light);

ThemeData tamreedyDarkTheme() => _buildTheme(TamThemeColors.dark);

ThemeData tamreedyTheme() => tamreedyLightTheme();

ThemeData _buildTheme(TamThemeColors c) {
  final brightness = c.isDark ? Brightness.dark : Brightness.light;
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: kFontFamily,
    package: kFontPackage,
    scaffoldBackgroundColor: c.background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: c.primary,
      brightness: brightness,
      primary: c.primary,
      secondary: c.secondary,
      surface: c.surface,
      error: c.danger,
    ),
    extensions: [c],
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      fontFamily: kFontFamily,
      package: kFontPackage,
      bodyColor: c.textPrimary,
      displayColor: c.textPrimary,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: c.surface,
      foregroundColor: c.textPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: tamText(
        size: 18,
        weight: FontWeight.w700,
        color: c.textPrimary,
      ),
    ),
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: c.border),
      ),
    ),
    dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.isDark ? c.surfaceElevated : c.textPrimary,
      contentTextStyle: tamText(color: Colors.white, size: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: InputBorder.none,
      isDense: true,
    ),
  );
}
