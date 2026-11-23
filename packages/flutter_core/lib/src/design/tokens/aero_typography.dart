import 'package:flutter/material.dart';
import 'aero_colors.dart';

/// Aero Typography system — NotoSansArabic font pairing
TextStyle aeroText({
  double size = 14,
  FontWeight weight = FontWeight.w400,
  Color color = AeroColors.textPrimary,
  double? height,
  double? letterSpacing,
}) => TextStyle(
  fontFamily: 'NotoSansArabic',
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: height,
  letterSpacing: letterSpacing,
);
