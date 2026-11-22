import 'package:flutter/material.dart';

/// Design tokens, mirrored from `reference_design/design_tokens.json`.
class TamreedyColors {
  static const navy = Color(0xFF074577);
  static const deepNavy = Color(0xFF073F6C);
  static const teal = Color(0xFF079D90);
  static const tealAlt = Color(0xFF08A996);
  static const background = Color(0xFFFFFFFF);
  static const canvas = Color(0xFFF7FAFC);
  static const text = Color(0xFF11395C);
  static const subtext = Color(0xFF7891A3);
  static const border = Color(0xFFE4EDF2);
  static const success = Color(0xFF05866B);
  static const warning = Color(0xFFB97824);
  static const danger = Color(0xFFCF5361);

  // Tinted surfaces used by icon boxes, chips and notices.
  static const tealTint = Color(0xFFE3F5F1);
  static const blueTint = Color(0xFFE6F0FB);
  static const orangeTint = Color(0xFFFDEEE2);
  static const warningTint = Color(0xFFFFF3E6);
  static const dangerTint = Color(0xFFFCE9EB);
  static const mapBase = Color(0xFFE8F1EE);
}

class TamreedyRadii {
  static const double card = 16;
  static const double button = 13;
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

ThemeData tamreedyTheme() {
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: kFontFamily,
    package: kFontPackage,
    scaffoldBackgroundColor: TamreedyColors.canvas,
    colorScheme: ColorScheme.fromSeed(
      seedColor: TamreedyColors.teal,
      primary: TamreedyColors.teal,
      secondary: TamreedyColors.navy,
      surface: Colors.white,
    ),
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      fontFamily: kFontFamily,
      package: kFontPackage,
      bodyColor: TamreedyColors.text,
      displayColor: TamreedyColors.text,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: TamreedyColors.navy,
      elevation: 0,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: TamreedyColors.navy,
      contentTextStyle: tamText(color: Colors.white, size: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: InputBorder.none,
      isDense: true,
    ),
  );
}
