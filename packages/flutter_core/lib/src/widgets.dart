import 'package:flutter/material.dart';
import 'analytics.dart';
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

/// Page scaffold: header (logo, bell, title, subtitle) + body + bottom nav.
class TamScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;
  final TamBottomNav? nav;
  final bool showBack;
  final Future<void> Function()? onRefresh;
  const TamScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
    this.nav,
    this.showBack = false,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return ScreenLogger(
      name: title,
      child: Scaffold(
        backgroundColor: TamreedyColors.canvas,
        bottomNavigationBar: nav,
        body: SafeArea(
          child: Column(
            children: [
              Container(
                color: Colors.white,
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Image.asset(
                          'assets/images/logo_wordmark.png',
                          package: kFontPackage,
                          height: 46,
                        ),
                        const Spacer(),
                        if (showBack)
                          IconButton(
                            onPressed: () => Navigator.of(context).maybePop(),
                            icon: const Icon(
                              Icons.arrow_forward_ios,
                              size: 18,
                              color: TamreedyColors.navy,
                            ),
                          ),
                        const BellButton(),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      style: tamText(
                        size: 22,
                        weight: FontWeight.w800,
                        color: TamreedyColors.navy,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: tamText(size: 12, color: TamreedyColors.subtext),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: TamreedyColors.border),
              Expanded(
                child: onRefresh != null
                    ? RefreshIndicator(
                        color: TamreedyColors.teal,
                        onRefresh: onRefresh!,
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                          children: children,
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                        children: children,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BellButton extends StatelessWidget {
  const BellButton({super.key});
  @override
  Widget build(BuildContext context) => Container(
    width: 46,
    height: 52,
    decoration: BoxDecoration(
      color: TamreedyColors.tealTint,
      borderRadius: BorderRadius.circular(14),
    ),
    child: const Icon(Icons.notifications_none, color: TamreedyColors.teal),
  );
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
      color: Colors.white,
      borderRadius: BorderRadius.circular(TamreedyRadii.card),
      border: Border.all(color: TamreedyColors.border),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0A074577),
          blurRadius: 10,
          offset: Offset(0, 3),
        ),
      ],
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(TamreedyRadii.card),
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
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(18),
      gradient: const LinearGradient(
        begin: AlignmentDirectional.centerStart,
        end: AlignmentDirectional.centerEnd,
        colors: [TamreedyColors.teal, TamreedyColors.navy],
      ),
    ),
    child: Stack(
      children: [
        PositionedDirectional(
          end: 0,
          bottom: 0,
          child: Icon(
            Icons.add,
            size: 96,
            color: Colors.white.withValues(alpha: .08),
          ),
        ),
        SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (caption != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    caption!,
                    style: tamText(size: 12, color: Colors.white70),
                  ),
                ),
              Text(
                title,
                style: tamText(
                  size: titleSize,
                  weight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              if (body != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    body!,
                    style: tamText(
                      size: 12.5,
                      color: Colors.white70,
                      height: 1.7,
                    ),
                  ),
                ),
              if (trailing != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: trailing,
                ),
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
    child: Opacity(
      opacity: onPressed == null ? .5 : 1,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(TamreedyRadii.button),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [TamreedyColors.tealAlt, Color(0xFF058A7C)],
            ),
          ),
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
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
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
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: TamreedyColors.border)),
    ),
    child: SafeArea(
      child: SizedBox(
        height: 64,
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: InkWell(
                  onTap: () => onTap(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        items[i].icon,
                        color: i == index
                            ? TamreedyColors.teal
                            : TamreedyColors.subtext,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        items[i].label,
                        style: tamText(
                          size: 11,
                          weight: i == index
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: i == index
                              ? TamreedyColors.teal
                              : TamreedyColors.subtext,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
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
