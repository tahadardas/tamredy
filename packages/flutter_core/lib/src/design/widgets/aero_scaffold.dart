import 'dart:ui';
import 'package:flutter/material.dart';
import '../tokens/aero_colors.dart';
import '../tokens/aero_radii.dart';
import '../tokens/aero_typography.dart';

/// AeroScaffold — Medical Aero Premium canvas and structure.
/// Provides soft clinical gradient backdrop, frosted glass App Bar,
/// and integrated slot for the Floating Aero Dock.
class AeroScaffold extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final Widget? body;
  final List<Widget>? children;
  final Widget? leading;
  final List<Widget>? actions;
  final bool showBack;
  final VoidCallback? onBack;
  final Future<void> Function()? onRefresh;
  final Widget? floatingDock;
  final Widget? floatingCta;
  final EdgeInsetsGeometry padding;
  final bool extendBody;
  final Widget? bottomSheet;

  const AeroScaffold({
    super.key,
    this.title,
    this.subtitle,
    this.body,
    this.children,
    this.leading,
    this.actions,
    this.showBack = false,
    this.onBack,
    this.onRefresh,
    this.floatingDock,
    this.floatingCta,
    this.padding = const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
    this.extendBody = true,
    this.bottomSheet,
  });

  @override
  Widget build(BuildContext context) {
    final hasAppBar = title != null || leading != null || showBack || (actions != null && actions!.isNotEmpty);

    Widget content;
    if (children != null) {
      content = ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: padding.add(
          EdgeInsets.only(
            top: hasAppBar ? 8 : 16,
            bottom: floatingDock != null ? 100 : 28,
          ),
        ),
        children: children!,
      );
    } else {
      content = Padding(
        padding: padding.add(
          EdgeInsets.only(
            top: hasAppBar ? 8 : 16,
            bottom: floatingDock != null ? 100 : 28,
          ),
        ),
        child: body ?? const SizedBox.shrink(),
      );
    }

    if (onRefresh != null) {
      content = RefreshIndicator(
        onRefresh: onRefresh!,
        color: AeroColors.accentTeal,
        backgroundColor: Colors.white,
        child: content,
      );
    }

    return Scaffold(
      backgroundColor: AeroColors.lightCanvas,
      extendBody: extendBody,
      bottomSheet: bottomSheet,
      body: Stack(
        children: [
          // Background soft clinical atmosphere gradient
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFFF7FCFE),
                    Color(0xFFEBF7F9),
                    Color(0xFFF3F8FB),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.0, 0.45, 1.0],
                ),
              ),
            ),
          ),

          // Subtle ambient glow orbs in the background
          Positioned(
            top: -60,
            right: -40,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AeroColors.accentTeal.withValues(alpha: 0.08),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                child: const SizedBox.shrink(),
              ),
            ),
          ),
          Positioned(
            top: 260,
            left: -80,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AeroColors.primaryNavy.withValues(alpha: 0.05),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
                child: const SizedBox.shrink(),
              ),
            ),
          ),

          // Main Content
          Positioned.fill(
            child: SafeArea(
              top: !hasAppBar,
              bottom: false,
              child: content,
            ),
          ),

          // Frosted Glass Top Bar
          if (hasAppBar)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildFrostedTopBar(context),
            ),

          // Smart CTA Layer
          if (floatingCta != null)
            Positioned(
              left: 18,
              right: 18,
              bottom: floatingDock != null ? 86 : 24,
              child: floatingCta!,
            ),

          // Floating Aero Dock
          if (floatingDock != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: floatingDock!,
            ),
        ],
      ),
    );
  }

  Widget _buildFrostedTopBar(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: EdgeInsets.only(
            top: topPadding + 6,
            bottom: 12,
            left: 16,
            right: 16,
          ),
          decoration: BoxDecoration(
            color: AeroColors.glassLight,
            border: Border(
              bottom: BorderSide(
                color: AeroColors.borderLight,
                width: 1.0,
              ),
            ),
          ),
          child: Row(
            children: [
              if (showBack)
                _buildCircularGlassButton(
                  icon: Icons.arrow_back_rounded,
                  onTap: onBack ?? () => Navigator.of(context).maybePop(),
                )
              else if (leading != null)
                leading!,
              if (showBack || leading != null) const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (title != null)
                      Text(
                        title!,
                        style: aeroText(
                          size: 19,
                          weight: FontWeight.w700,
                          color: AeroColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle!,
                          style: aeroText(
                            size: 12.5,
                            weight: FontWeight.w500,
                            color: AeroColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              if (actions != null) ...actions!,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCircularGlassButton({required IconData icon, required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AeroRadii.dock),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.8),
            shape: BoxShape.circle,
            border: Border.all(color: AeroColors.borderLight, width: 1),
          ),
          child: Icon(icon, size: 16, color: AeroColors.primaryNavy),
        ),
      ),
    );
  }
}
