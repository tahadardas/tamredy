import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../../core/nurse_session_coordinator.dart';

class _OutcomeDraft {
  final Map<String, dynamic> item;
  String? status; // null until nurse explicitly chooses COMPLETED | SKIPPED | CANCELLED
  final TextEditingController qtyCtrl;
  final TextEditingController minsCtrl;
  final TextEditingController noteCtrl;
  String? error;

  _OutcomeDraft(this.item, {Map<String, dynamic>? saved})
      : status = saved?['status']?.toString() ??
            (item['item_status'] == 'PENDING' ? null : '${item['item_status']}'),
        qtyCtrl = TextEditingController(
          text: '${saved?['qty'] ?? item['quantity'] ?? 1}',
        ),
        minsCtrl = TextEditingController(
          text: '${saved?['mins'] ?? item['expected_minutes'] ?? 30}',
        ),
        noteCtrl = TextEditingController(text: '${saved?['note'] ?? ''}');

  void dispose() {
    qtyCtrl.dispose();
    minsCtrl.dispose();
    noteCtrl.dispose();
  }
}

class ServiceOutcomesScreen extends StatefulWidget {
  final NurseSessionCoordinator session;

  const ServiceOutcomesScreen({super.key, required this.session});

  @override
  State<ServiceOutcomesScreen> createState() => _ServiceOutcomesScreenState();
}

class _ServiceOutcomesScreenState extends State<ServiceOutcomesScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<_OutcomeDraft> _drafts = [];

  String get _draftKey => 'nurse_outcomes_draft_${widget.session.visit.assignmentId}';

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
    try {
      Map<String, dynamic> savedMap = const {};
      final rawSaved = await widget.session.api.readLocal(_draftKey);
      if (rawSaved != null && rawSaved.isNotEmpty) {
        final dec = jsonDecode(rawSaved);
        if (dec is Map) savedMap = Map<String, dynamic>.from(dec);
      }

      if (!kDemoMode && widget.session.visit.assignmentId != null) {
        await widget.session.visit.refreshAssignmentDetail();
      }
      final items = widget.session.visit.items;
      _drafts = [
        for (final it in items)
          _OutcomeDraft(
            it,
            saved: savedMap['${it['id']}'] is Map
                ? Map<String, dynamic>.from(savedMap['${it['id']}'] as Map)
                : null,
          ),
      ];
    } catch (e) {
      _error = explainError(e, fallback: 'تعذر تحميل قائمة الخدمات');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _persistLocalDraft() async {
    final map = <String, dynamic>{};
    for (final d in _drafts) {
      map['${d.item['id']}'] = {
        'status': d.status,
        'qty': d.qtyCtrl.text.trim(),
        'mins': d.minsCtrl.text.trim(),
        'note': d.noteCtrl.text.trim(),
      };
    }
    await widget.session.api.writeLocal(_draftKey, jsonEncode(map));
  }

  bool _validate() {
    var ok = true;
    for (final d in _drafts.where((d) => d.item['item_status'] == 'PENDING')) {
      d.error = null;
      if (d.status == null) {
        d.error = 'يرجى تحديد نتيجة التنفيذ لهذه الخدمة';
        ok = false;
        continue;
      }
      if (d.noteCtrl.text.trim().isEmpty) {
        d.error = d.status == 'COMPLETED'
            ? 'أدخل ملاحظة التنفيذ الفعلية'
            : 'أدخل سبب التخطي أو الإلغاء';
        ok = false;
        continue;
      }
      if (d.status == 'COMPLETED') {
        final q = int.tryParse(d.qtyCtrl.text.trim());
        final m = int.tryParse(d.minsCtrl.text.trim());
        if (q == null || q < 1 || m == null || m < 1) {
          d.error = 'أدخل الكمية والمدة الفعلية بالدقائق';
          ok = false;
        }
      }
    }
    return ok;
  }

  Future<void> _submitAndComplete() async {
    if (_saving) return;
    if (!_validate()) {
      setState(() => _error = 'يرجى استكمال توثيق جميع الخدمات المطلوبة أولاً');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final reqId = widget.session.visit.requestId;
      for (final d in _drafts.where((d) => d.item['item_status'] == 'PENDING')) {
        final payload = <String, dynamic>{'status': d.status};
        if (d.status == 'COMPLETED') {
          payload.addAll({
            'performedQuantity': int.parse(d.qtyCtrl.text.trim()),
            'actualMinutes': int.parse(d.minsCtrl.text.trim()),
            'note': d.noteCtrl.text.trim(),
          });
        } else {
          payload['reason'] = d.noteCtrl.text.trim();
        }
        if (!kDemoMode && reqId != null) {
          await widget.session.api.post(
            '/v1/nurse/requests/$reqId/items/${d.item['id']}/outcome',
            payload,
          );
        }
        d.item['item_status'] = d.status;
      }

      await widget.session.api.writeLocal(_draftKey, null);
      await widget.session.visit.completeVisit();

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = explainError(e, fallback: 'تعذر حفظ نتائج الخدمات أو إنهاء الزيارة'));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    for (final d in _drafts) {
      d.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;

    return TamScaffold(
      title: 'توثيق نتائج الخدمات',
      subtitle: 'حدّد الحالة الفعلية لكل خدمة قبل إنهاء الزيارة',
      showBack: true,
      children: [
        if (_loading)
          const TamSkeleton.card(height: 180)
        else if (_drafts.isEmpty && _error != null)
          TamErrorState(title: 'تعذر تحميل الخدمات', message: _error!, onRetry: _load)
        else ...[
          if (_error != null) NoticeBox(_error!),
          for (final d in _drafts)
            TamCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${d.item['title_ar'] ?? d.item['service_title'] ?? 'خدمة تمريضية'}',
                    style: aeroText(size: 15, weight: FontWeight.w800, color: tc.textPrimary),
                  ),
                  const SizedBox(height: 8),
                  if (d.item['item_status'] != 'PENDING')
                    StatusChip('تم التوثيق: ${requestStatusAr('${d.item['item_status']}')}')
                  else ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        ChoiceChip(
                          label: const Text('تم التنفيذ'),
                          selected: d.status == 'COMPLETED',
                          onSelected: (_) {
                            setState(() => d.status = 'COMPLETED');
                            _persistLocalDraft();
                          },
                        ),
                        ChoiceChip(
                          label: const Text('تم تخطيها'),
                          selected: d.status == 'SKIPPED',
                          onSelected: (_) {
                            setState(() => d.status = 'SKIPPED');
                            _persistLocalDraft();
                          },
                        ),
                        ChoiceChip(
                          label: const Text('ألغيت'),
                          selected: d.status == 'CANCELLED',
                          onSelected: (_) {
                            setState(() => d.status = 'CANCELLED');
                            _persistLocalDraft();
                          },
                        ),
                      ],
                    ),
                    if (d.status == 'COMPLETED') ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: d.qtyCtrl,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              decoration: const InputDecoration(labelText: 'الكمية المنفذة', border: OutlineInputBorder(), isDense: true),
                              onChanged: (_) => _persistLocalDraft(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: d.minsCtrl,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              decoration: const InputDecoration(labelText: 'المدة (دقيقة)', border: OutlineInputBorder(), isDense: true),
                              onChanged: (_) => _persistLocalDraft(),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    TextField(
                      controller: d.noteCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: d.status == 'COMPLETED' ? 'ملاحظات التنفيذ' : 'السبب أو التوضيح',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) => _persistLocalDraft(),
                    ),
                    if (d.error != null) ...[
                      const SizedBox(height: 6),
                      Text(d.error!, style: aeroText(size: 12, color: tc.danger)),
                    ],
                  ],
                ],
              ),
            ),
          AeroButton(
            _saving ? 'جارٍ الحفظ والإنهاء...' : 'حفظ النتائج وإنهاء الزيارة',
            isLoading: _saving,
            onPressed: _saving ? null : _submitAndComplete,
          ),
        ],
      ],
    );
  }
}
