import 'package:flutter/material.dart';
import '../tokens/aero_colors.dart';
import '../tokens/aero_radii.dart';
import '../tokens/aero_typography.dart';
import 'aero_button.dart';
import 'aero_glass_card.dart';

class AeroScheduleResult {
  final bool isImmediate;
  final DateTime? scheduledDate;
  final String? timeWindow;

  const AeroScheduleResult({
    required this.isImmediate,
    this.scheduledDate,
    this.timeWindow,
  });
}

class AeroSchedulePickerSheet extends StatefulWidget {
  final ValueChanged<AeroScheduleResult> onConfirm;
  final bool initialImmediate;

  const AeroSchedulePickerSheet({
    super.key,
    required this.onConfirm,
    this.initialImmediate = true,
  });

  @override
  State<AeroSchedulePickerSheet> createState() => _AeroSchedulePickerSheetState();
}

class _AeroSchedulePickerSheetState extends State<AeroSchedulePickerSheet> {
  late bool _isImmediate;
  int _selectedDateOffset = 0; // 0 = اليوم, 1 = غداً, 2 = بعد غد
  String _selectedWindow = '10:00 - 12:00';

  final List<String> _windows = [
    '08:00 - 10:00',
    '10:00 - 12:00',
    '12:00 - 14:00',
    '14:00 - 16:00',
    '16:00 - 18:00',
    '18:00 - 20:00',
    '20:00 - 22:00',
  ];

  @override
  void initState() {
    super.initState();
    _isImmediate = widget.initialImmediate;
  }

  DateTime _getSelectedDate() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day + _selectedDateOffset);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title
            Center(
              child: Text(
                'تحديد موعد الزيارة التمريضية',
                style: aeroText(size: 18, weight: FontWeight.w700, color: AeroColors.primaryNavy),
              ),
            ),
            const SizedBox(height: 16),

            // Mode Selector: Immediate vs Scheduled
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _isImmediate = true),
                    child: AeroGlassCard(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      tintColor: _isImmediate ? AeroColors.aeroTint : Colors.white,
                      child: Column(
                        children: [
                          Icon(
                            Icons.bolt,
                            color: _isImmediate ? AeroColors.accentTeal : AeroColors.textMuted,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'الآن (فوري)',
                            style: aeroText(
                              size: 14,
                              weight: _isImmediate ? FontWeight.w700 : FontWeight.w500,
                              color: _isImmediate ? AeroColors.primaryNavy : AeroColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _isImmediate = false),
                    child: AeroGlassCard(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      tintColor: !_isImmediate ? AeroColors.aeroTint : Colors.white,
                      child: Column(
                        children: [
                          Icon(
                            Icons.calendar_month,
                            color: !_isImmediate ? AeroColors.accentTeal : AeroColors.textMuted,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'موعد مسبق',
                            style: aeroText(
                              size: 14,
                              weight: !_isImmediate ? FontWeight.w700 : FontWeight.w500,
                              color: !_isImmediate ? AeroColors.primaryNavy : AeroColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (!_isImmediate) ...[
              // Date Chips
              Text(
                'اختر التاريخ:',
                style: aeroText(size: 14, weight: FontWeight.w600, color: AeroColors.textPrimary),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildDateChip('اليوم', 0),
                  const SizedBox(width: 8),
                  _buildDateChip('غداً', 1),
                  const SizedBox(width: 8),
                  _buildDateChip('بعد غد', 2),
                ],
              ),
              const SizedBox(height: 16),

              // Time Window Chips
              Text(
                'النافذة الزمنية للزيارة (توقيت دمشق UTC+3):',
                style: aeroText(size: 14, weight: FontWeight.w600, color: AeroColors.textPrimary),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _windows.map((w) {
                  final isSelected = _selectedWindow == w;
                  return ChoiceChip(
                    label: Text(w, style: aeroText(size: 12, color: isSelected ? Colors.white : AeroColors.textPrimary)),
                    selected: isSelected,
                    selectedColor: AeroColors.accentTeal,
                    backgroundColor: AeroColors.lightCanvas,
                    onSelected: (selected) {
                      if (selected) setState(() => _selectedWindow = w);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),

              // Buffer notice
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AeroColors.aeroTintLight,
                  borderRadius: BorderRadius.circular(AeroRadii.badge),
                  border: Border.all(color: AeroColors.borderLight),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 16, color: AeroColors.accentTeal),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'يتم احتساب هامش انتقال مدته 30 دقيقة بين المواعيد لضمان التزام الممرض بالوقت المحدد.',
                        style: aeroText(size: 11, color: AeroColors.primaryNavy, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Confirm Button
            AeroButton.teal(
              _isImmediate ? 'تأكيد الطلب الفوري' : 'تثبيت الموعد المجدول',
              onPressed: () {
                Navigator.of(context).pop();
                widget.onConfirm(AeroScheduleResult(
                  isImmediate: _isImmediate,
                  scheduledDate: _isImmediate ? null : _getSelectedDate(),
                  timeWindow: _isImmediate ? null : _selectedWindow,
                ));
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateChip(String label, int offset) {
    final isSelected = _selectedDateOffset == offset;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedDateOffset = offset),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AeroColors.accentTeal : AeroColors.lightCanvas,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isSelected ? AeroColors.accentTeal : AeroColors.borderSubtle),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: aeroText(
              size: 13,
              weight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? Colors.white : AeroColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
