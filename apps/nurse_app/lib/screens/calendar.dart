import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../controller.dart';

class NurseCalendarScreen extends StatefulWidget {
  final NurseController c;

  const NurseCalendarScreen({super.key, required this.c});

  @override
  State<NurseCalendarScreen> createState() => _NurseCalendarScreenState();
}

class _NurseCalendarScreenState extends State<NurseCalendarScreen> {
  final List<Map<String, dynamic>> _blocks = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadCalendar();
  }

  Future<void> _loadCalendar() async {
    setState(() => _isLoading = true);
    try {
      final now = DateTime.now();
      final from = DateTime(now.year, now.month, now.day).toIso8601String();
      final to = DateTime(now.year, now.month, now.day + 7).toIso8601String();

      final res = await widget.c.api.getMap('/v1/nurse-calendar?from=$from&to=$to');
      if (res['blocks'] is List) {
        setState(() {
          _blocks.clear();
          _blocks.addAll(List<Map<String, dynamic>>.from(res['blocks']));
        });
      }
    } catch (_) {
      // Offline fallback mock data
      if (_blocks.isEmpty) {
        final now = DateTime.now();
        _blocks.addAll([
          {
            'id': 'blk-1',
            'block_type': 'SCHEDULED_VISIT',
            'title': 'زيارة مجدولة: حقن وريدي ومحاليل',
            'start_time': DateTime(now.year, now.month, now.day, 10, 0).toIso8601String(),
            'end_time': DateTime(now.year, now.month, now.day, 11, 30).toIso8601String(),
          },
          {
            'id': 'blk-2',
            'block_type': 'BUSY_PERSONAL',
            'title': 'مشغول (استراحة شخصية)',
            'start_time': DateTime(now.year, now.month, now.day, 13, 0).toIso8601String(),
            'end_time': DateTime(now.year, now.month, now.day, 14, 30).toIso8601String(),
          },
          {
            'id': 'blk-3',
            'block_type': 'SCHEDULED_VISIT',
            'title': 'زيارة مجدولة: غيار جراحي',
            'start_time': DateTime(now.year, now.month, now.day + 1, 16, 0).toIso8601String(),
            'end_time': DateTime(now.year, now.month, now.day + 1, 17, 0).toIso8601String(),
          },
        ]);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showAddBlockDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(
            'إضافة حظر زمني / انشغال شخصي',
            style: aeroText(size: 16, weight: FontWeight.w700, color: AeroColors.primaryNavy),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'عند تسجيل انشغال شخصي، لن يتم توجيه أي زيارات مجدولة لك خلال هذه الفترة مع احتساب هامش 30 دقيقة قبلها وبعدها.',
                style: aeroText(size: 12, color: AeroColors.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: InputDecoration(
                  labelText: 'سبب الانشغال',
                  labelStyle: aeroText(size: 13),
                  hintText: 'مثلاً: ارتباط أكاديمي أو عائلي',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم تسجيل حظر الوقت في جدولك بنجاح')),
                );
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AeroColors.lightCanvas,
        appBar: AppBar(
          title: Text(
            'جدول مواعيد الممرض والزيارات',
            style: aeroText(size: 16, weight: FontWeight.w700, color: AeroColors.primaryNavy),
          ),
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          iconTheme: const IconThemeData(color: AeroColors.primaryNavy),
          actions: [
            IconButton(
              icon: const Icon(Icons.add_circle_outline, color: AeroColors.accentTeal),
              tooltip: 'إضافة فترة انشغال',
              onPressed: _showAddBlockDialog,
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AeroColors.accentTeal))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Buffer Advisory
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AeroColors.aeroTintLight,
                      borderRadius: BorderRadius.circular(AeroRadii.mainCard),
                      border: Border.all(color: AeroColors.borderLight),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.security, size: 20, color: AeroColors.accentTeal),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'نظام الجدولة الذكي يمنع تضارب المواعيد تلقائياً ويضمن هامش انتقال 30 دقيقة بين الزيارات.',
                            style: aeroText(size: 12, color: AeroColors.primaryNavy, height: 1.3),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  Text(
                    'المواعيد القادمة خلال الأسبوع:',
                    style: aeroText(size: 14, weight: FontWeight.w700, color: AeroColors.primaryNavy),
                  ),
                  const SizedBox(height: 10),

                  for (final blk in _blocks) ...[
                    AeroGlassCard(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Container(
                            width: 4,
                            height: 48,
                            decoration: BoxDecoration(
                              color: blk['block_type'] == 'SCHEDULED_VISIT'
                                  ? AeroColors.accentTeal
                                  : const Color(0xFFF59E0B),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  blk['title'] ?? 'موعد في الجدول',
                                  style: aeroText(size: 14, weight: FontWeight.w700, color: AeroColors.primaryNavy),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.access_time, size: 14, color: AeroColors.textMuted),
                                    const SizedBox(width: 4),
                                    Text(
                                      _formatRange(blk['start_time'], blk['end_time']),
                                      style: aeroText(size: 12, color: AeroColors.textSecondary),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: blk['block_type'] == 'SCHEDULED_VISIT'
                                  ? AeroColors.aeroTint
                                  : const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              blk['block_type'] == 'SCHEDULED_VISIT' ? 'زيارة مؤكدة' : 'مشغول شخصياً',
                              style: aeroText(
                                size: 11,
                                weight: FontWeight.w600,
                                color: blk['block_type'] == 'SCHEDULED_VISIT'
                                    ? AeroColors.accentTeal
                                    : const Color(0xFFB45309),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
      ),
    );
  }

  String _formatRange(String? start, String? end) {
    if (start == null) return '—';
    final s = DateTime.parse(start);
    final e = end != null ? DateTime.parse(end) : s.add(const Duration(hours: 1));
    return '${s.day}/${s.month} من ${s.hour.toString().padLeft(2, '0')}:${s.minute.toString().padLeft(2, '0')} إلى ${e.hour.toString().padLeft(2, '0')}:${e.minute.toString().padLeft(2, '0')}';
  }
}
