import 'package:flutter/material.dart';
import '../tokens/aero_colors.dart';
import '../tokens/aero_radii.dart';
import '../tokens/aero_typography.dart';
import 'aero_button.dart';
import 'aero_glass_card.dart';

enum AeroBookingMode {
  instant,
  openMarketplace,
  scheduled,
}

/// AeroBookingModePickerSheet — Allows patient to choose their preferred booking mode
class AeroBookingModePickerSheet extends StatelessWidget {
  final AeroBookingMode initialMode;
  final ValueChanged<AeroBookingMode> onSelectMode;

  const AeroBookingModePickerSheet({
    super.key,
    required this.initialMode,
    required this.onSelectMode,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AeroColors.borderSubtle,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            'اختر طريقة الحجز',
            textAlign: TextAlign.center,
            style: aeroText(size: 18, weight: FontWeight.w700, color: AeroColors.primaryNavy),
          ),
          const SizedBox(height: 6),
          Text(
            'حدد الطريقة الأنسب لتأمين الرعاية التمريضية',
            textAlign: TextAlign.center,
            style: aeroText(size: 13, color: AeroColors.textSecondary),
          ),
          const SizedBox(height: 20),
          _buildModeCard(
            context: context,
            mode: AeroBookingMode.instant,
            title: 'طلب فوري الآن',
            subtitle: 'توزيع فوري على أقرب الممرضين في منطقتك والوصول بأسرع وقت',
            icon: Icons.bolt_rounded,
            tag: 'الأسرع وصولاً',
            tagColor: AeroColors.accentTeal,
            isSelected: initialMode == AeroBookingMode.instant,
          ),
          const SizedBox(height: 12),
          _buildModeCard(
            context: context,
            mode: AeroBookingMode.openMarketplace,
            title: 'السوق المفتوح',
            subtitle: 'نشر الطلب للممرضين المؤهلين واستقبال عروض الجاهزية والوقت',
            icon: Icons.storefront_rounded,
            tag: 'مرونة أعلى',
            tagColor: AeroColors.primaryNavy,
            isSelected: initialMode == AeroBookingMode.openMarketplace,
          ),
          const SizedBox(height: 12),
          _buildModeCard(
            context: context,
            mode: AeroBookingMode.scheduled,
            title: 'حجز موعد مسبق',
            subtitle: 'حدد اليوم وساعة الزيارة مسبقاً بما يناسب برنامجك',
            icon: Icons.event_available_rounded,
            tag: 'مواعيد مؤكدة',
            tagColor: AeroColors.info,
            isSelected: initialMode == AeroBookingMode.scheduled,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildModeCard({
    required BuildContext context,
    required AeroBookingMode mode,
    required String title,
    required String subtitle,
    required IconData icon,
    required String tag,
    required Color tagColor,
    required bool isSelected,
  }) {
    return GestureDetector(
      onTap: () {
        onSelectMode(mode);
        Navigator.of(context).pop();
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? AeroColors.aeroTintLight : Colors.white,
          borderRadius: AeroRadii.mainCardRadius,
          border: Border.all(
            color: isSelected ? AeroColors.accentTeal : AeroColors.borderLight,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: AeroColors.primaryNavy.withValues(alpha: isSelected ? 0.08 : 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isSelected ? AeroColors.accentTeal : AeroColors.lightCanvas,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: isSelected ? Colors.white : AeroColors.primaryNavy,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: aeroText(
                            size: 15,
                            weight: FontWeight.w700,
                            color: AeroColors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: tagColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          tag,
                          style: aeroText(size: 11, weight: FontWeight.w600, color: tagColor),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: aeroText(size: 12, color: AeroColors.textSecondary, height: 1.3),
                  ),
                ],
              ),
            ),
            Icon(
              isSelected ? Icons.check_circle_rounded : Icons.arrow_forward_ios_rounded,
              color: isSelected ? AeroColors.accentTeal : AeroColors.textMuted,
              size: isSelected ? 22 : 16,
            ),
          ],
        ),
      ),
    );
  }
}

/// AeroInstantTimeoutSheet — Modal displayed when instant search expires without nurse acceptance
class AeroInstantTimeoutSheet extends StatelessWidget {
  final VoidCallback onKeepOpenInMarketplace;
  final VoidCallback onRetryInstant;
  final VoidCallback onScheduleVisit;
  final VoidCallback onCancelRequest;

  const AeroInstantTimeoutSheet({
    super.key,
    required this.onKeepOpenInMarketplace,
    required this.onRetryInstant,
    required this.onScheduleVisit,
    required this.onCancelRequest,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AeroColors.borderSubtle,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Container(
            width: 56,
            height: 56,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AeroColors.warning.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.hourglass_empty_rounded,
              color: AeroColors.warning,
              size: 28,
            ),
          ),
          Text(
            'لم نجد ممرضاً متاحاً فوراً',
            textAlign: TextAlign.center,
            style: aeroText(size: 18, weight: FontWeight.w700, color: AeroColors.primaryNavy),
          ),
          const SizedBox(height: 6),
          Text(
            'الممرضون الأقرب إليك منشغلون حالياً. يمكنك ترك الطلب مفتوحاً ليصلك إشعار فور جاهزية أي ممرض.',
            textAlign: TextAlign.center,
            style: aeroText(size: 13, color: AeroColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 22),

          // Option 1: Keep Open (Recommended)
          AeroButton(
            'إبقاء الطلب مفتوحاً لاستقبال العروض',
            leadingIcon: const Icon(Icons.storefront_rounded, color: Colors.white, size: 20),
            onPressed: () {
              Navigator.of(context).pop();
              onKeepOpenInMarketplace();
            },
          ),
          const SizedBox(height: 10),

          // Option 2: Retry Instant
          AeroButton(
            'إعادة البحث الفوري الآن',
            variant: AeroButtonVariant.secondary,
            leadingIcon: const Icon(Icons.refresh_rounded, color: AeroColors.primaryNavy, size: 20),
            onPressed: () {
              Navigator.of(context).pop();
              onRetryInstant();
            },
          ),
          const SizedBox(height: 10),

          // Option 3: Schedule
          AeroButton(
            'تحديد موعد زيارة مجدولة لاحقاً',
            variant: AeroButtonVariant.ghost,
            leadingIcon: const Icon(Icons.calendar_today_rounded, color: AeroColors.textPrimary, size: 20),
            onPressed: () {
              Navigator.of(context).pop();
              onScheduleVisit();
            },
          ),
          const SizedBox(height: 6),

          // Option 4: Free Cancel
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              onCancelRequest();
            },
            child: Text(
              'إلغاء الطلب (مجاناً)',
              style: aeroText(size: 13, weight: FontWeight.w600, color: AeroColors.danger),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

/// AeroProposalSubmissionSheet — Used by nurses to submit readiness arrival proposal
class AeroProposalSubmissionSheet extends StatefulWidget {
  final String requestId;
  final String serviceTitle;
  final String approximateArea;
  final double distanceKm;
  final int netEarnings;
  final Future<void> Function(int? estimatedMinutes, String? specificTime, String? note) onSubmit;

  const AeroProposalSubmissionSheet({
    super.key,
    required this.requestId,
    required this.serviceTitle,
    required this.approximateArea,
    required this.distanceKm,
    required this.netEarnings,
    required this.onSubmit,
  });

  @override
  State<AeroProposalSubmissionSheet> createState() => _AeroProposalSubmissionSheetState();
}

class _AeroProposalSubmissionSheetState extends State<AeroProposalSubmissionSheet> {
  int _selectedMinutes = 30;
  final TextEditingController _noteController = TextEditingController();
  bool _isSubmitting = false;

  final List<int> _minutesChoices = [15, 30, 45, 60, 90, 120];

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    setState(() => _isSubmitting = true);
    try {
      final note = _noteController.text.trim();
      await widget.onSubmit(
        _selectedMinutes,
        null,
        note.isEmpty ? null : note,
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AeroColors.borderSubtle,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            'إرسال عرض جاهزية',
            textAlign: TextAlign.center,
            style: aeroText(size: 18, weight: FontWeight.w700, color: AeroColors.primaryNavy),
          ),
          const SizedBox(height: 4),
          Text(
            'حدد الوقت الذي تلتزم بالوصول فيه إلى المريض',
            textAlign: TextAlign.center,
            style: aeroText(size: 13, color: AeroColors.textSecondary),
          ),
          const SizedBox(height: 16),

          // Summary Card
          AeroGlassCard(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AeroColors.accentTeal.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.location_on_rounded, color: AeroColors.accentTeal, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.serviceTitle,
                        style: aeroText(size: 14, weight: FontWeight.w700, color: AeroColors.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${widget.approximateArea} • تبعد حوالي ${widget.distanceKm.toStringAsFixed(1)} كم',
                        style: aeroText(size: 12, color: AeroColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'صافي أرباحك',
                      style: aeroText(size: 11, color: AeroColors.textMuted),
                    ),
                    Text(
                      '${widget.netEarnings} ل.س',
                      style: aeroText(size: 14, weight: FontWeight.w700, color: AeroColors.success),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Arrival time selection
          Text(
            'أستطيع الوصول خلال:',
            style: aeroText(size: 13, weight: FontWeight.w600, color: AeroColors.textPrimary),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _minutesChoices.map((mins) {
              final isSelected = _selectedMinutes == mins;
              final label = mins < 60 ? '$mins دقيقة' : '${mins ~/ 60} ساعة${mins % 60 > 0 ? " و${mins % 60} د" : ""}';
              return ChoiceChip(
                label: Text(
                  label,
                  style: aeroText(
                    size: 13,
                    weight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? Colors.white : AeroColors.textPrimary,
                  ),
                ),
                selected: isSelected,
                selectedColor: AeroColors.accentTeal,
                backgroundColor: AeroColors.lightCanvas,
                side: BorderSide(
                  color: isSelected ? AeroColors.accentTeal : AeroColors.borderLight,
                ),
                onSelected: (val) {
                  if (val) {
                    setState(() => _selectedMinutes = mins);
                  }
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Optional note
          TextField(
            controller: _noteController,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'ملاحظة للمريض (مثال: جاهز فوراً ومعي المستلزمات المعقمة)...',
              hintStyle: aeroText(size: 12, color: AeroColors.textMuted),
              filled: true,
              fillColor: AeroColors.lightCanvas,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: AeroColors.borderLight),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: AeroColors.borderLight),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AeroColors.accentTeal),
              ),
            ),
            style: aeroText(size: 13),
          ),
          const SizedBox(height: 20),

          // Submit Button
          AeroButton(
            _isSubmitting ? 'جاري الإرسال...' : 'تأكيد وإرسال العرض',
            leadingIcon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
            isLoading: _isSubmitting,
            onPressed: _isSubmitting ? null : _handleSubmit,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
