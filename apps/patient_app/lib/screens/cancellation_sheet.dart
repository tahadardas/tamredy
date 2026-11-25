import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../controller.dart';

const _reasons = {
  'NO_LONGER_NEEDED': 'لم أعد بحاجة إلى الخدمة',
  'CREATED_BY_MISTAKE': 'أنشأت الطلب عن طريق الخطأ',
  'FOUND_ANOTHER_NURSE': 'وجدت ممرضًا بطريقة أخرى',
  'TIME_NOT_SUITABLE': 'الوقت لم يعد مناسبًا',
  'CHANGE_SERVICE_OR_LOCATION': 'أريد تغيير الخدمة أو الموقع',
  'WAITED_TOO_LONG': 'انتظرت طويلًا',
  'HEALTH_CIRCUMSTANCE_CHANGED': 'تغيّرت الظروف الصحية',
  'SYSTEM_OR_LOCATION_ERROR': 'مشكلة في النظام أو الموقع',
  'OTHER': 'سبب آخر',
};

Future<void> showCancellationSheet(BuildContext context, PatientController c) async {
  if (c.busy) return;
  final policy = await c.loadCancellationPolicy();
  if (!context.mounted) return;
  if (policy == null) {
    TamToast.show(
      context,
      c.error ?? 'تعذر الاتصال بالخادم للتحقق من إمكانية الإلغاء.',
      tone: TamToastTone.error,
    );
    return;
  }
  if (policy['canCancel'] != true) {
    final status = '${policy['status'] ?? ''}';
    final msg = (status == 'OPEN_FOR_PROPOSALS' || status == 'AWAITING_RECOVERY_CHOICE')
        ? 'سياسة الإلغاء في الخادم لم تفعّل الإلغاء لحالة (${requestStatusAr(status)}) بعد.'
        : 'لا يمكن إلغاء الطلب في حالته الحالية (${requestStatusAr(status)}).';
    TamToast.show(context, msg, tone: TamToastTone.warning);
    return;
  }
  await showAeroModalBottomSheet<void>(
    context: context,
    enableDrag: false,
    builder: (_) => _CancellationSheet(controller: c, policy: policy),
  );
}

class _CancellationSheet extends StatefulWidget {
  final PatientController controller;
  final Map<String, dynamic> policy;
  const _CancellationSheet({required this.controller, required this.policy});

  @override
  State<_CancellationSheet> createState() => _CancellationSheetState();
}

class _CancellationSheetState extends State<_CancellationSheet> {
  String? _reason;
  bool _sending = false;

  Future<void> _submit() async {
    final reason = _reason;
    if (_sending || reason == null) return;
    setState(() => _sending = true);
    final success = await widget.controller.cancel(
      reasonCode: reason,
      expectedVersion: (widget.policy['version'] as num?)?.toInt(),
      policyAcknowledged: widget.policy['requiresAcknowledgement'] == true,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (success) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final acknowledgement = widget.policy['requiresAcknowledgement'] == true;
    final description = switch (widget.policy['classification']) {
      'NURSE_DELAY' => 'نعتذر عن تأخر وصول الممرض عن الموعد المتوقع. يمكنك إلغاء الطلب دون أي تأثير على سجل التزامك بالمواعيد. نشكرك على تفهمك، وسنعمل على تحسين جودة الخدمة.',
      'EN_ROUTE_COUNTED' => 'الممرض في طريقه إليك ولم يتجاوز مهلة الوصول المسموح بها. يمكنك إلغاء الزيارة، لكن سيتم تسجيل الإلغاء ضمن سجل الالتزام بالمواعيد في حسابك. وقد يظهر للممرضين مستقبلًا عدد الإلغاءات المحتسبة بعد انطلاق الممرض، دون عرض أسبابك الشخصية.',
      _ => 'الإلغاء مجاني ولا يؤثر على سجل التزامك بالمواعيد.',
    };
    return PopScope(
      canPop: !_sending,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('هل تريد إلغاء الزيارة؟', style: tamText(size: 21, weight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(description),
            const SizedBox(height: 14),
            DropdownMenu<String>(
              expandedInsets: EdgeInsets.zero,
              label: const Text('سبب الإلغاء'),
              enabled: !_sending,
              onSelected: (value) => setState(() => _reason = value),
              dropdownMenuEntries: [
                for (final entry in _reasons.entries)
                  DropdownMenuEntry(value: entry.key, label: entry.value),
              ],
            ),
            const SizedBox(height: 14),
            if (!_sending && widget.controller.error != null)
              NoticeBox(widget.controller.error!),
            PrimaryButton(
              _sending ? 'جارٍ الإلغاء…' : acknowledgement ? 'تأكيد الإلغاء على أي حال' : 'تأكيد الإلغاء',
              onPressed: _sending || _reason == null ? null : _submit,
            ),
            SoftButton('العودة إلى التتبع', onPressed: _sending ? null : () => Navigator.of(context).pop()),
          ],
        ),
      ),
    );
  }
}
