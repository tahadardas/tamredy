import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../controller.dart';

class ServiceOutcomesScreen extends StatefulWidget {
  const ServiceOutcomesScreen({super.key, required this.c});
  final NurseController c;

  @override
  State<ServiceOutcomesScreen> createState() => _ServiceOutcomesScreenState();
}

class _OutcomeDraft {
  _OutcomeDraft(this.item)
      : status = item['item_status'] == 'PENDING' ? 'COMPLETED' : '${item['item_status']}',
        quantity = TextEditingController(text: '${item['quantity'] ?? 1}'),
        minutes = TextEditingController(text: '${item['expected_minutes'] ?? 1}'),
        detail = TextEditingController();

  final Map<String, dynamic> item;
  String status;
  final TextEditingController quantity;
  final TextEditingController minutes;
  final TextEditingController detail;

  void dispose() {
    quantity.dispose();
    minutes.dispose();
    detail.dispose();
  }
}

class _ServiceOutcomesScreenState extends State<ServiceOutcomesScreen> {
  bool loading = true;
  bool saving = false;
  String? error;
  List<_OutcomeDraft> drafts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (kDemoMode) {
        drafts = [_OutcomeDraft({'id': 'demo', 'service_title': 'زيارة تمريضية', 'quantity': 1, 'expected_minutes': 30, 'item_status': 'PENDING'})];
      } else {
        final assignment = await widget.c.api.getMap('/v1/nurse/assignments/${widget.c.assignmentId}');
        drafts = [for (final item in assignment['items'] as List) _OutcomeDraft(Map<String, dynamic>.from(item as Map))];
      }
    } catch (e) {
      error = explainError(e, fallback: 'تعذر تحميل عناصر الخدمة');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _submit() async {
    if (saving) return;
    setState(() { saving = true; error = null; });
    try {
      for (final draft in drafts.where((d) => d.item['item_status'] == 'PENDING')) {
        final detail = draft.detail.text.trim();
        if (detail.isEmpty) throw const FormatException('يجب كتابة ملاحظة التنفيذ أو سبب عدم التنفيذ لكل خدمة');
        final payload = <String, dynamic>{'status': draft.status};
        if (draft.status == 'COMPLETED') {
          final quantity = int.tryParse(draft.quantity.text);
          final minutes = int.tryParse(draft.minutes.text);
          if (quantity == null || quantity < 1 || minutes == null || minutes < 1) {
            throw const FormatException('تحقق من الكمية والمدة لكل خدمة منفذة');
          }
          payload.addAll({'performedQuantity': quantity, 'actualMinutes': minutes, 'note': detail});
        } else {
          payload['reason'] = detail;
        }
        if (!kDemoMode) {
          final itemId = draft.item['id'];
          await widget.c.api.post('/v1/nurse/requests/${widget.c.requestId}/items/$itemId/outcome', payload);
        }
        draft.item['item_status'] = draft.status;
      }
      await widget.c.complete();
      if (widget.c.stage != NurseStage.completed) {
        throw StateError(widget.c.error ?? 'تعذر إنهاء الزيارة؛ تحقق من التوثيق السريري');
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => error = e is FormatException ? e.message : explainError(e, fallback: 'تعذر حفظ نتائج الخدمات'));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  void dispose() {
    for (final draft in drafts) { draft.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('نتائج الخدمات')),
    body: loading
      ? const Center(child: CircularProgressIndicator())
      : ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(error!, style: const TextStyle(color: Colors.red))),
            for (final draft in drafts) _card(draft),
            PrimaryButton('حفظ النتائج وإنهاء الزيارة', onPressed: saving ? null : _submit),
          ],
        ),
  );

  Widget _card(_OutcomeDraft draft) {
    final finalized = draft.item['item_status'] != 'PENDING';
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${draft.item['service_title']}', style: const TextStyle(fontWeight: FontWeight.bold)),
          if (finalized) Text('تم توثيق النتيجة: ${draft.item['item_status']}') else ...[
            DropdownButtonFormField<String>(
              initialValue: draft.status,
              items: const [
                DropdownMenuItem(value: 'COMPLETED', child: Text('تم التنفيذ')),
                DropdownMenuItem(value: 'SKIPPED', child: Text('لم تنفذ')),
                DropdownMenuItem(value: 'CANCELLED', child: Text('ألغيت')),
              ],
              onChanged: (value) => setState(() => draft.status = value ?? draft.status),
            ),
            if (draft.status == 'COMPLETED') Row(children: [
              Expanded(child: TextField(controller: draft.quantity, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الكمية المنفذة'))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: draft.minutes, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'المدة بالدقائق'))),
            ]),
            TextField(
              controller: draft.detail,
              maxLines: 3,
              decoration: InputDecoration(labelText: draft.status == 'COMPLETED' ? 'ملاحظة التنفيذ' : 'سبب عدم التنفيذ'),
            ),
          ],
        ]),
      ),
    );
  }
}
