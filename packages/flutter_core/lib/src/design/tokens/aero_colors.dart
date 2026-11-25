import 'package:flutter/material.dart';

/// Tamreedy Design System 2.0 (Aero Evolution) — Legacy static color aliases.
/// Prefer `context.tamColors` for theme-aware Light/Dark semantic colors.
abstract class AeroColors {
  // Brand Anchors
  static const Color primaryNavy = Color(0xFF0F172A);
  static const Color primaryDark = Color(0xFF115E59);
  static const Color accentTeal = Color(0xFF0D9488);
  static const Color secondarySky = Color(0xFF0EA5E9);
  static const Color deepNavyOffer = Color(0xFF0B1220);

  // Surfaces & Canvas
  static const Color lightCanvas = Color(0xFFF8FAFC);
  static const Color aeroTint = Color(0xFFCCFBF1);
  static const Color aeroTintLight = Color(0xFFF0FDFA);
  static const Color surfaceWhite = Colors.white;

  // Frosted Glass Tints (restrained for calm healthcare UI)
  static final Color glassLight = Colors.white.withValues(alpha: 0.94);
  static final Color glassElevated = const Color(0xFFF1F5F9).withValues(alpha: 0.96);
  static final Color glassTealTint = const Color(0xFF0D9488).withValues(alpha: 0.08);
  static final Color glassNavyTint = const Color(0xFF0F172A).withValues(alpha: 0.05);

  // Borders & Glows
  static final Color borderLight = const Color(0xFFE2E8F0);
  static final Color borderGlow = const Color(0xFF0D9488).withValues(alpha: 0.38);
  static final Color borderCard = const Color(0xFFE2E8F0);
  static const Color borderSubtle = Color(0xFFCBD5E1);

  // Typography
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textMuted = Color(0xFF94A3B8);

  // Semantic
  static const Color success = Color(0xFF16A34A);
  static const Color danger = Color(0xFFDC2626);
  static const Color warning = Color(0xFFD97706);
  static const Color info = Color(0xFF0EA5E9);
}
