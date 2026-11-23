import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../tokens/aero_colors.dart';
import '../tokens/aero_motion_tokens.dart';
import '../tokens/aero_radii.dart';
import '../tokens/aero_shadows.dart';
import '../tokens/aero_typography.dart';

class AeroDockItem {
  final IconData icon;
  final IconData? activeIcon;
  final String label;
  final int badgeCount;

  const AeroDockItem({
    required this.icon,
    this.activeIcon,
    required this.label,
    this.badgeCount = 0,
  });
}

/// AeroFloatingDock — Floating navigation pill dock for Patient and Nurse apps.
/// Features frosted glass styling, subtle teal illuminated border,
/// animated active tab indicator, and RTL orientation support.
class AeroFloatingDock extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onIndexChanged;
  final List<AeroDockItem> items;

  const AeroFloatingDock({
    super.key,
    required this.currentIndex,
    required this.onIndexChanged,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: bottomInset > 0 ? bottomInset + 8 : 16,
      ),
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AeroRadii.dock),
          boxShadow: AeroShadows.floatingDock,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AeroRadii.dock),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(AeroRadii.dock),
                border: Border.all(
                  color: AeroColors.borderLight,
                  width: 1.2,
                ),
              ),
              child: Row(
                children: [
                  for (int i = 0; i < items.length; i++)
                    Expanded(
                      child: _buildDockItem(context, i),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDockItem(BuildContext context, int index) {
    final isSelected = index == currentIndex;
    final item = items[index];

    return GestureDetector(
      onTap: () {
        if (!isSelected) {
          HapticFeedback.selectionClick();
          onIndexChanged(index);
        }
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: AeroMotionTokens.tabDuration,
        curve: AeroMotionTokens.springCurve,
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? AeroColors.accentTeal.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AeroRadii.dock),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  isSelected ? (item.activeIcon ?? item.icon) : item.icon,
                  size: 22,
                  color: isSelected ? AeroColors.accentTeal : AeroColors.textSecondary,
                ),
                if (item.badgeCount > 0)
                  Positioned(
                    top: -4,
                    right: -8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: AeroColors.danger,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Text(
                        item.badgeCount > 9 ? '9+' : '${item.badgeCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              item.label,
              style: aeroText(
                size: 11,
                weight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? AeroColors.accentTeal : AeroColors.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
