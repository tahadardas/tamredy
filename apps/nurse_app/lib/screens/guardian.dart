import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../controller.dart';
import '../guardian.dart';
import 'night_preference.dart';

Future<void> openGuardian(BuildContext context, NurseController nurse) async {
  final guardian = nurse.guardian;
  guardian.refreshSession();
  guardian.refreshSos();
  guardian.location.sync();
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
      listenable: Listenable.merge([nurse, safety, safety.location]),
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
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => TrustedContactsScreen(api: nurse.api),
                  )),
                  icon: const Icon(Icons.contact_phone_outlined),
                  label: const Text('جهات الاتصال الموثوقة'),
                ),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => EmergencyDirectoryScreen(api: nurse.api),
                  )),
                  icon: const Icon(Icons.phone_outlined),
                  label: const Text('دليل الطوارئ'),
                ),
                _SosPanel(guardian: safety),
                NightPreference(api: nurse.api),
                const SizedBox(height: 16),
                if (assignment != null && (onVisit || nurse.stage == NurseStage.assigned))
                  AeroButton.danger(
                    'إنهاء المهمة لأسباب السلامة',
                    onPressed: safety.busy ? null : () async {
                      final accepted = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('إنهاء المهمة لأسباب السلامة؟'),
                          content: const Text('ينهي الإجراء المهمة ويسجل بلاغًا للمتابعة. يمكنك المغادرة دون كتابة تفاصيل.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context), child: const Text('رجوع')),
                            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('تأكيد إنهاء المهمة')),
                          ],
                        ),
                      );
                      if (accepted == true) await nurse.safeAbort();
                    },
                  ),
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
                if (safety.sessionId != null) ...[
                  const Text(
                    'يُسجل GPS لأغراض السلامة أثناء الجلسة، عندما يكون التطبيق في المقدمة.',
                  ),
                  if (safety.location.capturing)
                    OutlinedButton(
                      onPressed: safety.location.stop,
                      child: const Text('إيقاف تسجيل الموقع'),
                    )
                  else
                    OutlinedButton(
                      onPressed: safety.location.starting
                          ? null
                          : safety.startLocation,
                      child: const Text('بدء تسجيل الموقع'),
                    ),
                ],
                if (safety.location.queued > 0)
                  TextButton(
                    onPressed: safety.location.sync,
                    child: Text(
                      'مزامنة نقاط الموقع المعلقة (${safety.location.queued})',
                    ),
                  ),
                if (safety.location.error != null)
                  NoticeBox(safety.location.error!),
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
            'UNKNOWN' => 'توقفت المهمة. يمكنك تحديث حالة بلاغ السلامة.',
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
        if (guardian.sosTriggeredAt case final DateTime time)
          KeyValueRow(
            'وقت طلب الاستغاثة',
            '${MaterialLocalizations.of(context).formatMediumDate(time)} • ${TimeOfDay.fromDateTime(time).format(context)}',
          ),
        if (guardian.sosReceivedAt case final DateTime time)
          KeyValueRow(
            'وقت تسجيل البلاغ على الخادم',
            '${MaterialLocalizations.of(context).formatMediumDate(time)} • ${TimeOfDay.fromDateTime(time).format(context)}',
          ),
        if (guardian.sosStorageUnavailable && guardian.sosUnconfirmed)
          const NoticeBox(
            'تعذر حفظ البلاغ على الجهاز. اترك التطبيق مفتوحًا لإعادة المحاولة.',
          ),
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
