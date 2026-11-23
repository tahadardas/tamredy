import 'dart:ui';
import 'package:flutter/material.dart';
import 'analytics.dart';
import 'design/tokens/aero_colors.dart';
import 'design/tokens/aero_radii.dart';
import 'design/tokens/aero_shadows.dart';
import 'design/tokens/aero_typography.dart';
import 'design/widgets/aero_button.dart';
import 'theme.dart';

enum Tone { teal, blue, orange, danger }

Color _toneBg(Tone t) => switch (t) {
  Tone.teal => TamreedyColors.tealTint,
  Tone.blue => TamreedyColors.blueTint,
  Tone.orange => TamreedyColors.orangeTint,
  Tone.danger => TamreedyColors.dangerTint,
};
Color _toneFg(Tone t) => switch (t) {
  Tone.teal => TamreedyColors.teal,
  Tone.blue => TamreedyColors.navy,
  Tone.orange => const Color(0xFFD9822B),
  Tone.danger => TamreedyColors.danger,
};

/// Shared layout for Arabic screens, including optional persistent actions.
class TamScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;
  final TamBottomNav? nav;
  final Widget? actions;
  final bool showBack;
  final Future<void> Function()? onRefresh;

  const TamScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
    this.nav,
    this.actions,
    this.showBack = false,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final refresh = onRefresh;
    final visibleNav = MediaQuery.viewInsetsOf(context).bottom == 0 ? nav : null;
    final content = ListView(
      physics: refresh == null ? null : const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16, 12, 16, visibleNav != null ? 86 : 24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
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
        backgroundColor: AeroColors.lightCanvas,
        extendBody: true,
        bottomNavigationBar: visibleNav,
        body: SafeArea(
          bottom: visibleNav == null,
          child: Column(
            children: [
              ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.88),
                      border: Border(
                        bottom: BorderSide(
                          color: AeroColors.borderLight,
                          width: 1.0,
                        ),
                      ),
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 712),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              if (showBack)
                                IconButton(
                                  tooltip: 'رجوع',
                                  onPressed: () => Navigator.of(context).maybePop(),
                                  icon: const Icon(Icons.arrow_back_rounded, color: AeroColors.primaryNavy),
                                )
                              else
                                Image.asset(
                                  'assets/images/logo_mark.png',
                                  package: kFontPackage,
                                  width: 46,
                                  height: 46,
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
                                        style: aeroText(size: 20, weight: FontWeight.w800, color: AeroColors.textPrimary),
                                      ),
                                    ),
                                    if (subtitle.isNotEmpty)
                                      Text(
                                        subtitle,
                                        style: aeroText(size: 12, weight: FontWeight.w500, color: AeroColors.textSecondary),
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
                ),
              ),
              Expanded(
                child: refresh == null
                    ? content
                    : RefreshIndicator(
                        color: AeroColors.accentTeal,
                        onRefresh: refresh,
                        child: content,
                      ),
              ),
              if (actions != null)
                Container(
                  color: Colors.white.withValues(alpha: 0.9),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 680),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 12),
    child: Text(
      text,
      style: tamText(
        size: 17,
        weight: FontWeight.w800,
        color: TamreedyColors.navy,
      ),
    ),
  );
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
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(AeroRadii.mainCard),
      border: Border.all(color: AeroColors.borderLight, width: 1.1),
      boxShadow: AeroShadows.card,
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
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(AeroRadii.heroCard),
      gradient: const LinearGradient(
        begin: AlignmentDirectional.centerStart,
        end: AlignmentDirectional.centerEnd,
        colors: [AeroColors.primaryNavy, Color(0xFF0C5D8B), AeroColors.accentTeal],
      ),
      boxShadow: AeroShadows.hero,
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
                color: Colors.white.withValues(alpha: 0.2),
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

class StatusChip extends StatelessWidget {
  final String text;
  final bool warning;
  const StatusChip(this.text, {super.key, this.warning = false});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: warning ? const Color(0xFFFCEBD8) : const Color(0xFFDDF3EE),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      text,
      style: tamText(
        size: 11.5,
        weight: FontWeight.w700,
        color: warning ? TamreedyColors.warning : TamreedyColors.success,
      ),
    ),
  );
}

class IconBox extends StatelessWidget {
  final IconData icon;
  final Tone tone;
  final double size;
  const IconBox(this.icon, {super.key, this.tone = Tone.teal, this.size = 46});
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: _toneBg(tone),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Icon(icon, color: _toneFg(tone), size: size * .5),
  );
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
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: divider
            ? const Border(bottom: BorderSide(color: TamreedyColors.border))
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
                    color: TamreedyColors.navy,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: tamText(size: 11.5, color: TamreedyColors.subtext),
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

/// Label on the start side, bold value on the end side.
class KeyValueRow extends StatelessWidget {
  final String label;
  final String value;
  const KeyValueRow(this.label, this.value, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      children: [
        Text(label, style: tamText(size: 13, color: TamreedyColors.subtext)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: tamText(
              size: 13,
              weight: FontWeight.w700,
              color: TamreedyColors.navy,
            ),
          ),
        ),
      ],
    ),
  );
}

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  const StatCard(this.label, this.value, {super.key});
  @override
  Widget build(BuildContext context) => TamCard(
    child: SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: tamText(
              size: 15,
              weight: FontWeight.w800,
              color: TamreedyColors.navy,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            value,
            style: tamText(
              size: 30,
              weight: FontWeight.w800,
              color: TamreedyColors.navy,
            ),
          ),
        ],
      ),
    ),
  );
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: TamreedyColors.tealTint,
      borderRadius: BorderRadius.circular(TamreedyRadii.button),
      child: InkWell(
        borderRadius: BorderRadius.circular(TamreedyRadii.button),
        onTap: onPressed,
        child: Container(
          height: 54,
          alignment: Alignment.center,
          child: Text(
            label,
            style: tamText(
              size: 15,
              weight: FontWeight.w800,
              color: TamreedyColors.success,
            ),
          ),
        ),
      ),
    ),
  );
}

class NoticeBox extends StatelessWidget {
  final String text;
  const NoticeBox(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 6, bottom: 12),
    padding: const EdgeInsets.all(16),
    width: double.infinity,
    decoration: BoxDecoration(
      color: TamreedyColors.warningTint,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Text(
      text,
      style: tamText(size: 12.5, color: TamreedyColors.warning, height: 1.7),
    ),
  );
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
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: bottomInset > 0 ? bottomInset + 4 : 12,
      ),
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AeroRadii.dock),
          boxShadow: AeroShadows.floatingDock,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AeroRadii.dock),
          child: NavigationBar(
            backgroundColor: Colors.white.withValues(alpha: 0.94),
            indicatorColor: AeroColors.accentTeal.withValues(alpha: 0.16),
            height: 64,
            selectedIndex: index,
            onDestinationSelected: onTap,
            destinations: [
              for (final item in items)
                NavigationDestination(
                  icon: Icon(item.icon, size: 22, color: AeroColors.textSecondary),
                  selectedIcon: Icon(item.icon, size: 22, color: AeroColors.accentTeal),
                  label: item.label,
                ),
            ],
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
  Widget build(BuildContext context) => Row(
    children: [
      for (var i = 0; i < total; i++)
        Expanded(
          child: Container(
            height: 4,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: i < filled ? TamreedyColors.teal : TamreedyColors.border,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
    ],
  );
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
