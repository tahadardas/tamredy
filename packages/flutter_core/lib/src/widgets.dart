import 'package:flutter/material.dart';
import 'analytics.dart';
import 'design/tokens/aero_radii.dart';
import 'design/tokens/aero_typography.dart';
import 'design/tokens/tam_tokens.dart';
import 'design/widgets/aero_button.dart';
import 'theme.dart';

enum Tone { teal, blue, orange, danger }

Color _toneBg(Tone t, TamThemeColors c) => switch (t) {
  Tone.teal => c.primaryTint,
  Tone.blue => c.secondaryTint,
  Tone.orange => c.warningTint,
  Tone.danger => c.dangerTint,
};
Color _toneFg(Tone t, TamThemeColors c) => switch (t) {
  Tone.teal => c.primary,
  Tone.blue => c.secondary,
  Tone.orange => c.warning,
  Tone.danger => c.danger,
};

/// Shared layout for Arabic screens, including optional persistent actions.
class TamScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;
  final TamBottomNav? nav;
  final Widget? actions;
  final bool showBack;
  final bool showHeader;
  final Future<void> Function()? onRefresh;

  const TamScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
    this.nav,
    this.actions,
    this.showBack = false,
    this.showHeader = true,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.tamColors;
    final refresh = onRefresh;
    final visibleNav = MediaQuery.viewInsetsOf(context).bottom == 0 ? nav : null;
    final content = ListView(
      physics: refresh == null ? null : const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: TamBreakpoints.maxContentWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ],
    );

    return ScreenLogger(
      name: title,
      child: Scaffold(
        backgroundColor: c.background,
        extendBody: false,
        bottomNavigationBar: visibleNav,
        body: SafeArea(
          bottom: visibleNav == null,
          child: Column(
            children: [
              if (showHeader)
                Container(
                decoration: BoxDecoration(
                  color: c.surface,
                  border: Border(
                    bottom: BorderSide(color: c.border, width: 1.0),
                  ),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: TamBreakpoints.maxContentWidth + 32),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          if (showBack)
                            Material(
                              color: c.surfaceElevated,
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => Navigator.of(context).maybePop(),
                                child: SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: Icon(
                                    Icons.arrow_back_rounded,
                                    color: c.textPrimary,
                                    size: 22,
                                  ),
                                ),
                              ),
                            )
                          else
                            Image.asset(
                              'assets/images/logo_mark.png',
                              package: kFontPackage,
                              width: 42,
                              height: 42,
                              excludeFromSemantics: true,
                            ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Semantics(
                                  header: true,
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: aeroText(size: 19, weight: FontWeight.w800, color: c.textPrimary),
                                  ),
                                ),
                                if (subtitle.isNotEmpty)
                                  Text(
                                    subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: aeroText(size: 12, weight: FontWeight.w500, color: c.textSecondary),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: refresh == null
                    ? content
                    : RefreshIndicator(
                        color: c.primary,
                        onRefresh: refresh,
                        child: content,
                      ),
              ),
              if (actions != null)
                Container(
                  decoration: BoxDecoration(
                    color: c.surface,
                    border: Border(top: BorderSide(color: c.border)),
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: TamBreakpoints.maxContentWidth),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                        child: actions!,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.tamColors;
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 12),
      child: Text(
        text,
        style: tamText(
          size: 17,
          weight: FontWeight.w800,
          color: c.textPrimary,
        ),
      ),
    );
  }
}

class TamCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  const TamCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final c = context.tamColors;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AeroRadii.mainCard),
        border: Border.all(color: c.border, width: 1.0),
        boxShadow: c.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AeroRadii.mainCard),
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class HeroCard extends StatelessWidget {
  final String? caption;
  final String title;
  final String? body;
  final Widget? trailing;
  final double titleSize;
  const HeroCard({
    super.key,
    this.caption,
    required this.title,
    this.body,
    this.trailing,
    this.titleSize = 22,
  });
  @override
  Widget build(BuildContext context) {
    final c = context.tamColors;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AeroRadii.heroCard),
        gradient: LinearGradient(
          begin: AlignmentDirectional.centerStart,
          end: AlignmentDirectional.centerEnd,
          colors: [c.heroStart, c.heroEnd],
        ),
        boxShadow: c.elevatedShadow,
      ),
      child: Stack(
        children: [
          if (caption != null)
            PositionedDirectional(
              top: 0,
              start: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(AeroRadii.dock),
                ),
                child: Text(
                  caption!,
                  style: aeroText(size: 11, weight: FontWeight.w700, color: Colors.white),
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.only(top: caption != null ? 28 : 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: aeroText(size: titleSize, weight: FontWeight.w800, color: Colors.white),
                ),
                if (body != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    body!,
                    style: aeroText(size: 13, weight: FontWeight.w500, color: Colors.white.withValues(alpha: 0.9)),
                  ),
                ],
                if (trailing != null) ...[
                  const SizedBox(height: 14),
                  trailing!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  final String text;
  final bool warning;
  const StatusChip(this.text, {super.key, this.warning = false});
  @override
  Widget build(BuildContext context) {
    final c = context.tamColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: warning ? c.warningTint : c.successTint,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        style: tamText(
          size: 11.5,
          weight: FontWeight.w700,
          color: warning ? c.warning : c.success,
        ),
      ),
    );
  }
}

class IconBox extends StatelessWidget {
  final IconData icon;
  final Tone tone;
  final double size;
  const IconBox(this.icon, {super.key, this.tone = Tone.teal, this.size = 46});
  @override
  Widget build(BuildContext context) {
    final c = context.tamColors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _toneBg(tone, c),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Icon(icon, color: _toneFg(tone, c), size: size * .5),
    );
  }
}

/// A row: icon box, title/subtitle, and a trailing chip/arrow.
class ListRow extends StatelessWidget {
  final IconData icon;
  final Tone tone;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool divider;
  const ListRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.tone = Tone.teal,
    this.divider = true,
  });
  @override
  Widget build(BuildContext context) {
    final c = context.tamColors;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: divider
              ? Border(bottom: BorderSide(color: c.border))
              : null,
        ),
        child: Row(
          children: [
            IconBox(icon, tone: tone),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: tamText(
                      size: 14,
                      weight: FontWeight.w700,
                      color: c.textPrimary,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: tamText(size: 11.5, color: c.textSecondary),
                    ),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

/// Label on the start side, bold value on the end side.
class KeyValueRow extends StatelessWidget {
  final String label;
  final String value;
  const KeyValueRow(this.label, this.value, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.tamColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            flex: 3,
            child: Text(label, style: tamText(size: 13, color: c.textSecondary)),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: tamText(
                size: 13,
                weight: FontWeight.w700,
                color: c.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  const StatCard(this.label, this.value, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.tamColors;
    return TamCard(
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TamTypography.supporting(
                color: c.textSecondary,
                weight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: TamSpacing.md),
            Text(
              value,
              style: TamTypography.financialAmount(
                color: c.textPrimary,
                size: 28,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const PrimaryButton(this.label, {super.key, this.onPressed});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: AeroButton(
      label,
      onPressed: onPressed,
      variant: AeroButtonVariant.primary,
    ),
  );
}

class SoftButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const SoftButton(this.label, {super.key, this.onPressed});
  @override
  Widget build(BuildContext context) {
    final c = context.tamColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        button: true,
        enabled: onPressed != null,
        label: label,
        child: Material(
          color: c.primaryTint.withValues(alpha: c.isDark ? 0.35 : 0.75),
          borderRadius: BorderRadius.circular(TamreedyRadii.button),
          child: InkWell(
            borderRadius: BorderRadius.circular(TamreedyRadii.button),
            onTap: onPressed,
            child: Container(
              constraints: const BoxConstraints(minHeight: 52),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              alignment: Alignment.center,
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: aeroText(
                  size: 15,
                  weight: FontWeight.w700,
                  color: c.isDark ? c.primaryAccent : c.primaryDark,
                  height: 1.35,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class NoticeBox extends StatelessWidget {
  final String text;
  const NoticeBox(this.text, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.tamColors;
    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 12),
      padding: const EdgeInsets.all(16),
      width: double.infinity,
      decoration: BoxDecoration(
        color: c.warningTint.withValues(alpha: c.isDark ? 0.35 : 0.85),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.warning.withValues(alpha: 0.25)),
      ),
      child: Text(
        text,
        style: tamText(size: 12.5, color: c.isDark ? c.textPrimary : c.warning, height: 1.7),
      ),
    );
  }
}

class NavItem {
  final IconData icon;
  final String label;
  const NavItem(this.icon, this.label);
}

class TamBottomNav extends StatelessWidget {
  final List<NavItem> items;
  final int index;
  final ValueChanged<int> onTap;
  const TamBottomNav({
    super.key,
    required this.items,
    required this.index,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final c = context.tamColors;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final narrow = TamBreakpoints.isNarrowPhone(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        bottom: bottomInset > 0 ? bottomInset + 6 : 10,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: c.navBackground,
          borderRadius: BorderRadius.circular(AeroRadii.dock),
          border: Border.all(color: c.border),
          boxShadow: c.cardShadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AeroRadii.dock),
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            removeBottom: true,
            child: NavigationBarTheme(
              data: NavigationBarThemeData(
                height: 68,
                backgroundColor: c.navBackground,
                surfaceTintColor: Colors.transparent,
                indicatorColor: c.primaryTint.withValues(
                  alpha: c.isDark ? 0.45 : 0.85,
                ),
                indicatorShape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                labelTextStyle: WidgetStateProperty.resolveWith((states) {
                  final selected = states.contains(WidgetState.selected);
                  return aeroText(
                    size: narrow ? 10.5 : 11.5,
                    weight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? c.primary : c.textSecondary,
                  );
                }),
                iconTheme: WidgetStateProperty.resolveWith((states) {
                  final selected = states.contains(WidgetState.selected);
                  return IconThemeData(
                    size: narrow ? 20 : 22,
                    color: selected ? c.primary : c.textSecondary,
                  );
                }),
              ),
              child: NavigationBar(
                height: 68,
                elevation: 0,
                backgroundColor: c.navBackground,
                surfaceTintColor: Colors.transparent,
                selectedIndex: index.clamp(0, items.length - 1),
                onDestinationSelected: onTap,
                destinations: [
                  for (final item in items)
                    NavigationDestination(
                      icon: Icon(item.icon),
                      selectedIcon: Icon(item.icon),
                      label: item.label,
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

/// Segmented progress bar used while searching for a nurse.
class StepBar extends StatelessWidget {
  final int total;
  final int filled;
  const StepBar({super.key, this.total = 4, required this.filled});
  @override
  Widget build(BuildContext context) {
    final c = context.tamColors;
    return Row(
      children: [
        for (var i = 0; i < total; i++)
          Expanded(
            child: Container(
              height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: i < filled ? c.primary : c.border,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
      ],
    );
  }
}

/// Runs [onStart] once when the signed-in part of the app first appears (data loaded before login got 401).
class OnSessionStart extends StatefulWidget {
  final Future<void> Function() onStart;
  final Widget child;
  const OnSessionStart({super.key, required this.onStart, required this.child});
  @override
  State<OnSessionStart> createState() => _OnSessionStartState();
}

class _OnSessionStartState extends State<OnSessionStart> {
  @override
  void initState() {
    super.initState();
    widget.onStart();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
