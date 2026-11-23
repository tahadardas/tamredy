import 'dart:ui';
import 'package:flutter/material.dart';
import '../tokens/aero_colors.dart';
import '../tokens/aero_motion_tokens.dart';
import '../tokens/aero_radii.dart';
import '../tokens/aero_shadows.dart';

/// AeroGlassCard — Frosted glass container with multi-layer diffuse elevation,
/// illuminated gradient border, and optional spring micro-interaction on tap.
class AeroGlassCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final double borderRadius;
  final Color? tintColor;
  final double blurSigma;
  final VoidCallback? onTap;
  final List<BoxShadow>? customShadow;
  final Border? customBorder;

  const AeroGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.margin,
    this.width,
    this.height,
    this.borderRadius = AeroRadii.mainCard,
    this.tintColor,
    this.blurSigma = 12.0,
    this.onTap,
    this.customShadow,
    this.customBorder,
  });

  @override
  State<AeroGlassCard> createState() => _AeroGlassCardState();
}

class _AeroGlassCardState extends State<AeroGlassCard> with SingleTickerProviderStateMixin {
  late final AnimationController _pressController;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: AeroMotionTokens.pressDuration,
      reverseDuration: AeroMotionTokens.buttonDuration,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.985).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    if (widget.onTap != null) _pressController.forward();
  }

  void _onTapUp(TapUpDetails _) {
    if (widget.onTap != null) _pressController.reverse();
  }

  void _onTapCancel() {
    if (widget.onTap != null) _pressController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(widget.borderRadius);
    final fill = widget.tintColor ?? AeroColors.glassLight;

    Widget cardBody = Container(
      width: widget.width,
      height: widget.height,
      margin: widget.margin,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: widget.customShadow ?? AeroShadows.card,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: widget.blurSigma, sigmaY: widget.blurSigma),
          child: Container(
            padding: widget.padding,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: radius,
              border: widget.customBorder ??
                  Border.all(
                    color: AeroColors.borderLight,
                    width: 1.2,
                  ),
            ),
            child: widget.child,
          ),
        ),
      ),
    );

    if (widget.onTap != null) {
      cardBody = GestureDetector(
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: _onTapCancel,
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: cardBody,
        ),
      );
    }

    return cardBody;
  }
}
