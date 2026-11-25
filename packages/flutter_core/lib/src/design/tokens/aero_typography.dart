import 'package:flutter/material.dart';
import 'aero_colors.dart';

/// Tamreedy Typography system — NotoSansArabic font pairing
TextStyle aeroText({
  double size = 14,
  FontWeight weight = FontWeight.w400,
  Color color = AeroColors.textPrimary,
  double? height,
  double? letterSpacing,
  List<FontFeature>? fontFeatures,
}) => TextStyle(
  fontFamily: 'NotoSansArabic',
  package: 'tamreedy_core',
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: height,
  letterSpacing: letterSpacing,
  fontFeatures: fontFeatures,
);

/// Medical Premium 2.0 Typography Scale (Flutter logical pixels).
abstract class TamTypography {
  static TextStyle heroTitle({Color color = AeroColors.textPrimary}) =>
      aeroText(size: 28, weight: FontWeight.w800, color: color, height: 1.25);

  static TextStyle pageTitle({Color color = AeroColors.textPrimary}) =>
      aeroText(size: 24, weight: FontWeight.w800, color: color, height: 1.3);

  static TextStyle sectionTitle({Color color = AeroColors.textPrimary}) =>
      aeroText(size: 18, weight: FontWeight.w700, color: color, height: 1.35);

  static TextStyle cardTitle({Color color = AeroColors.textPrimary}) =>
      aeroText(size: 16, weight: FontWeight.w700, color: color, height: 1.4);

  static TextStyle body({
    Color color = AeroColors.textPrimary,
    FontWeight weight = FontWeight.w400,
  }) =>
      aeroText(size: 15, weight: weight, color: color, height: 1.55);

  static TextStyle supporting({
    Color color = AeroColors.textSecondary,
    FontWeight weight = FontWeight.w500,
  }) =>
      aeroText(size: 13, weight: weight, color: color, height: 1.45);

  static TextStyle financialAmount({
    Color color = AeroColors.textPrimary,
    double size = 30,
  }) =>
      aeroText(
        size: size,
        weight: FontWeight.w800,
        color: color,
        height: 1.2,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}

/// Optional app-wide UI text scale multiplier for Senior / Low-Vision accessibility.
final ValueNotifier<double> tamUiScale = ValueNotifier<double>(1.0);

/// Wraps a subtree with both system text scaling and optional [tamUiScale].
class TamScaledTextScope extends StatelessWidget {
  final Widget child;
  const TamScaledTextScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: tamUiScale,
      builder: (context, extraScale, _) {
        final mq = MediaQuery.of(context);
        final currentScale = mq.textScaler.scale(1.0);
        final effective = (currentScale * extraScale).clamp(1.0, 2.2);
        return MediaQuery(
          data: mq.copyWith(textScaler: TextScaler.linear(effective)),
          child: child,
        );
      },
    );
  }
}
