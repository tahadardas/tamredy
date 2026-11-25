import 'package:flutter/material.dart';
import '../tokens/aero_typography.dart';
import '../tokens/tam_tokens.dart';

/// Accessible icon button (>= 48x48dp touch target) with semantic states.
class TamIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;
  final Color? backgroundColor;
  final int badgeCount;

  const TamIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
    this.backgroundColor,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.tamColors;
    final fg = onPressed == null ? c.textMuted : (color ?? c.textPrimary);
    final bg = backgroundColor ?? c.surfaceElevated;

    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: c.border),
          ),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 48,
              height: 48,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(icon, size: 22, color: fg),
                  if (badgeCount > 0)
                    PositionedDirectional(
                      top: 6,
                      end: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: c.danger,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          badgeCount > 9 ? '9+' : '$badgeCount',
                          style: aeroText(
                            size: 10,
                            weight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TamNavDestination {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int badgeCount;

  const TamNavDestination({
    required this.icon,
    IconData? activeIcon,
    required this.label,
    this.badgeCount = 0,
  }) : activeIcon = activeIcon ?? icon;
}

/// Clean, calm, 320px-safe bottom navigation bar for Tamreedy 2.0.
class TamNavigationBar extends StatelessWidget {
  final int currentIndex;
  final List<TamNavDestination> destinations;
  final ValueChanged<int> onChanged;

  const TamNavigationBar({
    super.key,
    required this.currentIndex,
    required this.destinations,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.tamColors;
    final narrow = TamBreakpoints.isNarrowPhone(context);
    return Container(
      decoration: BoxDecoration(
        color: c.navBackground,
        border: Border(top: BorderSide(color: c.border)),
        boxShadow: c.cardShadow,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: TamSpacing.xs,
            vertical: TamSpacing.xs,
          ),
          child: Row(
            children: List.generate(destinations.length, (i) {
              final d = destinations[i];
              final selected = i == currentIndex;
              final fg = selected ? c.primary : c.textSecondary;
              return Expanded(
                child: Semantics(
                  button: true,
                  selected: selected,
                  label: d.label,
                  child: InkWell(
                    onTap: () => onChanged(i),
                    borderRadius: BorderRadius.circular(14),
                    child: AnimatedContainer(
                      duration: TamMotion.of(context, TamMotion.fast),
                      constraints: const BoxConstraints(minHeight: 52),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? c.primaryTint.withValues(alpha: c.isDark ? 0.35 : 0.7)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Icon(
                                selected ? d.activeIcon : d.icon,
                                size: narrow ? 20 : 22,
                                color: fg,
                              ),
                              if (d.badgeCount > 0)
                                PositionedDirectional(
                                  top: -4,
                                  end: -8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: c.danger,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      '${d.badgeCount}',
                                      style: aeroText(
                                        size: 9,
                                        weight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            d.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: aeroText(
                              size: narrow ? 10.5 : 11.5,
                              weight: selected ? FontWeight.w700 : FontWeight.w500,
                              color: fg,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

/// Responsive Sidebar for tablet / wide screens (>= 1024dp).
class TamResponsiveSidebar extends StatelessWidget {
  final String brandTitle;
  final String? brandSubtitle;
  final int currentIndex;
  final List<TamNavDestination> destinations;
  final ValueChanged<int> onChanged;
  final Widget? footer;

  const TamResponsiveSidebar({
    super.key,
    this.brandTitle = 'تمريضي',
    this.brandSubtitle,
    required this.currentIndex,
    required this.destinations,
    required this.onChanged,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.tamColors;
    return Container(
      width: TamBreakpoints.sidebarWidth,
      decoration: BoxDecoration(
        color: c.surface,
        border: BorderDirectional(end: BorderSide(color: c.border)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(TamSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    brandTitle,
                    style: aeroText(
                      size: 20,
                      weight: FontWeight.w800,
                      color: c.primary,
                    ),
                  ),
                  if (brandSubtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      brandSubtitle!,
                      style: aeroText(size: 12, color: c.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
            Divider(color: c.border),
            const SizedBox(height: TamSpacing.sm),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: TamSpacing.md),
                itemCount: destinations.length,
                separatorBuilder: (_, __) => const SizedBox(height: 4),
                itemBuilder: (context, i) {
                  final d = destinations[i];
                  final selected = i == currentIndex;
                  return ListTile(
                    selected: selected,
                    selectedTileColor:
                        c.primaryTint.withValues(alpha: c.isDark ? 0.3 : 0.7),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    leading: Icon(
                      selected ? d.activeIcon : d.icon,
                      color: selected ? c.primary : c.textSecondary,
                    ),
                    title: Text(
                      d.label,
                      style: aeroText(
                        size: 14,
                        weight: selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected ? c.primaryDark : c.textPrimary,
                      ),
                    ),
                    onTap: () => onChanged(i),
                  );
                },
              ),
            ),
            if (footer != null) ...[
              Divider(color: c.border),
              Padding(
                padding: const EdgeInsets.all(TamSpacing.md),
                child: footer!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
