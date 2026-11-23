import 'dart:ui';
import 'package:flutter/material.dart';
import '../tokens/aero_colors.dart';
import '../tokens/aero_radii.dart';

/// Shows an Aero frosted glass modal bottom sheet with illuminated border,
/// drag handle, and 28px top radii.
Future<T?> showAeroModalBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool enableDrag = true,
  Color? barrierColor,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    enableDrag: enableDrag,
    backgroundColor: Colors.transparent,
    barrierColor: barrierColor ?? AeroColors.primaryNavy.withValues(alpha: 0.35),
    builder: (ctx) => AeroGlassSheet(child: builder(ctx)),
  );
}

/// AeroGlassSheet — Frosted glass container for bottom sheets.
class AeroGlassSheet extends StatelessWidget {
  final Widget child;
  final double maxHeightFactor;

  const AeroGlassSheet({
    super.key,
    required this.child,
    this.maxHeightFactor = 0.88,
  });

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * maxHeightFactor;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: ClipRRect(
          borderRadius: AeroRadii.sheetRadius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                borderRadius: AeroRadii.sheetRadius,
                border: Border.all(
                  color: AeroColors.borderLight,
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AeroColors.primaryNavy.withValues(alpha: 0.15),
                    blurRadius: 36,
                    offset: const Offset(0, -6),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Sheet Drag Handle
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 10, bottom: 8),
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    Flexible(
                      child: child,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
