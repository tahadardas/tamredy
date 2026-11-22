import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';

/// Shows [child] only once staff verified the nurse's licence; until then the nurse
/// uploads documents here and watches the approval status.
class NurseApprovalGate extends StatefulWidget {
  final TamreedyApi api;
  final WidgetBuilder child;
  final VoidCallback onLogout;
  const NurseApprovalGate({
    super.key,
    required this.api,
    required this.child,
    required this.onLogout,
  });
  @override
  State<NurseApprovalGate> createState() => _NurseApprovalGateState();
}

class _NurseApprovalGateState extends State<NurseApprovalGate> {
  Map<String, dynamic>? _s;
  bool _failed = false, _busy = false;
  String? _msg;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    if (kDemoMode) return;
    _load();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await widget.api.getMap('/v1/nurse/me/onboarding');
      if (mounted) {
        setState(() {
          _s = s;
          _failed = false;
        });
      }
    } catch (e) {
      final str = e.toString();
      if (str.contains('401') || str.contains('AUTH_REQUIRED') || str.contains('Unauthorized')) {
        widget.onLogout();
        return;
      }
      if (mounted && _s == null) setState(() => _failed = true);
    }
  }

  Future<void> _upload(String kind) async {
    String? ref, expires;
    if (kind == 'LICENSE' || kind == 'PRACTICE_CERT') {
      final r = await _askLicense();
      if (r == null) return;
      ref = r.$1;
      expires = r.$2;
    }
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (picked == null) return;
    if ((await picked.length() ?? 0) > 8 * 1024 * 1024) {
      return setState(() => _msg = 'الملف أكبر من 8 ميغابايت');
    }
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      await widget.api.uploadNurseDocument(
        bytes: await picked.readAsBytes(),
        filename: picked.name,
        kind: kind,
        licenseRef: ref,
        expiresAt: expires,
      );
      _msg = 'تم رفع المستند بنجاح';
      await _load();
    } catch (e) {
      _msg = explainError(e, fallback: 'تعذر رفع المستند: تأكد أن الملف PDF أو صورة JPG/PNG');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<(String, String)?> _askLicense() async {
    final ref = TextEditingController();
    DateTime? date;
    return showDialog<(String, String)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text('بيانات رخصة المزاولة', style: tamText(weight: FontWeight.w800)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ref,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(hintText: 'رقم الرخصة'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: DateTime.now().add(const Duration(days: 365)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365 * 15)),
                  );
                  if (d != null) set(() => date = d);
                },
                child: Text(
                  date == null
                      ? 'تاريخ انتهاء الرخصة'
                      : date!.toIso8601String().substring(0, 10),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            TextButton(
              onPressed: () {
                if (ref.text.trim().isEmpty || date == null) return;
                Navigator.pop(ctx, (ref.text.trim(), date!.toIso8601String().substring(0, 10)));
              },
              child: const Text('متابعة واختيار الملف'),
            ),
          ],
        ),
      ),
    );
  }

  static const _kinds = {
    'LICENSE': 'رخصة مزاولة المهنة',
    'PRACTICE_CERT': 'شهادة مزاولة المهنة',
    'ID': 'الهوية',
    'DEGREE': 'الشهادة',
    'PHOTO': 'صورة شخصية',
  };
  static const _licenseText = {
    'PENDING': 'قيد المراجعة من الإدارة',
    'APPROVED': 'معتمدة',
    'REJECTED': 'مرفوضة',
    'NEEDS_INFO': 'تحتاج معلومات إضافية',
  };

  @override
  Widget build(BuildContext context) {
    if (kDemoMode || (_s?['verified'] == true)) return widget.child(context);
    if (_s == null) {
      return Scaffold(
        body: Center(
          child: _failed
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('تعذر الاتصال بالخادم'),
                    TextButton(onPressed: _load, child: const Text('إعادة المحاولة')),
                    TextButton(onPressed: widget.onLogout, child: const Text('تسجيل الخروج')),
                  ],
                )
              : const CircularProgressIndicator(),
        ),
      );
    }
    final lic = _s!['license'] as Map<String, dynamic>?;
    final docs = List<Map<String, dynamic>>.from(
      (_s!['documents'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
    );
    final status = lic?['review_status'] as String?;
    return TamScaffold(
      title: 'استكمال التسجيل',
      subtitle: 'أهلًا ${_s!['name'] ?? ''} — رقمك ${_s!['nurseNo'] ?? ''}',
      children: [
        HeroCard(
          title: lic == null
              ? 'ارفع رخصة مزاولة المهنة'
              : 'حالة الرخصة: ${_licenseText[status] ?? status}',
          body: lic == null
              ? 'لن تصلك طلبات قبل أن تعتمد الإدارة رخصتك.'
              : status == 'REJECTED' || status == 'NEEDS_INFO'
              ? 'السبب: ${lic['review_reason'] ?? '—'}. يمكنك رفع رخصة جديدة.'
              : 'سنُعلمك فور الاعتماد. تُحدَّث الحالة تلقائيًا.',
        ),
        for (final e in _kinds.entries)
          SoftButton(
            'رفع ${e.value}',
            onPressed: _busy ? null : () => _upload(e.key),
          ),
        if (_msg != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(_msg!, style: tamText(size: 12, color: TamreedyColors.subtext)),
          ),
        if (docs.isNotEmpty) ...[
          Text('المستندات المرفوعة', style: tamText(weight: FontWeight.w800)),
          for (final d in docs)
            TamCard(
              child: Text('${_kinds[d['kind']] ?? d['kind']} — ${d['original_name']}', style: tamText(size: 13)),
            ),
        ],
        PrimaryButton('تحديث الحالة', onPressed: _busy ? null : _load),
        SoftButton('تسجيل الخروج', onPressed: widget.onLogout),
        const NoticeBox('مستنداتك تُحفظ مشفّرة ولا يطّلع عليها إلا فريق الاعتماد.'),
      ],
    );
  }
}
