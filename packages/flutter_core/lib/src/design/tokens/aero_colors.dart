import 'package:flutter/material.dart';

/// Unified color tokens aligned with Tamreedy Signature 3.0.
class AeroColors {
  static const Color primaryNavy = Color(0xFF163B45);
  static const Color deepNavy = Color(0xFF0A1419);
  static const Color accentTeal = Color(0xFF007F78);
  static const Color accentTealDark = Color(0xFF005F59);
  static const Color accentTealLight = Color(0xFF009B92);
  static const Color secondary = Color(0xFF0EA5E9);

  static const Color lightCanvas = Color(0xFFF6F8FA);
  static const Color surfaceWhite = Color(0xFFFFFFFF);
  static const Color aeroTint = Color(0xFFE0F5F1);
  static const Color aeroTintLight = Color(0xFFF0FAF8);

  static const Color textPrimary = Color(0xFF122B34);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textMuted = Color(0xFF94A3B8);

  static const Color success = Color(0xFF15803D);
  static const Color successLight = Color(0xFFDCFCE7);
  static const Color warning = Color(0xFFB45309);
  static const Color warningLight = Color(0xFFFEF3C7);
  static const Color danger = Color(0xFFDC2626);
  static const Color dangerLight = Color(0xFFFEE2E2);
  static const Color info = Color(0xFF0EA5E9);
  static const Color infoLight = Color(0xFFE0F2FE);

  static const Color borderLight = Color(0xFFE2E8F0);
  static const Color borderSubtle = Color(0xFFCBD5E1);
  static const Color glassLight = Color(0xCCFFFFFF);
  static const Color glassBorder = Color(0xB3FFFFFF);
  static const Color glassShadow = Color(0x14122B34);

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF007F78), Color(0xFF005F59)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient navyGradient = LinearGradient(
    colors: [Color(0xFF163B45), Color(0xFF005F59)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
