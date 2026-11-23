import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../tokens/aero_colors.dart';
import '../tokens/aero_motion_tokens.dart';
import '../tokens/aero_radii.dart';
import '../tokens/aero_shadows.dart';
import '../tokens/aero_typography.dart';

enum AeroButtonVariant {
  primary,
  teal,
  secondary,
  ghost,
  danger,
}

/// AeroButton — Tactile interactive button featuring spring physics,
/// subtle illuminated glow, and haptic feedback.
class AeroButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final AeroButtonVariant variant;
  final Widget? leadingIcon;
  final Widget? trailingIcon;
  final bool isLoading;
  final double? width;
  final double height;
  final double fontSize;
  final EdgeInsetsGeometry padding;

  const AeroButton(
    this.label, {
    super.key,
    required this.onPressed,
    this.variant = AeroButtonVariant.primary,
    this.leadingIcon,
    this.trailingIcon,
    this.isLoading = false,
    this.width,
    this.height = 54,
    this.fontSize = 16,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
  });

  const AeroButton.teal(
    this.label, {
    super.key,
    required this.onPressed,
    this.leadingIcon,
    this.trailingIcon,
    this.isLoading = false,
    this.width,
    this.height = 54,
    this.fontSize = 16,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
  }) : variant = AeroButtonVariant.teal;

  const AeroButton.secondary(
    this.label, {
    super.key,
    required this.onPressed,
    this.leadingIcon,
    this.trailingIcon,
    this.isLoading = false,
    this.width,
    this.height = 52,
    this.fontSize = 15,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
  }) : variant = AeroButtonVariant.secondary;

  const AeroButton.ghost(
    this.label, {
    super.key,
    required this.onPressed,
    this.leadingIcon,
    this.trailingIcon,
    this.isLoading = false,
    this.width,
    this.height = 48,
    this.fontSize = 15,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  }) : variant = AeroButtonVariant.ghost;

  const AeroButton.danger(
    this.label, {
    super.key,
    required this.onPressed,
    this.leadingIcon,
    this.trailingIcon,
    this.isLoading = false,
    this.width,
    this.height = 52,
    this.fontSize = 15,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
  }) : variant = AeroButtonVariant.danger;

  @override
  State<AeroButton> createState() => _AeroButtonState();
}

class _AeroButtonState extends State<AeroButton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AeroMotionTokens.pressDuration,
      reverseDuration: AeroMotionTokens.buttonDuration,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.965).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    if (widget.onPressed != null && !widget.isLoading) {
      _controller.forward();
    }
  }

  void _onTapUp(TapUpDetails _) {
    if (widget.onPressed != null && !widget.isLoading) {
      _controller.reverse();
    }
  }

  void _onTapCancel() {
    if (widget.onPressed != null && !widget.isLoading) {
      _controller.reverse();
    }
  }

  void _handleTap() {
    if (widget.onPressed != null && !widget.isLoading) {
      HapticFeedback.lightImpact();
      widget.onPressed!();
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.isLoading;

    Color textColor;
    Gradient? gradient;
    Color? solidColor;
    Border? border;
    List<BoxShadow>? shadow;

    switch (widget.variant) {
      case AeroButtonVariant.primary:
        textColor = Colors.white;
        gradient = enabled
            ? const LinearGradient(
                colors: [Color(0xFF0A5796), AeroColors.primaryNavy],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              )
            : LinearGradient(
                colors: [
                  AeroColors.primaryNavy.withValues(alpha: 0.4),
                  AeroColors.primaryNavy.withValues(alpha: 0.3),
                ],
              );
        shadow = enabled ? AeroShadows.hero : null;
        border = Border.all(color: Colors.white.withValues(alpha: 0.25), width: 1);
        break;

      case AeroButtonVariant.teal:
        textColor = Colors.white;
        gradient = enabled
            ? const LinearGradient(
                colors: [Color(0xFF0BB3A4), AeroColors.accentTeal],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              )
            : LinearGradient(
                colors: [
                  AeroColors.accentTeal.withValues(alpha: 0.4),
                  AeroColors.accentTeal.withValues(alpha: 0.3),
                ],
              );
        shadow = enabled ? AeroShadows.hero : null;
        border = Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1);
        break;

      case AeroButtonVariant.secondary:
        textColor = enabled ? AeroColors.primaryNavy : AeroColors.textMuted;
        solidColor = enabled ? AeroColors.glassElevated : Colors.white.withValues(alpha: 0.5);
        border = Border.all(
          color: enabled ? AeroColors.borderLight : const Color(0xFFE2E8F0),
          width: 1.2,
        );
        shadow = enabled ? AeroShadows.card : null;
        break;

      case AeroButtonVariant.ghost:
        textColor = enabled ? AeroColors.primaryNavy : AeroColors.textMuted;
        solidColor = Colors.transparent;
        border = null;
        shadow = null;
        break;

      case AeroButtonVariant.danger:
        textColor = Colors.white;
        gradient = enabled
            ? const LinearGradient(
                colors: [Color(0xFFEF4444), AeroColors.danger],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              )
            : null;
        solidColor = enabled ? null : AeroColors.danger.withValues(alpha: 0.3);
        shadow = enabled
            ? [
                BoxShadow(
                  color: AeroColors.danger.withValues(alpha: 0.25),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ]
            : null;
        border = Border.all(color: Colors.white.withValues(alpha: 0.2), width: 1);
        break;
    }

    final content = widget.isLoading
        ? SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(textColor),
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.leadingIcon != null) ...[
                widget.leadingIcon!,
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  widget.label,
                  style: aeroText(
                    size: widget.fontSize,
                    weight: FontWeight.w700,
                    color: textColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              if (widget.trailingIcon != null) ...[
                const SizedBox(width: 8),
                widget.trailingIcon!,
              ],
            ],
          );

    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onTap: enabled ? _handleTap : null,
      behavior: HitTestBehavior.opaque,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          width: widget.width,
          height: widget.height,
          padding: widget.padding,
          decoration: BoxDecoration(
            gradient: gradient,
            color: solidColor,
            borderRadius: BorderRadius.circular(AeroRadii.button),
            border: border,
            boxShadow: shadow,
          ),
          alignment: Alignment.center,
          child: content,
        ),
      ),
    );
  }
}
