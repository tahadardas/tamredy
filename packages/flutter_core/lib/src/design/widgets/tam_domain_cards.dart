import 'package:flutter/material.dart';
import '../tokens/aero_typography.dart';
import '../tokens/tam_tokens.dart';
import 'tam_status_badge.dart';

/// Medical Service Card for catalogs and quick-pick grids.
class TamServiceCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? description;
  final String? priceLabel;
  final String? durationLabel;
  final bool requiresPrescription;
  final bool selected;
  final int quantity;
  final VoidCallback? onTap;
  final VoidCallback? onIncrement;
  final VoidCallback? onDecrement;

  const TamServiceCard({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.priceLabel,
    this.durationLabel,
    this.requiresPrescription = false,
    this.selected = false,
    this.quantity = 0,
    this.onTap,
    this.onIncrement,
    this.onDecrement,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.tamColors;
    return Material(
      color: selected
          ? c.primaryTint.withValues(alpha: c.isDark ? 0.25 : 0.45)
          : c.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(TamSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? c.primary : c.border,
              width: selected ? 1.5 : 1.0,
            ),
            boxShadow: c.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: selected ? c.primary : c.primaryTint,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      icon,
                      size: 22,
                      color: selected ? Colors.white : c.primary,
                    ),
                  ),
                  const Spacer(),
                  if (requiresPrescription)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: c.warningTint,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'وصفة طبية',
                        style: aeroText(
                          size: 10.5,
                          weight: FontWeight.w700,
                          color: c.warning,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: TamSpacing.md),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: aeroText(
                  size: 15,
                  weight: FontWeight.w700,
                  color: c.textPrimary,
                  height: 1.35,
                ),
              ),
              if (description != null && description!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  description!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: aeroText(
                    size: 12.5,
                    color: c.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
              if (priceLabel != null || durationLabel != null) ...[
                const SizedBox(height: TamSpacing.md),
                Wrap(
                  spacing: TamSpacing.sm,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (priceLabel != null)
                      Text(
                        priceLabel!,
                        style: aeroText(
                          size: 13.5,
                          weight: FontWeight.w800,
                          color: c.primary,
                        ),
                      ),
                    if (durationLabel != null)
                      Text(
                        '• $durationLabel',
                        style: aeroText(
                          size: 12,
                          color: c.textSecondary,
                        ),
                      ),
                  ],
                ),
              ],
              if (quantity > 0 && (onIncrement != null || onDecrement != null)) ...[
                const SizedBox(height: TamSpacing.md),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: onDecrement,
                      icon: const Icon(Icons.remove_circle_outline_rounded),
                      color: c.primary,
                      tooltip: 'إنقاص الكمية',
                    ),
                    Text(
                      '$quantity',
                      style: aeroText(
                        size: 15,
                        weight: FontWeight.w800,
                        color: c.textPrimary,
                      ),
                    ),
                    IconButton(
                      onPressed: onIncrement,
                      icon: const Icon(Icons.add_circle_outline_rounded),
                      color: c.primary,
                      tooltip: 'زيادة الكمية',
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Nurse profile & credential card used in tracking, proposals, and favorites.
class TamNurseCard extends StatelessWidget {
  final String name;
  final String? badgeText;
  final double? rating;
  final int? completedVisits;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const TamNurseCard({
    super.key,
    required this.name,
    this.badgeText,
    this.rating,
    this.completedVisits,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.tamColors;
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(TamSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: c.border),
            boxShadow: c.cardShadow,
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: c.primaryTint,
                child: Icon(Icons.person_rounded, color: c.primary, size: 26),
              ),
              const SizedBox(width: TamSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: TamSpacing.xs,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          name,
                          style: aeroText(
                            size: 15,
                            weight: FontWeight.w700,
                            color: c.textPrimary,
                          ),
                        ),
                        if (badgeText != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: c.primaryTint,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              badgeText!,
                              style: aeroText(
                                size: 10.5,
                                weight: FontWeight.w700,
                                color: c.primaryDark,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (rating != null) ...[
                          Icon(Icons.star_rounded, size: 16, color: c.warning),
                          const SizedBox(width: 3),
                          Text(
                            rating!.toStringAsFixed(1),
                            style: aeroText(
                              size: 12.5,
                              weight: FontWeight.w700,
                              color: c.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (completedVisits != null)
                          Text(
                            '$completedVisits زيارة',
                            style: aeroText(size: 12, color: c.textSecondary),
                          ),
                        if (subtitle != null)
                          Flexible(
                            child: Text(
                              subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: aeroText(size: 12, color: c.textSecondary),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

/// Appointment / Scheduled visit summary card.
class TamAppointmentCard extends StatelessWidget {
  final String title;
  final String dateTimeLabel;
  final String? areaLabel;
  final String status;
  final String? priceLabel;
  final VoidCallback? onTap;

  const TamAppointmentCard({
    super.key,
    required this.title,
    required this.dateTimeLabel,
    this.areaLabel,
    required this.status,
    this.priceLabel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.tamColors;
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(TamSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: c.border),
            boxShadow: c.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: aeroText(
                        size: 15,
                        weight: FontWeight.w700,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: TamSpacing.sm),
                  TamStatusBadge(status: status, compact: true),
                ],
              ),
              const SizedBox(height: TamSpacing.sm),
              Row(
                children: [
                  Icon(Icons.schedule_rounded, size: 15, color: c.textSecondary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      dateTimeLabel,
                      style: aeroText(size: 12.5, color: c.textSecondary),
                    ),
                  ),
                  if (priceLabel != null)
                    Text(
                      priceLabel!,
                      style: aeroText(
                        size: 13,
                        weight: FontWeight.w700,
                        color: c.primary,
                      ),
                    ),
                ],
              ),
              if (areaLabel != null && areaLabel!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 15,
                      color: c.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        areaLabel!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: aeroText(size: 12.5, color: c.textSecondary),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Notification list item card.
class TamNotificationCard extends StatelessWidget {
  final String title;
  final String body;
  final String? timeLabel;
  final bool unread;
  final IconData icon;
  final VoidCallback? onTap;

  const TamNotificationCard({
    super.key,
    required this.title,
    required this.body,
    this.timeLabel,
    this.unread = false,
    this.icon = Icons.notifications_rounded,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.tamColors;
    return Material(
      color: unread ? c.primaryTint.withValues(alpha: 0.35) : c.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(TamSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: unread ? c.primary : c.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: unread ? c.primary : c.surfaceElevated,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: unread ? Colors.white : c.textSecondary,
                ),
              ),
              const SizedBox(width: TamSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: aeroText(
                              size: 13.5,
                              weight: FontWeight.w700,
                              color: c.textPrimary,
                            ),
                          ),
                        ),
                        if (timeLabel != null)
                          Text(
                            timeLabel!,
                            style: aeroText(size: 11, color: c.textMuted),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      body,
                      style: aeroText(
                        size: 12.5,
                        color: c.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Financial KPI summary row/card.
class TamFinancialSummary extends StatelessWidget {
  final String title;
  final String primaryValue;
  final String? subtitle;
  final List<({String label, String value, Color? color})> metrics;

  const TamFinancialSummary({
    super.key,
    required this.title,
    required this.primaryValue,
    this.subtitle,
    this.metrics = const [],
  });

  @override
  Widget build(BuildContext context) {
    final c = context.tamColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(TamSpacing.xl),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [c.heroStart, c.heroEnd],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: c.elevatedShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: aeroText(
              size: 12.5,
              weight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            primaryValue,
            style: aeroText(
              size: 26,
              weight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: aeroText(
                size: 12.5,
                color: Colors.white.withValues(alpha: 0.78),
              ),
            ),
          ],
          if (metrics.isNotEmpty) ...[
            const SizedBox(height: TamSpacing.lg),
            Container(
              padding: const EdgeInsets.all(TamSpacing.md),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: metrics.map((m) {
                  return Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          m.label,
                          style: aeroText(
                            size: 11,
                            color: Colors.white.withValues(alpha: 0.75),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          m.value,
                          style: aeroText(
                            size: 13.5,
                            weight: FontWeight.w700,
                            color: m.color ?? Colors.white,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Itemized invoice card.
class TamInvoiceCard extends StatelessWidget {
  final String title;
  final String statusLabel;
  final Color? statusColor;
  final List<({String label, String value, bool highlight})> lines;
  final String totalLabel;
  final String totalValue;

  const TamInvoiceCard({
    super.key,
    this.title = 'ملخص الفاتورة',
    required this.statusLabel,
    this.statusColor,
    required this.lines,
    this.totalLabel = 'الإجمالي المستحق',
    required this.totalValue,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.tamColors;
    final badgeColor = statusColor ?? c.primary;
    return Container(
      padding: const EdgeInsets.all(TamSpacing.lg),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.border),
        boxShadow: c.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: aeroText(
                    size: 15,
                    weight: FontWeight.w700,
                    color: c.textPrimary,
                  ),
                ),
              ),
              TamStatusBadge(
                labelOverride: statusLabel,
                foregroundOverride: badgeColor,
                backgroundOverride: badgeColor.withValues(alpha: 0.14),
                iconOverride: Icons.receipt_long_rounded,
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: TamSpacing.md),
          ...lines.map(
            (l) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l.label,
                      style: aeroText(size: 13, color: c.textSecondary),
                    ),
                  ),
                  Text(
                    l.value,
                    style: aeroText(
                      size: 13,
                      weight: l.highlight ? FontWeight.w700 : FontWeight.w600,
                      color: l.highlight ? c.success : c.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: TamSpacing.sm),
            child: Divider(color: c.border),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  totalLabel,
                  style: aeroText(
                    size: 14.5,
                    weight: FontWeight.w700,
                    color: c.textPrimary,
                  ),
                ),
              ),
              Text(
                totalValue,
                style: aeroText(
                  size: 17,
                  weight: FontWeight.w800,
                  color: c.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// High-visibility emergency / safety card (zero motion delay).
class TamEmergencyCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;
  final IconData icon;

  const TamEmergencyCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
    this.icon = Icons.emergency_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.tamColors;
    return Container(
      padding: const EdgeInsets.all(TamSpacing.lg),
      decoration: BoxDecoration(
        color: c.dangerTint.withValues(alpha: c.isDark ? 0.35 : 0.75),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.danger.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: c.danger,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(width: TamSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: aeroText(
                    size: 14.5,
                    weight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: aeroText(
                    size: 12,
                    color: c.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: TamSpacing.sm),
          ElevatedButton(
            onPressed: onAction,
            style: ElevatedButton.styleFrom(
              backgroundColor: c.danger,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: Text(
              actionLabel,
              style: aeroText(
                size: 12.5,
                weight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Map overlay pill for ETA, distance, or connection freshness.
class TamMapOverlay extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? accent;

  const TamMapOverlay({
    super.key,
    required this.icon,
    required this.label,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.tamColors;
    final fg = accent ?? c.primary;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: TamSpacing.md,
        vertical: TamSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: c.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.border),
        boxShadow: c.cardShadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: aeroText(
              size: 12,
              weight: FontWeight.w700,
              color: c.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
