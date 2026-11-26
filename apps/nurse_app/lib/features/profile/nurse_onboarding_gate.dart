import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';

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
  Map<String, dynamic>? _statusData;
  bool _failed = false;
  bool _busy = false;
  String? _message;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    if (!kDemoMode) {
      _load();
      _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await widget.api.getMap('/v1/nurse/me/onboarding');
      if (mounted) {
        setState(() {
          _statusData = res;
          _failed = false;
        });
      }
    } catch (e) {
      final s = '$e';
      if (s.contains('401') || s.contains('AUTH_REQUIRED') || s.contains('Unauthorized')) {
        widget.onLogout();
        return;
      }
      if (mounted && _statusData == null) setState(() => _failed = true);
    }
  }

  Future<void> _upload(String kind) async {
    String? ref, expires;
    if (kind == 'LICENSE' || kind == 'PRACTICE_CERT') {
      final info = await _askLicenseDetails();
      if (info == null) return;
      ref = info.$1;
      expires = info.$2;
    }

    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (file == null) return;
    final len = await file.length();
    if (len == null || len == 0 || len > 8 * 1024 * 1024) {
      if (mounted) setState(() => _message = 'اختر ملفاً بحجم لا يتجاوز 8 ميغابايت');
      return;
    }

    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.api.uploadNurseDocument(
        bytes: await file.readAsBytes(),
        filename: file.name,
        kind: kind,
        licenseRef: ref,
        expiresAt: expires,
      );
      _message = 'تم رفع المستند بنجاح';
      await _load();
    } catch (e) {
      _message = explainError(e, fallback: 'تعذر رفع المستند');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<(String, String)?> _askLicenseDetails() async {
    final refCtrl = TextEditingController();
    DateTime? expiry;
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('بيانات رخصة المزاولة'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: refCtrl,
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
                  if (d != null) setDlg(() => expiry = d);
                },
                child: Text(expiry == null ? 'تاريخ انتهاء الرخصة' : expiry!.toIso8601String().substring(0, 10)),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            TextButton(
              onPressed: () {
                if (refCtrl.text.trim().isEmpty || expiry == null) return;
                Navigator.pop(ctx, (refCtrl.text.trim(), expiry!.toIso8601String().substring(0, 10)));
              },
              child: const Text('متابعة'),
            ),
          ],
        ),
      ),
    );
    refCtrl.dispose();
    return result;
  }

  static const _kinds = {
    'LICENSE': 'رخصة مزاولة المهنة',
    'PRACTICE_CERT': 'شهادة مزاولة المهنة',
    'ID': 'الهوية الشخصية',
    'DEGREE': 'الشهادة العلمية',
    'PHOTO': 'الصورة الشخصية',
  };

  @override
  Widget build(BuildContext context) {
    if (kDemoMode || _statusData?['verified'] == true) {
      return widget.child(context);
    }
    if (_statusData == null) {
      if (!_failed) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return TamScaffold(
        title: 'حالة الاعتماد المهني',
        subtitle: 'التحقق من حساب الممرض',
        children: [
          TamErrorState(
            title: 'تعذر الاتصال بالخادم',
            message: 'تحقق من الاتصال ثم أعد المحاولة.',
            onRetry: () {
              setState(() => _failed = false);
              _load();
            },
          ),
          const SizedBox(height: 12),
          AeroButton.secondary('تسجيل الخروج', onPressed: widget.onLogout),
        ],
      );
    }

    final lic = _statusData!['license'] as Map<String, dynamic>?;
    final docs = (_statusData!['documents'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final licStatus = lic?['review_status']?.toString();

    return TamScaffold(
      title: 'استكمال ملف الاعتماد',
      subtitle: 'أهلاً ${_statusData!['name'] ?? ''}',
      children: [
        HeroCard(
          title: lic == null ? 'ارفع رخصة مزاولة المهنة' : 'حالة الرخصة: $licStatus',
          body: lic == null
              ? 'لن تتلقى طلبات زيارات قبل اعتماد الإدارة لوثائقك.'
              : licStatus == 'REJECTED' || licStatus == 'NEEDS_INFO'
                  ? 'ملاحظة الإدارة: ${lic['review_reason'] ?? '—'}'
                  : 'المستندات قيد المراجعة من الإدارة.',
        ),
        for (final e in _kinds.entries)
          SoftButton('رفع ${e.value}', onPressed: _busy ? null : () => _upload(e.key)),
        if (_message != null) NoticeBox(_message!),
        for (final d in docs)
          TamCard(
            child: Text('${_kinds[d['kind']] ?? d['kind']} — ${d['original_name'] ?? ''}'),
          ),
        PrimaryButton('تحديث حالة الاعتماد', onPressed: _busy ? null : _load),
        SoftButton('تسجيل الخروج', onPressed: widget.onLogout),
      ],
    );
  }
}
