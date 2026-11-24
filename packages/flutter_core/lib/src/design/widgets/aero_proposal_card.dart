import 'package:flutter/material.dart';
import '../tokens/aero_colors.dart';
import '../tokens/aero_radii.dart';
import '../tokens/aero_typography.dart';
import 'aero_button.dart';

class AeroProposalData {
  final String id;
  final String nurseId;
  final String nurseName;
  final double ratingAvg;
  final int completedVisitsCount;
  final int? estimatedArrivalMinutes;
  final DateTime? proposedArrivalAt;
  final String? nurseNote;
  final int priceAmount;
  final String currencyCode;
  final String status;

  const AeroProposalData({
    required this.id,
    required this.nurseId,
    required this.nurseName,
    required this.ratingAvg,
    required this.completedVisitsCount,
    this.estimatedArrivalMinutes,
    this.proposedArrivalAt,
    this.nurseNote,
    required this.priceAmount,
    this.currencyCode = 'ل.س',
    this.status = 'PENDING',
  });
}

class AeroProposalCard extends StatelessWidget {
  final AeroProposalData proposal;
  final VoidCallback onAccept;
  final VoidCallback? onDecline;
  final bool isAccepting;
  final bool isDeclining;

  const AeroProposalCard({
    super.key,
    required this.proposal,
    required this.onAccept,
    this.onDecline,
    this.isAccepting = false,
    this.isDeclining = false,
  });

  @override
  Widget build(BuildContext context) {
    final arrivalText = proposal.estimatedArrivalMinutes != null
        ? 'يصل خلال ${proposal.estimatedArrivalMinutes} دقيقة تقريباً'
        : proposal.proposedArrivalAt != null
            ? 'الموعد المقترح: ${_formatTime(proposal.proposedArrivalAt!)}'
            : 'جاهز للانطلاق فوراً';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AeroRadii.mainCardRadius,
        border: Border.all(color: AeroColors.borderLight, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: AeroColors.primaryNavy.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top: Nurse profile header & Price
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Nurse Avatar
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AeroColors.aeroTintLight,
                    shape: BoxShape.circle,
                    border: Border.all(color: AeroColors.accentTeal.withValues(alpha: 0.3)),
                  ),
                  child: Center(
                    child: Text(
                      proposal.nurseName.isNotEmpty ? proposal.nurseName[0] : 'م',
                      style: aeroText(
                        size: 20,
                        weight: FontWeight.w700,
                        color: AeroColors.primaryNavy,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Nurse details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              proposal.nurseName,
                              style: aeroText(
                                size: 15,
                                weight: FontWeight.w700,
                                color: AeroColors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.verified_rounded, color: AeroColors.accentTeal, size: 16),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(Icons.star_rounded, color: Colors.amber, size: 15),
                          const SizedBox(width: 3),
                          Text(
                            proposal.ratingAvg.toStringAsFixed(1),
                            style: aeroText(
                              size: 12,
                              weight: FontWeight.w700,
                              color: AeroColors.textPrimary,
                            ),
                          ),
                          Text(
                            ' (${proposal.completedVisitsCount} زيارة)',
                            style: aeroText(size: 11, color: AeroColors.textMuted),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Price Tag
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${proposal.priceAmount} ${proposal.currencyCode}',
                      style: aeroText(
                        size: 15,
                        weight: FontWeight.w800,
                        color: AeroColors.primaryNavy,
                      ),
                    ),
                    Text(
                      'سعر الزيارة الشامل',
                      style: aeroText(size: 10, color: AeroColors.textMuted),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Arrival time banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AeroColors.aeroTintLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AeroColors.accentTeal.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.access_time_filled_rounded, color: AeroColors.accentTeal, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      arrivalText,
                      style: aeroText(
                        size: 13,
                        weight: FontWeight.w600,
                        color: AeroColors.accentTeal,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Note (if any)
            if (proposal.nurseNote != null && proposal.nurseNote!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AeroColors.lightCanvas,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.chat_bubble_outline_rounded, size: 14, color: AeroColors.textMuted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        proposal.nurseNote!,
                        style: aeroText(size: 12, color: AeroColors.textSecondary, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 14),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: AeroButton(
                    isAccepting ? 'جاري التأكيد...' : 'قبول وتأكيد الزيارة',
                    leadingIcon: const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                    isLoading: isAccepting,
                    onPressed: isAccepting || isDeclining ? null : onAccept,
                  ),
                ),
                if (onDecline != null) ...[
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AeroColors.borderSubtle),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      onPressed: isAccepting || isDeclining ? null : onDecline,
                      child: Text(
                        'رفض',
                        style: aeroText(size: 13, weight: FontWeight.w600, color: AeroColors.textMuted),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'م' : 'ص';
    return '$h:$m $period';
  }
}
