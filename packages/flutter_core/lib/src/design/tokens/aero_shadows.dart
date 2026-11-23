import 'package:flutter/material.dart';
import 'aero_colors.dart';

/// Aero Elevation System — Multi-layer diffuse ambient + crisp contact shadows
abstract class AeroShadows {
  /// Base subtle card elevation (ambient + contact)
  static final List<BoxShadow> card = [
    BoxShadow(
      color: const Color(0xFF074577).withValues(alpha: 0.05),
      blurRadius: 18,
      spreadRadius: 0,
      offset: const Offset(0, 8),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.03),
      blurRadius: 6,
      spreadRadius: 0,
      offset: const Offset(0, 2),
    ),
  ];

  /// Hero Card & Smart CTA Elevation
  static final List<BoxShadow> hero = [
    BoxShadow(
      color: AeroColors.accentTeal.withValues(alpha: 0.22),
      blurRadius: 26,
      spreadRadius: -4,
      offset: const Offset(0, 12),
    ),
    BoxShadow(
      color: AeroColors.primaryNavy.withValues(alpha: 0.12),
      blurRadius: 14,
      spreadRadius: 0,
      offset: const Offset(0, 4),
    ),
  ];

  /// Floating Dock Navigation Elevation
  static final List<BoxShadow> floatingDock = [
    BoxShadow(
      color: AeroColors.primaryNavy.withValues(alpha: 0.10),
      blurRadius: 32,
      spreadRadius: -2,
      offset: const Offset(0, 10),
    ),
    BoxShadow(
      color: AeroColors.accentTeal.withValues(alpha: 0.08),
      blurRadius: 12,
      spreadRadius: 0,
      offset: const Offset(0, 2),
    ),
  ];

  /// Deep Navy Offer Insistent Glowing Halo
  static final List<BoxShadow> deepNavyHalo = [
    BoxShadow(
      color: AeroColors.accentTeal.withValues(alpha: 0.35),
      blurRadius: 40,
      spreadRadius: 6,
      offset: const Offset(0, 0),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.30),
      blurRadius: 20,
      spreadRadius: 0,
      offset: const Offset(0, 10),
    ),
  ];
}
