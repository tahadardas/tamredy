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
      : status = item['item_status'] == 'PENDING' ? null : '${item['item_status']}',
        quantity = TextEditingController(),
        minutes = TextEditingController(),
        detail = TextEditingController();

  final Map<String, dynamic> item;
  String? status; // null = awaiting explicit nurse documentation
  final TextEditingController quantity;
  final TextEditingController minutes;
  final TextEditingController detail;
  String? itemError;

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
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (kDemoMode) {
        drafts = [
          _OutcomeDraft({
            'id': 'demo',
            'service_title': 'زيارة تمريضية',
            'quantity': 1,
            'expected_minutes': 30,
            'item_status': 'PENDING',
          }),
        ];
      } else {
        final assignment = await widget.c.api.getMap(
          '/v1/nurse/assignments/${widget.c.assignmentId}',
        );
        drafts = [
          for (final item in assignment['items'] as List)
            _OutcomeDraft(Map<String, dynamic>.from(item as Map)),
        ];
      }
    } catch (e) {
      error = explainError(e, fallback: 'تعذر تحميل عناصر الخدمة');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  bool _validateAll() {
    var valid = true;
    for (final draft in drafts.where((d) => d.item['item_status'] == 'PENDING')) {
      draft.itemError = null;
      if (draft.status == null) {
        draft.itemError = 'يرجى اختيار نتيجة الخدمة (تم التنفيذ / لم تنفذ / ألغيت)';
        valid = false;
        continue;
      }
      final detail = draft.detail.text.trim();
      if (detail.isEmpty) {
        draft.itemError = draft.status == 'COMPLETED'
            ? 'يجب كتابة ملاحظة التنفيذ الفعلية'
            : 'يجب توضيح سبب عدم التنفيذ أو الإلغاء';
        valid = false;
        continue;
      }
      if (draft.status == 'COMPLETED') {
        final q = int.tryParse(draft.quantity.text.trim());
        final m = int.tryParse(draft.minutes.text.trim());
        if (q == null || q < 1 || m == null || m < 1) {
          draft.itemError = 'أدخل الكمية المنفذة والمدة الفعلية بالدقائق';
          valid = false;
        }
      }
    }
    return valid;
  }

  Future<void> _submit() async {
    if (saving) return;
    if (!_validateAll()) {
      setState(() {
        error = 'يرجى استكمال توثيق جميع الخدمات المطلوبة قبل الحفظ.';
      });
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      for (final draft in drafts.where((d) => d.item['item_status'] == 'PENDING')) {
        final detail = draft.detail.text.trim();
        final payload = <String, dynamic>{'status': draft.status};
        if (draft.status == 'COMPLETED') {
          payload.addAll({
            'performedQuantity': int.parse(draft.quantity.text.trim()),
            'actualMinutes': int.parse(draft.minutes.text.trim()),
            'note': detail,
          });
        } else {
          payload['reason'] = detail;
        }
        try {
          if (!kDemoMode) {
            final itemId = draft.item['id'];
            await widget.c.api.post(
              '/v1/nurse/requests/${widget.c.requestId}/items/$itemId/outcome',
              payload,
            );
          }
          draft.item['item_status'] = draft.status;
          draft.itemError = null;
        } catch (e) {
          draft.itemError = explainError(e, fallback: 'تعذر حفظ هذا العنصر');
          rethrow;
        }
      }
      await widget.c.complete();
      if (widget.c.stage != NurseStage.completed) {
        throw StateError(
          widget.c.error ?? 'تعذر إنهاء الزيارة؛ تحقق من التوثيق السريري',
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          error = explainError(e, fallback: 'تعذر حفظ بعض نتائج الخدمات');
        });
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  void dispose() {
    for (final draft in drafts) {
      draft.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    return TamScaffold(
      title: 'توثيق نتائج الخدمات',
      subtitle: 'وثّق النتيجة الفعلية لكل خدمة قبل إنهاء الزيارة',
      showBack: true,
      children: [
        if (loading) ...[
          const TamSkeleton.card(height: 140),
          const SizedBox(height: TamSpacing.md),
          const TamSkeleton.card(height: 140),
        ] else if (error != null && drafts.isEmpty) ...[
          TamErrorState(
            title: 'تعذر تحميل عناصر الزيارة',
            message: error!,
            onRetry: _load,
          ),
        ] else ...[
          if (error != null) NoticeBox(error!),
          for (final draft in drafts) _card(context, tc, draft),
          const SizedBox(height: TamSpacing.sm),
          PrimaryButton(
            saving ? 'جارٍ الحفظ والإنهاء...' : 'حفظ النتائج وإنهاء الزيارة',
            onPressed: saving ? null : _submit,
          ),
        ],
      ],
    );
  }

  Widget _card(BuildContext context, TamThemeColors tc, _OutcomeDraft draft) {
    final finalized = draft.item['item_status'] != 'PENDING';
    final expectedQty = draft.item['quantity'] ?? 1;
    final expectedMin = draft.item['expected_minutes'] ?? 30;

    return TamCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${draft.item['service_title']}',
                  style: TamTypography.cardTitle(color: tc.textPrimary),
                ),
              ),
              TamStatusBadge(
                labelOverride: finalized
                    ? 'تم الحفظ'
                    : (draft.status == null ? 'بانتظار التوثيق' : 'جاهز للحفظ'),
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'المطلوب: $expectedQty • المدة المتوقعة: $expectedMin دقيقة',
            style: TamTypography.supporting(color: tc.textSecondary),
          ),
          if (finalized) ...[
            const SizedBox(height: 10),
            Text(
              'النتيجة المسجلة: ${draft.item['item_status']}',
              style: TamTypography.body(color: tc.success, weight: FontWeight.w700),
            ),
          ] else ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: draft.status,
              hint: const Text('اختر نتيجة الخدمة...'),
              decoration: InputDecoration(
                labelText: 'نتيجة الخدمة',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              items: const [
                DropdownMenuItem(value: 'COMPLETED', child: Text('تم التنفيذ')),
                DropdownMenuItem(value: 'SKIPPED', child: Text('لم تنفذ')),
                DropdownMenuItem(value: 'CANCELLED', child: Text('ألغيت')),
              ],
              onChanged: saving
                  ? null
                  : (value) => setState(() {
                        draft.status = value;
                        draft.itemError = null;
                      }),
            ),
            if (draft.status == 'COMPLETED') ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: draft.quantity,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'الكمية المنفذة',
                        hintText: '$expectedQty',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: draft.minutes,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'المدة الفعلية (د)',
                        hintText: '$expectedMin',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (draft.status != null) ...[
              const SizedBox(height: 12),
              TextField(
                controller: draft.detail,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: draft.status == 'COMPLETED'
                      ? 'ملاحظة التنفيذ السريرية'
                      : 'سبب عدم التنفيذ أو الإلغاء',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
            if (draft.itemError != null) ...[
              const SizedBox(height: 8),
              Text(
                draft.itemError!,
                style: TamTypography.supporting(
                  color: tc.danger,
                  weight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
