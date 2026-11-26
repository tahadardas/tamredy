import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../../app/patient_router.dart';
import '../../core/patient_session_coordinator.dart';

const _reasons = {
  'NO_LONGER_NEEDED': 'لم أعد بحاجة إلى الخدمة',
  'CREATED_BY_MISTAKE': 'أنشأت الطلب عن طريق الخطأ',
  'FOUND_ANOTHER_NURSE': 'وجدت ممرضاً بطريقة أخرى',
  'TIME_NOT_SUITABLE': 'الوقت لم يعد مناسباً',
  'CHANGE_SERVICE_OR_LOCATION': 'أريد تغيير الخدمة أو الموقع',
  'WAITED_TOO_LONG': 'انتظرت طويلاً',
  'HEALTH_CIRCUMSTANCE_CHANGED': 'تغيّرت الظروف الصحية',
  'SYSTEM_OR_LOCATION_ERROR': 'مشكلة في النظام أو الموقع',
  'OTHER': 'سبب آخر',
};

Future<void> showPatientCancellationSheet(
  BuildContext context,
  PatientSessionCoordinator session,
  String requestId,
) async {
  Map<String, dynamic> policy;
  try {
    policy = await session.requests.loadCancellationPolicy(requestId);
  } catch (e) {
    if (context.mounted) {
      TamToast.show(context, explainError(e, fallback: 'تعذر التحقق من سياسة الإلغاء'), tone: TamToastTone.error);
    }
    return;
  }

  if (!context.mounted) return;
  if (policy['canCancel'] != true) {
    final status = '${policy['status'] ?? ''}';
    TamToast.show(
      context,
      'لا يمكن إلغاء الطلب في حالته الحالية (${requestStatusAr(status)}).',
      tone: TamToastTone.warning,
    );
    return;
  }

  await showAeroModalBottomSheet<void>(
    context: context,
    enableDrag: false,
    builder: (_) => _CancellationSheetBody(
      session: session,
      requestId: requestId,
      policy: policy,
    ),
  );
}

class _CancellationSheetBody extends StatefulWidget {
  final PatientSessionCoordinator session;
  final String requestId;
  final Map<String, dynamic> policy;

  const _CancellationSheetBody({
    required this.session,
    required this.requestId,
    required this.policy,
  });

  @override
  State<_CancellationSheetBody> createState() => _CancellationSheetBodyState();
}

class _CancellationSheetBodyState extends State<_CancellationSheetBody> {
  String? _reason;
  bool _sending = false;
  final _noteCtrl = TextEditingController();

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirmCancel() async {
    final reason = _reason;
    if (_sending || reason == null) return;
    setState(() => _sending = true);
    try {
      await widget.session.requests.cancelRequest(
        widget.requestId,
        reasonCode: reason,
        reasonNote: _noteCtrl.text,
        expectedVersion: (widget.policy['version'] as num?)?.toInt(),
        policyAcknowledged: widget.policy['requiresAcknowledgement'] == true,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      PatientRouter.switchTab(0);
      TamToast.show(context, 'تم إلغاء الطلب بنجاح', tone: TamToastTone.success);
    } catch (e) {
      if (mounted) {
        TamToast.show(context, explainError(e, fallback: 'تعذر إلغاء الطلب'), tone: TamToastTone.error);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final acknowledgement = widget.policy['requiresAcknowledgement'] == true;
    final description = switch (widget.policy['classification']) {
      'NURSE_DELAY' =>
        'نعتذر عن تأخر الممرض عن الموعد المتوقع. الإلغاء مجاني ولن يؤثر على سجل التزامك.',
      'EN_ROUTE_COUNTED' =>
        'الممرض في طريقه إليك حالياً. سيتم تسجيل هذا الإلغاء ضمن سجل الالتزام بالمواعيد.',
      _ => 'الإلغاء مجاني ولا يؤثر على سجل التزامك بالمواعيد.',
    };

    return PopScope(
      canPop: !_sending,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('تأكيد إلغاء الطلب', style: aeroText(size: 19, weight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(description, style: aeroText(size: 13.5, height: 1.5)),
            const SizedBox(height: 14),
            DropdownMenu<String>(
              expandedInsets: EdgeInsets.zero,
              label: const Text('اختر سبب الإلغاء'),
              enabled: !_sending,
              onSelected: (v) => setState(() => _reason = v),
              dropdownMenuEntries: [
                for (final e in _reasons.entries)
                  DropdownMenuEntry(value: e.key, label: e.value),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteCtrl,
              enabled: !_sending,
              decoration: const InputDecoration(
                labelText: 'ملاحظة إضافية (اختياري)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            AeroButton(
              _sending
                  ? 'جارٍ تنفيذ الإلغاء...'
                  : (acknowledgement ? 'أفهم وأؤكد الإلغاء' : 'تأكيد إلغاء الطلب'),
              variant: AeroButtonVariant.danger,
              isLoading: _sending,
              onPressed: (_sending || _reason == null) ? null : _confirmCancel,
            ),
            const SizedBox(height: 8),
            SoftButton(
              'التراجع وإبقاء الطلب',
              onPressed: _sending ? null : () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
