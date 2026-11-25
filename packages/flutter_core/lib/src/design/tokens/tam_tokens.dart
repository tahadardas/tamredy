import 'package:flutter/material.dart';

/// Tamreedy Design System 2.0 — Spacing, Radii, Breakpoints, Motion, Shadows,
/// and Semantic Light/Dark Color Tokens.

abstract class TamSpacing {
  static const double xxs = 2.0;
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0;
  static const double xxl = 24.0;
  static const double xxxl = 32.0;
}

abstract class TamBreakpoints {
  static const double minPhone = 320.0;
  static const double compact = 600.0;
  static const double medium = 1024.0;
  static const double maxContentWidth = 720.0;
  static const double sidebarWidth = 264.0;

  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < compact;

  static bool isMedium(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w >= compact && w < medium;
  }

  static bool isExpanded(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= medium;

  static bool isNarrowPhone(BuildContext context) =>
      MediaQuery.sizeOf(context).width <= 360.0;
}

abstract class TamMotion {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration normal = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 320);

  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeInOutCubicEmphasized;

  /// Returns [Duration.zero] when the user has enabled Reduced Motion.
  static Duration of(BuildContext context, [Duration base = normal]) {
    if (MediaQuery.disableAnimationsOf(context)) return Duration.zero;
    return base;
  }
}

@immutable
class TamThemeColors extends ThemeExtension<TamThemeColors> {
  final Color primary;
  final Color primaryAccent;
  final Color primaryDark;
  final Color primaryTint;
  final Color secondary;
  final Color secondaryTint;
  final Color background;
  final Color surface;
  final Color surfaceElevated;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color border;
  final Color borderStrong;
  final Color success;
  final Color successTint;
  final Color warning;
  final Color warningTint;
  final Color danger;
  final Color dangerTint;
  final Color info;
  final Color infoTint;
  final Color heroStart;
  final Color heroEnd;
  final Color navBackground;
  final bool isDark;

  const TamThemeColors({
    required this.primary,
    required this.primaryAccent,
    required this.primaryDark,
    required this.primaryTint,
    required this.secondary,
    required this.secondaryTint,
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.border,
    required this.borderStrong,
    required this.success,
    required this.successTint,
    required this.warning,
    required this.warningTint,
    required this.danger,
    required this.dangerTint,
    required this.info,
    required this.infoTint,
    required this.heroStart,
    required this.heroEnd,
    required this.navBackground,
    required this.isDark,
  });

  static const light = TamThemeColors(
    primary: Color(0xFF0F766E),
    primaryAccent: Color(0xFF0D9488),
    primaryDark: Color(0xFF115E59),
    primaryTint: Color(0xFFCCFBF1),
    secondary: Color(0xFF0EA5E9),
    secondaryTint: Color(0xFFE0F2FE),
    background: Color(0xFFF8FAFC),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFF1F5F9),
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF64748B),
    textMuted: Color(0xFF94A3B8),
    border: Color(0xFFE2E8F0),
    borderStrong: Color(0xFFCBD5E1),
    success: Color(0xFF16A34A),
    successTint: Color(0xFFDCFCE7),
    warning: Color(0xFFD97706),
    warningTint: Color(0xFFFEF3C7),
    danger: Color(0xFFDC2626),
    dangerTint: Color(0xFFFEE2E2),
    info: Color(0xFF0EA5E9),
    infoTint: Color(0xFFE0F2FE),
    heroStart: Color(0xFF0F172A),
    heroEnd: Color(0xFF115E59),
    navBackground: Color(0xFFFFFFFF),
    isDark: false,
  );

  static const dark = TamThemeColors(
    primary: Color(0xFF14B8A6),
    primaryAccent: Color(0xFF2DD4BF),
    primaryDark: Color(0xFF0D9488),
    primaryTint: Color(0xFF134E4A),
    secondary: Color(0xFF38BDF8),
    secondaryTint: Color(0xFF0C4A6E),
    background: Color(0xFF0B1220),
    surface: Color(0xFF111B2E),
    surfaceElevated: Color(0xFF18253D),
    textPrimary: Color(0xFFF1F5F9),
    textSecondary: Color(0xFF94A3B8),
    textMuted: Color(0xFF64748B),
    border: Color(0xFF1E293B),
    borderStrong: Color(0xFF334155),
    success: Color(0xFF22C55E),
    successTint: Color(0xFF14532D),
    warning: Color(0xFFF59E0B),
    warningTint: Color(0xFF78350F),
    danger: Color(0xFFEF4444),
    dangerTint: Color(0xFF7F1D1D),
    info: Color(0xFF38BDF8),
    infoTint: Color(0xFF0C4A6E),
    heroStart: Color(0xFF0F172A),
    heroEnd: Color(0xFF134E4A),
    navBackground: Color(0xFF111B2E),
    isDark: true,
  );

  List<BoxShadow> get cardShadow => isDark
      ? [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ]
      : [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ];

  List<BoxShadow> get elevatedShadow => isDark
      ? [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.40),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ]
      : [
          BoxShadow(
            color: primary.withValues(alpha: 0.14),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ];

  @override
  TamThemeColors copyWith({
    Color? primary,
    Color? primaryAccent,
    Color? primaryDark,
    Color? primaryTint,
    Color? secondary,
    Color? secondaryTint,
    Color? background,
    Color? surface,
    Color? surfaceElevated,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? border,
    Color? borderStrong,
    Color? success,
    Color? successTint,
    Color? warning,
    Color? warningTint,
    Color? danger,
    Color? dangerTint,
    Color? info,
    Color? infoTint,
    Color? heroStart,
    Color? heroEnd,
    Color? navBackground,
    bool? isDark,
  }) {
    return TamThemeColors(
      primary: primary ?? this.primary,
      primaryAccent: primaryAccent ?? this.primaryAccent,
      primaryDark: primaryDark ?? this.primaryDark,
      primaryTint: primaryTint ?? this.primaryTint,
      secondary: secondary ?? this.secondary,
      secondaryTint: secondaryTint ?? this.secondaryTint,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      success: success ?? this.success,
      successTint: successTint ?? this.successTint,
      warning: warning ?? this.warning,
      warningTint: warningTint ?? this.warningTint,
      danger: danger ?? this.danger,
      dangerTint: dangerTint ?? this.dangerTint,
      info: info ?? this.info,
      infoTint: infoTint ?? this.infoTint,
      heroStart: heroStart ?? this.heroStart,
      heroEnd: heroEnd ?? this.heroEnd,
      navBackground: navBackground ?? this.navBackground,
      isDark: isDark ?? this.isDark,
    );
  }

  @override
  TamThemeColors lerp(ThemeExtension<TamThemeColors>? other, double t) {
    if (other is! TamThemeColors) return this;
    return TamThemeColors(
      primary: Color.lerp(primary, other.primary, t)!,
      primaryAccent: Color.lerp(primaryAccent, other.primaryAccent, t)!,
      primaryDark: Color.lerp(primaryDark, other.primaryDark, t)!,
      primaryTint: Color.lerp(primaryTint, other.primaryTint, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      secondaryTint: Color.lerp(secondaryTint, other.secondaryTint, t)!,
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      success: Color.lerp(success, other.success, t)!,
      successTint: Color.lerp(successTint, other.successTint, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningTint: Color.lerp(warningTint, other.warningTint, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerTint: Color.lerp(dangerTint, other.dangerTint, t)!,
      info: Color.lerp(info, other.info, t)!,
      infoTint: Color.lerp(infoTint, other.infoTint, t)!,
      heroStart: Color.lerp(heroStart, other.heroStart, t)!,
      heroEnd: Color.lerp(heroEnd, other.heroEnd, t)!,
      navBackground: Color.lerp(navBackground, other.navBackground, t)!,
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}

extension TamThemeContext on BuildContext {
  TamThemeColors get tamColors =>
      Theme.of(this).extension<TamThemeColors>() ?? TamThemeColors.light;
}
