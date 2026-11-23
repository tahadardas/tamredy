import 'package:flutter/material.dart';

/// Aero Motion Tokens — Responsive micro-interactions, springs and curves
abstract class AeroMotionTokens {
  // Durations
  static const Duration pressDuration = Duration(milliseconds: 100);
  static const Duration buttonDuration = Duration(milliseconds: 180);
  static const Duration tabDuration = Duration(milliseconds: 220);
  static const Duration cardDuration = Duration(milliseconds: 260);
  static const Duration dialogDuration = Duration(milliseconds: 280);
  static const Duration sheetDuration = Duration(milliseconds: 320);
  static const Duration pageTransition = Duration(milliseconds: 320);
  static const Duration offerReveal = Duration(milliseconds: 280);
  static const Duration splashGlow = Duration(milliseconds: 900);

  // Curves
  static const Curve standardCurve = Curves.easeInOutCubicEmphasized;
  static const Curve easeOut = Curves.easeOutCubic;
  static const Curve springCurve = Curves.easeOutBack;
  static const Curve bounce = Curves.elasticOut;
  static const Curve enter = Curves.decelerate;
}

typedef AeroMotion = AeroMotionTokens;
