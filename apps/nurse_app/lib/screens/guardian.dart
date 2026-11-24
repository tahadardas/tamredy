import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../controller.dart';
import '../guardian.dart';

Future<void> openGuardian(BuildContext context, NurseController nurse) async {
  final guardian = nurse.guardian;
  guardian.refreshSession();
  guardian.refreshSos();
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => _GuardianSheet(nurse: nurse),
  );
}

class _GuardianSheet extends StatelessWidget {
  final NurseController nurse;
  const _GuardianSheet({required this.nurse});

  static const _responses = {
    'OK': 'أنا بخير',
    'MORE_TIME': 'أحتاج وقتًا إضافيًا',
    'HELP': 'أحتاج مساعدة',
    'SAFE_EXIT': 'أطلب الخروج الآمن',
  };

  @override
  Widget build(BuildContext context) {
    final safety = nurse.guardian;
    return ListenableBuilder(
      listenable: Listenable.merge([nurse, safety]),
      builder: (context, _) {
        final assignment = nurse.assignmentId;
        final onVisit = [
          NurseStage.enRoute,
          NurseStage.arrived,
          NurseStage.inService,
        ].contains(nurse.stage);
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionTitle('سلامة الممرض'),
                _SosPanel(guardian: safety),
                const SizedBox(height: 16),
                if (safety.sessionId != null) ...[
                  const StatusChip('جلسة السلامة مفتوحة'),
                  const Text(
                    'أكّد المغادرة الآمنة عند الابتعاد عن مكان الزيارة.',
                  ),
                  OutlinedButton(
                    onPressed: safety.busy
                        ? null
                        : () async {
                            final yes = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text(
                                  'هل غادرت مكان الزيارة بأمان؟',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('رجوع'),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text('تأكيد المغادرة'),
                                  ),
                                ],
                              ),
                            );
                            if (yes == true) await safety.checkout();
                          },
                    child: const Text('تأكيد المغادرة الآمنة'),
                  ),
                ] else if (assignment != null && onVisit)
                  OutlinedButton(
                    onPressed: safety.busy
                        ? null
                        : () => safety.start(assignment),
                    child: const Text('بدء جلسة السلامة لهذه الزيارة'),
                  ),
                if (safety.checkin != null) ...[
                  const SectionTitle('هل أنت بخير؟'),
                  for (final choice in _responses.entries)
                    if ((safety.pendingResponse == null ||
                            safety.pendingResponse == choice.key) &&
                        (choice.key != 'MORE_TIME' ||
                            safety.checkin?['snoozed_at'] == null ||
                            safety.pendingResponse == 'MORE_TIME'))
                      OutlinedButton(
                        onPressed: safety.busy
                            ? null
                            : () => safety.respond(choice.key),
                        child: Text(
                          safety.pendingResponse == null
                              ? choice.value
                              : 'إعادة إرسال الرد',
                        ),
                      ),
                ],
                if (safety.error != null) NoticeBox(safety.error!),
                OutlinedButton.icon(
                  onPressed: safety.busy ? null : safety.refreshSession,
                  icon: const Icon(Icons.refresh),
                  label: const Text('تحديث جلسة السلامة'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SosPanel extends StatelessWidget {
  final GuardianController guardian;
  const _SosPanel({required this.guardian});

  @override
  Widget build(BuildContext context) {
    final state = guardian.event?['state'];
    final message = guardian.sendingSos
        ? 'جارٍ إرسال الاستغاثة…'
        : guardian.sosUnconfirmed
        ? 'لم يؤكد الخادم تسجيل البلاغ. أعد المحاولة عند توفر الاتصال.'
        : switch (state) {
            'RECEIVED' => 'سجّل الخادم البلاغ. بانتظار استلام موظف السلامة.',
            'ACKNOWLEDGED' => 'استلم موظف السلامة البلاغ.',
            'ESCALATED' => 'صعّد موظف السلامة البلاغ.',
            'IN_PROGRESS' => 'بدأت معالجة البلاغ.',
            'RESOLVED' ||
            'FALSE_ALARM' ||
            'CLOSED' => 'أُغلقت متابعة هذا البلاغ.',
            _ => null,
          };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (message != null)
          Semantics(liveRegion: true, child: NoticeBox(message)),
        if (guardian.statusUnavailable)
          const NoticeBox('تعذر تحديث حالة البلاغ. تُعرض آخر حالة مؤكدة.'),
        if (state == null || guardian.eventClosed)
          AeroButton.danger(
            guardian.sosUnconfirmed
                ? 'إعادة إرسال الاستغاثة'
                : 'إرسال استغاثة صامتة',
            isLoading: guardian.sendingSos,
            onPressed: guardian.sendingSos ? null : guardian.sendSos,
          ),
        if (state != null)
          TextButton(
            onPressed: guardian.refreshSos,
            child: const Text('تحديث حالة البلاغ'),
          ),
      ],
    );
  }
}
