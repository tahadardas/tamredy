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
      final combined = <Map<String, dynamic>>[];
      if (res['visits'] is List) {
        for (final raw in res['visits'] as List) {
          final v = Map<String, dynamic>.from(raw as Map);
          final startStr = (v['appointment_at'] ?? v['accepted_at'])?.toString();
          final mins = int.tryParse('${v['expected_minutes'] ?? 45}') ?? 45;
          final endStr = startStr != null
              ? DateTime.parse(startStr).add(Duration(minutes: mins)).toIso8601String()
              : null;
          combined.add({
            'id': v['request_id'],
            'block_type': 'SCHEDULED_VISIT',
            'title': '${v['service_title'] ?? 'زيارة تمريضية'} — ${v['beneficiary_name'] ?? 'المريض'}',
            'start_time': startStr,
            'end_time': endStr,
          });
        }
      }
      if (res['blocks'] is List) {
        for (final raw in res['blocks'] as List) {
          final b = Map<String, dynamic>.from(raw as Map);
          combined.add({
            'id': b['id'],
            'block_type': 'BUSY_PERSONAL',
            'title': (b['reason']?.toString().trim().isNotEmpty == true)
                ? b['reason'].toString()
                : 'انشغال شخصي',
            'start_time': b['start_time'],
            'end_time': b['end_time'],
          });
        }
      }
      combined.sort((a, b) => '${a['start_time'] ?? ''}'.compareTo('${b['start_time'] ?? ''}'));
      setState(() {
        _blocks
          ..clear()
          ..addAll(combined);
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر تحميل جدول المواعيد، تحقق من الاتصال')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showAddBlockDialog() {
    final reasonCtrl = TextEditingController();
    int hours = 2;
    bool saving = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => Directionality(
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
                DropdownButtonFormField<int>(
                  initialValue: hours,
                  decoration: const InputDecoration(labelText: 'مدة الانشغال من الآن'),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('ساعة واحدة')),
                    DropdownMenuItem(value: 2, child: Text('ساعتان')),
                    DropdownMenuItem(value: 4, child: Text('4 ساعات')),
                    DropdownMenuItem(value: 8, child: Text('8 ساعات')),
                  ],
                  onChanged: (v) {
                    if (v != null) setDlgState(() => hours = v);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonCtrl,
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
                onPressed: saving ? null : () => Navigator.of(ctx).pop(),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        setDlgState(() => saving = true);
                        try {
                          final start = DateTime.now().toUtc();
                          final end = start.add(Duration(hours: hours));
                          await widget.c.api.post('/v1/nurse-calendar/blocks', {
                            'startTime': start.toIso8601String(),
                            'endTime': end.toIso8601String(),
                            if (reasonCtrl.text.trim().isNotEmpty) 'reason': reasonCtrl.text.trim(),
                          });
                          if (ctx.mounted) Navigator.of(ctx).pop();
                          await _loadCalendar();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('تم تسجيل حظر الوقت في جدولك بنجاح')),
                            );
                          }
                        } catch (e) {
                          setDlgState(() => saving = false);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(explainError(e, fallback: 'تعذر حفظ فترة الانشغال'))),
                            );
                          }
                        }
                      },
                child: Text(saving ? 'جارٍ الحفظ...' : 'حفظ'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _removeBlock(String blockId) async {
    try {
      await widget.c.api.delete('/v1/nurse-calendar/blocks/$blockId');
      await _loadCalendar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(explainError(e, fallback: 'تعذر حذف فترة الانشغال'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: tc.background,
        appBar: AppBar(
          title: Text(
            'جدول مواعيد الممرض والزيارات',
            style: aeroText(size: 16, weight: FontWeight.w700, color: tc.textPrimary),
          ),
          backgroundColor: tc.surface,
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            tooltip: 'رجوع',
            icon: Icon(Icons.arrow_back_rounded, color: tc.textPrimary),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          actions: [
            IconButton(
              icon: Icon(Icons.add_circle_outline, color: tc.primary),
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
                          if (blk['block_type'] != 'SCHEDULED_VISIT' && blk['id'] != null)
                            IconButton(
                              tooltip: 'إزالة الحظر',
                              icon: const Icon(Icons.delete_outline, color: Color(0xFFDC2626), size: 20),
                              onPressed: () => _removeBlock(blk['id'].toString()),
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
