import 'package:flutter/material.dart';
import '../tokens/aero_colors.dart';
import '../tokens/aero_radii.dart';
import '../tokens/aero_typography.dart';
import 'aero_button.dart';
import 'aero_glass_card.dart';

/// AeroCarePlanCard — Displays an ongoing recurring care plan with progress indicator,
/// next scheduled visit timestamp, and action shortcuts.
class AeroCarePlanCard extends StatelessWidget {
  final String title;
  final String frequency;
  final int totalVisits;
  final int completedVisits;
  final DateTime? nextVisitAt;
  final String status; // ACTIVE, PAUSED, COMPLETED
  final VoidCallback? onTap;

  const AeroCarePlanCard({
    super.key,
    required this.title,
    required this.frequency,
    required this.totalVisits,
    required this.completedVisits,
    this.nextVisitAt,
    this.status = 'ACTIVE',
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final progress = totalVisits > 0 ? (completedVisits / totalVisits).clamp(0.0, 1.0) : 0.0;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AeroGlassCard(
        onTap: onTap,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: aeroText(size: 15, weight: FontWeight.w700, color: AeroColors.primaryNavy),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: status == 'ACTIVE' ? AeroColors.aeroTint : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    status == 'ACTIVE' ? 'نشطة' : 'متوقفة مؤقتاً',
                    style: aeroText(
                      size: 11,
                      weight: FontWeight.w600,
                      color: status == 'ACTIVE' ? AeroColors.accentTeal : AeroColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'التكرار: $frequency',
              style: aeroText(size: 12, color: AeroColors.textSecondary),
            ),
            const SizedBox(height: 12),

            // Progress Bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'الزيارات المنجزة: $completedVisits من $totalVisits',
                  style: aeroText(size: 12, weight: FontWeight.w600, color: AeroColors.textPrimary),
                ),
                Text(
                  '${(progress * 100).toInt()}%',
                  style: aeroText(size: 12, weight: FontWeight.w700, color: AeroColors.accentTeal),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: AeroColors.lightCanvas,
                color: AeroColors.accentTeal,
                minHeight: 6,
              ),
            ),

            if (nextVisitAt != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.event_available, size: 14, color: AeroColors.accentTeal),
                  const SizedBox(width: 4),
                  Text(
                    'الزيارة القادمة: ${nextVisitAt!.day}/${nextVisitAt!.month} الساعة ${nextVisitAt!.hour.toString().padLeft(2, '0')}:${nextVisitAt!.minute.toString().padLeft(2, '0')}',
                    style: aeroText(size: 11, color: AeroColors.textSecondary),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// AeroFavoriteNurseCard — Displays a saved favorite nurse with direct booking capability,
/// verified badge, and rating overview.
class AeroFavoriteNurseCard extends StatelessWidget {
  final String name;
  final double rating;
  final int totalVisits;
  final List<String> skills;
  final bool isAvailable;
  final VoidCallback? onRequestDirect;
  final VoidCallback? onRemoveFavorite;

  const AeroFavoriteNurseCard({
    super.key,
    required this.name,
    required this.rating,
    this.totalVisits = 0,
    this.skills = const [],
    this.isAvailable = true,
    this.onRequestDirect,
    this.onRemoveFavorite,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AeroGlassCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AeroColors.aeroTint,
                  child: Text(
                    name.isNotEmpty ? name[0] : 'ن',
                    style: aeroText(size: 18, weight: FontWeight.w700, color: AeroColors.primaryNavy),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            name,
                            style: aeroText(size: 15, weight: FontWeight.w700, color: AeroColors.primaryNavy),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.verified, size: 16, color: AeroColors.accentTeal),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.star, size: 14, color: Color(0xFFF59E0B)),
                          const SizedBox(width: 2),
                          Text(
                            rating.toStringAsFixed(1),
                            style: aeroText(size: 12, weight: FontWeight.w600),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '($totalVisits زيارة مكتملة)',
                            style: aeroText(size: 11, color: AeroColors.textMuted),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (onRemoveFavorite != null)
                  IconButton(
                    icon: const Icon(Icons.favorite, color: Color(0xFFEF4444), size: 20),
                    tooltip: 'إزالة من المفضلة',
                    onPressed: onRemoveFavorite,
                  ),
              ],
            ),
            if (skills.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: skills.map((s) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AeroColors.lightCanvas,
                    borderRadius: BorderRadius.circular(AeroRadii.badge),
                    border: Border.all(color: AeroColors.borderLight),
                  ),
                  child: Text(s, style: aeroText(size: 10, color: AeroColors.textSecondary)),
                )).toList(),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: AeroButton.teal(
                    'طلب زيارة مباشرة',
                    height: 42,
                    fontSize: 13,
                    onPressed: onRequestDirect,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
