import 'package:flutter/material.dart';

/// Aero Signature & Medical Aero Premium Design Tokens — Colors
abstract class AeroColors {
  // Brand Anchors
  static const Color primaryNavy = Color(0xFF074577);
  static const Color accentTeal = Color(0xFF079D90);
  static const Color deepNavyOffer = Color(0xFF102F49);

  // Surfaces & Canvas
  static const Color lightCanvas = Color(0xFFF5FAFD);
  static const Color aeroTint = Color(0xFFDFF4F2);
  static const Color aeroTintLight = Color(0xFFEDFAF9);
  static const Color surfaceWhite = Colors.white;

  // Frosted Glass Tints
  static final Color glassLight = Colors.white.withValues(alpha: 0.85);
  static final Color glassElevated = const Color(0xFFE9F5F8).withValues(alpha: 0.90);
  static final Color glassTealTint = const Color(0xFF079D90).withValues(alpha: 0.08);
  static final Color glassNavyTint = const Color(0xFF074577).withValues(alpha: 0.06);

  // Borders & Glows
  static final Color borderLight = const Color(0xFF079D90).withValues(alpha: 0.16);
  static final Color borderGlow = const Color(0xFF079D90).withValues(alpha: 0.38);
  static final Color borderCard = Colors.white.withValues(alpha: 0.75);
  static final Color borderSubtle = const Color(0xFFD0E3ED);

  // Typography
  static const Color textPrimary = Color(0xFF163B52);
  static const Color textSecondary = Color(0xFF5A7A8E);
  static const Color textMuted = Color(0xFF8BA5B5);

  // Semantic
  static const Color success = Color(0xFF059669);
  static const Color danger = Color(0xFFDC2626);
  static const Color warning = Color(0xFFD97706);
  static const Color info = Color(0xFF2563EB);
}
