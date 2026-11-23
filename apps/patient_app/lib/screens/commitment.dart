import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';

const _classifications = {
  'BEFORE_ASSIGNMENT': 'إلغاء أثناء البحث',
  'BEFORE_DEPARTURE': 'إلغاء قبل الانطلاق',
  'EN_ROUTE_COUNTED': 'إلغاء أثناء التوجه',
  'NURSE_DELAY': 'إلغاء بسبب تأخر الوصول',
  'ETA_UNAVAILABLE': 'لم يتوفر موعد وصول مرجعي',
  'SYSTEM_ERROR': 'إلغاء بسبب خلل في النظام',
  'EXCUSED': 'إلغاء معذور',
};

const _appealStatuses = {
  'SUBMITTED': 'تم تقديم الاعتراض',
  'UNDER_REVIEW': 'قيد المراجعة',
  'NEEDS_INFORMATION': 'تحتاج المراجعة إلى معلومات إضافية',
  'APPROVED': 'تم قبول الاعتراض',
  'REJECTED': 'تم رفض الاعتراض',
  'CLOSED': 'أُغلق الاعتراض',
};

class CommitmentScreen extends StatefulWidget {
  final TamreedyApi api;
  const CommitmentScreen({super.key, required this.api});

  @override
  State<CommitmentScreen> createState() => _CommitmentScreenState();
}

class _CommitmentScreenState extends State<CommitmentScreen> {
  late Future<Map<String, dynamic>> _history = widget.api.getMap('/v1/me/commitment');

  void _reload() => setState(() => _history = widget.api.getMap('/v1/me/commitment'));

  Future<void> _appeal(String cancellationId) async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => const _AppealDialog(),
    );
    if (!mounted || text == null) return;
    try {
      await widget.api.post('/v1/cancellations/$cancellationId/appeals', {'description': text});
      if (mounted) _reload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(explainError(error, fallback: 'تعذر تقديم الاعتراض. تحقق من مهلة التقديم.')),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _history,
    builder: (context,snapshot) {
      final data = snapshot.data;
      return TamScaffold(
        title: 'سجل الالتزام بالمواعيد',
        subtitle: 'سجل الزيارات والإلغاءات والاعتراضات',
        showBack: true,
        children: [
          if (snapshot.connectionState == ConnectionState.waiting)
            const Center(child: CircularProgressIndicator())
          else if (data == null)
            PrimaryButton('إعادة تحميل السجل',onPressed: _reload)
          else ...[
            TamCard(child: Column(
              children: [
                KeyValueRow('الفترة', '${data['lookbackDays']} يومًا'),
                KeyValueRow('الزيارات المسندة', '${data['assignedVisits']}'),
                KeyValueRow('الإلغاءات المحتسبة', '${data['countedCancellations']}'),
              ],
            )),
            if ((data['items'] as List).isEmpty) const NoticeBox('لا توجد وقائع إلغاء مسجلة.'),
            for (final item in data['items'] as List)
              TamCard(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_classifications[item['classification']] ?? 'إلغاء غير محتسب'),
                  Text('${item['cancelledAt']}'.split('T').first),
                  if (_appealStatuses[item['appealStatus']] case final status?) Text(status),
                  if (item['commitmentImpact'] == true && item['appealId'] == null)
                    TextButton(onPressed: () => _appeal(item['id'] as String), child: const Text('تقديم اعتراض')),
                ],
              )),
          ],
        ],
      );
    },
  );
}

class _AppealDialog extends StatefulWidget {
  const _AppealDialog();

  @override
  State<_AppealDialog> createState() => _AppealDialogState();
}

class _AppealDialogState extends State<_AppealDialog> {
  String _description = '';

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('تقديم اعتراض'),
    content: TextField(
      maxLength: 2000,
      maxLines: 4,
      onChanged: (value) => setState(() => _description = value.trim()),
      decoration: const InputDecoration(labelText: 'سبب طلب المراجعة'),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('رجوع')),
      FilledButton(
        onPressed: _description.isEmpty ? null : () => Navigator.of(context).pop(_description),
        child: const Text('تقديم'),
      ),
    ],
  );
}
