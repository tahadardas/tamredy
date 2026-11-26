import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';

const _classifications = {
  'BEFORE_ASSIGNMENT': 'إلغاء أثناء البحث',
  'BEFORE_DEPARTURE': 'إلغاء قبل الانطلاق',
  'EN_ROUTE_COUNTED': 'إلغاء أثناء التوجه',
  'NURSE_DELAY': 'إلغاء بسبب تأخر الوصول',
  'ETA_UNAVAILABLE': 'لم يتوفر موعد وصول مرجعي',
  'SYSTEM_ERROR': 'إلغاء بسبب خلل تقني',
  'EXCUSED': 'إلغاء معذور',
};

const _appealStatuses = {
  'SUBMITTED': 'تم تقديم الاعتراض',
  'UNDER_REVIEW': 'قيد المراجعة',
  'NEEDS_INFORMATION': 'تحتاج لمعلومات إضافية',
  'APPROVED': 'تم قبول الاعتراض',
  'REJECTED': 'تم رفض الاعتراض',
  'CLOSED': 'مغلق',
};

class CommitmentScreen extends StatefulWidget {
  final TamreedyApi api;

  const CommitmentScreen({super.key, required this.api});

  @override
  State<CommitmentScreen> createState() => _CommitmentScreenState();
}

class _CommitmentScreenState extends State<CommitmentScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    if (kDemoMode) {
      _data = {'lookbackDays': 30, 'assignedVisits': 3, 'countedCancellations': 0, 'items': []};
      _loading = false;
      return;
    }
    try {
      _data = await widget.api.getMap('/v1/me/commitment');
    } catch (e) {
      _error = explainError(e, fallback: 'تعذر تحميل سجل الالتزام');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _appeal(String cancellationId) async {
    final ctrl = TextEditingController();
    final desc = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تقديم اعتراض على الإلغاء'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'اشرح سبب الاعتراض بوضوح'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              if (ctrl.text.trim().length >= 4) Navigator.of(ctx).pop(ctrl.text.trim());
            },
            child: const Text('إرسال الاعتراض'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (desc == null || !mounted) return;
    try {
      await widget.api.post('/v1/cancellations/$cancellationId/appeals', {'description': desc});
      await _load();
      if (mounted) TamToast.show(context, 'تم إرسال الاعتراض للمراجعة', tone: TamToastTone.success);
    } catch (e) {
      if (mounted) TamToast.show(context, explainError(e), tone: TamToastTone.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return TamScaffold(
      title: 'سجل الالتزام بالمواعيد',
      subtitle: 'متابعة الزيارات والإلغاءات والاعتراضات',
      showBack: true,
      onRefresh: _load,
      children: [
        if (_loading)
          const TamSkeleton.card(height: 140)
        else if (_error != null)
          TamErrorState(title: 'تعذر التحميل', message: _error!, onRetry: _load)
        else if (data != null) ...[
          TamCard(
            child: Column(
              children: [
                KeyValueRow('فترة الاحتساب', '${data['lookbackDays'] ?? 30} يوماً'),
                KeyValueRow('الزيارات المسندة', '${data['assignedVisits'] ?? 0}'),
                KeyValueRow('الإلغاءات المحتسبة', '${data['countedCancellations'] ?? 0}'),
              ],
            ),
          ),
          if ((data['items'] as List? ?? const []).isEmpty)
            const TamEmptyState(
              icon: Icons.verified_outlined,
              title: 'سجلك ممتاز',
              message: 'لا توجد وقائع إلغاء مسجلة خلال الفترة الحالية.',
            )
          else
            for (final item in (data['items'] as List).whereType<Map>())
              TamCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _classifications[item['classification']] ?? 'إلغاء غير محتسب',
                      style: aeroText(size: 14.5, weight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text('${item['cancelledAt'] ?? ''}'.split('T').first,
                        style: aeroText(size: 12, color: context.tamColors.textSecondary)),
                    if (_appealStatuses[item['appealStatus']] case final String st)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: StatusChip(st),
                      ),
                    if (item['commitmentImpact'] == true && item['appealId'] == null)
                      TextButton(
                        onPressed: () => _appeal('${item['id']}'),
                        child: const Text('تقديم اعتراض'),
                      ),
                  ],
                ),
              ),
        ],
      ],
    );
  }
}
