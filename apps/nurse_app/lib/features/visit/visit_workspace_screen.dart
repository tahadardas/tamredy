import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/nurse_session_coordinator.dart';
import '../../guardian.dart';
import '../communication/nurse_chat_screen.dart';
import '../safety/guardian_sheet.dart';
import 'clinical_notes_screen.dart';
import 'post_visit_report_screen.dart';
import 'service_outcomes_screen.dart';
import 'visit_store.dart';
import 'pending_cash_collection_store.dart';

class VisitWorkspaceScreen extends StatelessWidget {
  final NurseSessionCoordinator session;

  const VisitWorkspaceScreen({super.key, required this.session});

  Future<void> _showArrivalOverrideDialog(BuildContext context, VisitStore store) async {
    var reason = '';
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDlg) => AlertDialog(
          title: const Text('توثيق سبب الوصول خارج النطاق'),
          content: TextField(
            maxLength: 500,
            maxLines: 3,
            decoration: const InputDecoration(hintText: 'اذكر سبب عدم تطابق GPS مع العنوان'),
            onChanged: (v) => setDlg(() => reason = v.trim()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('إلغاء')),
            TextButton(
              onPressed: reason.length < 5 ? null : () => Navigator.of(dialogContext).pop(reason),
              child: const Text('تأكيد الوصول'),
            ),
          ],
        ),
      ),
    );
    if (result != null) {
      await store.arrive(overrideReason: result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;

    return ListenableBuilder(
      listenable: session.visit,
      builder: (context, _) {
        final v = session.visit;
        final phase = v.phase;

        if (v.activeUnpaidInvoice != null && !v.hasActiveWork) {
          return _CompletedCollectionView(session: session);
        }

        if (phase == NurseVisitPhase.idle || phase == NurseVisitPhase.scheduled) {
          return TamScaffold(
            title: 'تفاصيل الزيارة',
            subtitle: phase == NurseVisitPhase.scheduled
                ? 'موعد محجوز لم يدخل نافذة الانطلاق بعد'
                : 'لا توجد زيارة نشطة حالياً',
            showBack: true,
            children: [
              if (v.syncError != null) NoticeBox(v.syncError!),
              if (v.cancellationNotice != null) NoticeBox(v.cancellationNotice!),
              TamEmptyState(
                icon: Icons.check_circle_outline_rounded,
                title: phase == NurseVisitPhase.scheduled ? 'زيارة مجدولة قادمة' : 'اكتملت المهمة أو أُغلقت',
                message: phase == NurseVisitPhase.scheduled
                    ? 'ستُفتح خطوات الزيارة والعنوان تلقائياً عند دخول نافذة الانطلاق.'
                    : 'يمكنك العودة للوحة الممرض واستقبال طلبات جديدة.',
              ),
              PrimaryButton('العودة للوحة الممرض', onPressed: () => Navigator.of(context).maybePop()),
            ],
          );
        }

        if (phase == NurseVisitPhase.completed) {
          return _CompletedCollectionView(session: session);
        }

        final header = switch (phase) {
          NurseVisitPhase.assigned => ('تم إسناد الزيارة', 'أكّد الانطلاق عند بدء التوجه للمريض'),
          NurseVisitPhase.enRoute => ('في الطريق إلى المريض', 'تتم مشاركة موقعك المباشر أثناء القيادة'),
          NurseVisitPhase.arrived => ('وصلت إلى موقع الزيارة', 'ابدأ الزيارة التمريضية عند الجاهزية'),
          NurseVisitPhase.inService => ('الزيارة قيد التنفيذ', 'وثّق العلامات الحيوية ونتائج الخدمات'),
          _ => ('إدارة الزيارة', ''),
        };

        return TamScaffold(
          title: header.$1,
          subtitle: header.$2,
          showBack: true,
          onRefresh: v.restoreActiveAssignment,
          children: [
            if (v.syncError != null) NoticeBox(v.syncError!),
            if (v.error != null) NoticeBox(v.error!),
            TamStepper(
              steps: const ['إسناد', 'في الطريق', 'وصول', 'تنفيذ', 'إنهاء'],
              currentStep: switch (phase) {
                NurseVisitPhase.assigned => 0,
                NurseVisitPhase.enRoute => 1,
                NurseVisitPhase.arrived => 2,
                NurseVisitPhase.inService => 3,
                _ => 4,
              },
            ),
            const SizedBox(height: TamSpacing.md),
            if (phase != NurseVisitPhase.inService && v.destination != null) ...[
              TamMap(
                height: 270,
                patient: v.destination,
                nurse: v.nursePos,
                route: v.route,
              ),
              const SizedBox(height: 12),
            ],
            TamCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(v.serviceTitle ?? 'زيارة تمريضية',
                      style: aeroText(size: 16, weight: FontWeight.w800, color: tc.textPrimary)),
                  const SizedBox(height: 6),
                  if (v.beneficiaryName != null) KeyValueRow('المستفيد', v.beneficiaryName!),
                  if (v.addressText != null) KeyValueRow('العنوان', v.addressText!),
                  if (phase == NurseVisitPhase.enRoute && v.route != null)
                    KeyValueRow('الوصول المقدر', '${v.route!.etaLabel} • ${v.route!.distanceLabel}'),
                ],
              ),
            ),
            if (v.destination != null && phase != NurseVisitPhase.inService)
              OutlinedButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse(
                    'https://www.google.com/maps/dir/?api=1&travelmode=driving&destination=${v.destination!.latitude},${v.destination!.longitude}',
                  ),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.navigation_outlined),
                label: const Text('فتح الملاحة في خرائط جوجل'),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: SoftButton(
                    'محادثة المريض',
                    onPressed: v.requestId == null
                        ? null
                        : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => NurseChatScreen(
                                  session: session,
                                  requestId: v.requestId!,
                                  patientName: v.patientName ?? 'المريض',
                                ),
                              ),
                            ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SoftButton(
                    'اتصال صوتي آمن',
                    onPressed: v.requestId == null
                        ? null
                        : () => session.callManager.startOutgoing(
                              requestId: v.requestId!,
                              peerName: v.patientName ?? 'المريض',
                              peerRole: 'المريض / المستفيد',
                            ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (phase == NurseVisitPhase.assigned)
              AeroButton(
                'بدأت التوجه إلى المريض',
                isLoading: v.busy,
                onPressed: v.busy ? null : v.depart,
              )
            else if (phase == NurseVisitPhase.enRoute) ...[
              AeroButton(
                'أكّد الوصول إلى الموقع',
                isLoading: v.busy,
                onPressed: v.busy ? null : () => v.arrive(),
              ),
              if (v.arrivalOverrideAvailable) ...[
                const SizedBox(height: 8),
                SoftButton(
                  'توثيق استثناء الموقع (GPS)',
                  onPressed: v.busy ? null : () => _showArrivalOverrideDialog(context, v),
                ),
              ],
            ] else if (phase == NurseVisitPhase.arrived)
              AeroButton(
                'بدء تنفيذ الزيارة',
                isLoading: v.busy,
                onPressed: v.busy ? null : v.startService,
              )
            else if (phase == NurseVisitPhase.inService) ...[
              PrimaryButton(
                'توثيق العلامات الحيوية والملاحظات',
                onPressed: v.requestId == null
                    ? null
                    : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => NurseClinicalNotesScreen(
                              session: session,
                              requestId: v.requestId!,
                              patientName: v.patientName ?? 'المريض',
                            ),
                          ),
                        ),
              ),
              AeroButton(
                'توثيق نتائج الخدمات وإنهاء الزيارة',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ServiceOutcomesScreen(session: session),
                  ),
                ),
              ),
            ],
            if (guardianEnabled) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: tc.danger),
                onPressed: () => openGuardianSheet(context, session),
                icon: const Icon(Icons.shield_outlined),
                label: const Text('مركز الأمان أو إنهاء المهمة اضطرارياً'),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _CompletedCollectionView extends StatefulWidget {
  final NurseSessionCoordinator session;
  const _CompletedCollectionView({required this.session});

  @override
  State<_CompletedCollectionView> createState() => _CompletedCollectionViewState();
}

class _CompletedCollectionViewState extends State<_CompletedCollectionView> {
  final _amountCtrl = TextEditingController();
  String? _fieldError;

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _collect() async {
    FocusScope.of(context).unfocus();
    final amt = int.tryParse(_amountCtrl.text.trim());
    if (amt == null || amt <= 0) {
      setState(() => _fieldError = 'أدخل مبلغاً نقدياً صحيحاً أكبر من صفر');
      return;
    }
    setState(() => _fieldError = null);
    await _showOutcome(await widget.session.visit.collectCash(amt));
  }

  Future<void> _showOutcome(CashCollectionOutcome outcome) async {
    if (!mounted || outcome == CashCollectionOutcome.failed) return;
    _amountCtrl.clear();
    await widget.session.finance.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    final v = widget.session.visit;
    final bill = v.bill;
    final paid = bill?.status == 'PAID';

    if (v.invoiceAbsent) {
      return TamScaffold(
        title: 'أُغلقت الزيارة دون تقديم خدمات',
        subtitle: 'لا توجد فاتورة للتحصيل',
        showBack: true,
        children: [
          NoticeBox(v.visitOutcomeReason ?? 'لم تُنفذ الخدمات خلال هذه الزيارة'),
          PrimaryButton('العودة إلى وضع الاستعداد', onPressed: () {
            v.finishAndReturnAvailable();
            Navigator.of(context).maybePop();
          }),
        ],
      );
    }

    return TamScaffold(
      title: 'إنهاء الزيارة والتحصيل',
      subtitle: paid ? 'تم التحصيل بالكامل بنجاح' : 'تحصيل القيمة النقدية من المريض',
      showBack: true,
      onRefresh: v.loadBill,
      children: [
        if (bill == null)
          if (v.billLoading)
            const TamSkeleton.card(height: 160)
          else
            TamErrorState(title: 'تعذر تحميل الفاتورة', message: v.error ?? 'أعد تحميل تفاصيل الفاتورة', onRetry: v.loadBill)
        else ...[
          TamCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  paid ? 'تم استلام كامل المبلغ' : 'المبلغ المطلوب تحصيله من المريض',
                  style: aeroText(size: 13, color: tc.textSecondary),
                ),
                const SizedBox(height: 4),
                Text(
                  bill.money('payable').formatted,
                  style: aeroText(size: 28, weight: FontWeight.w800, color: tc.primary),
                ),
                const Divider(height: 20),
                KeyValueRow('مدة الزيارة', '${bill.minutes} دقيقة'),
                KeyValueRow('المستلم حتى الآن', bill.money('collected').formatted),
                KeyValueRow('المتبقي', bill.money('remaining').formatted),
                KeyValueRow('صافي حصتك من الزيارة', bill.money('nurseEarning').formatted),
                if (bill.money('tip').amountMinor > BigInt.zero) KeyValueRow('إكرامية المريض (لك كاملة)', bill.money('tip').formatted),
              ],
            ),
          ),
          if (!paid)
            TamCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('تسجيل المبلغ المستلم نقداً',
                      style: aeroText(size: 15, weight: FontWeight.w800)),
                  if (bill.remaining > 0) ...[
                    const SizedBox(height: 8),
                    ActionChip(
                      avatar: Icon(Icons.bolt_rounded, size: 16, color: tc.primary),
                      label: Text('تعبئة كامل المتبقي (${bill.money('remaining').formatted})'),
                      onPressed: () {
                        setState(() {
                          _amountCtrl.text = '${bill.remaining}';
                          _fieldError = null;
                        });
                      },
                    ),
                  ],
                  const SizedBox(height: 10),
                  TamTextField(
                    controller: _amountCtrl,
                    hint: 'أدخل المبلغ نقدًا (${bill.currencyCode})',
                    errorText: _fieldError,
                    keyboardType: TextInputType.number,
                    textDirection: TextDirection.ltr,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  const SizedBox(height: 12),
                  AeroButton.teal(
                    'تأكيد استلام المبلغ',
                    isLoading: v.collecting,
                    onPressed: v.canStartCashCollection ? _collect : null,
                  ),
                ],
              ),
            ),
          if (v.collectionMessage != null) NoticeBox(v.collectionMessage!),
          if (v.billIsStale || (v.pendingCashCollection != null && !v.canResumeCashCollection)) ...[
            NoticeBox(v.error ?? 'تحقق من مزامنة الفاتورة قبل تسجيل دفعة أخرى'),
            SoftButton('تحديث الفاتورة', onPressed: v.billLoading ? null : () async { await v.loadBill(); }),
          ],
          if (!bill.cashCollectionSupported && !kDemoMode)
            const NoticeBox('عملة الفاتورة أو دقتها تتطلب مراجعة الإدارة قبل التحصيل'),
          if (v.canResumeCashCollection)
            SoftButton('تحقق من الدفعة السابقة أو أعد المحاولة بالمفتاح نفسه',
              onPressed: () async => _showOutcome(await v.resumeCashCollection())),
          if (paid) ...[
            SoftButton(
              'كتابة تقرير ما بعد الزيارة (داخلي)',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PostVisitReportScreen(session: widget.session),
                ),
              ),
            ),
            AeroButton(
              'العودة إلى وضع الاستعداد',
              onPressed: () {
                v.finishAndReturnAvailable();
                Navigator.of(context).popUntil((r) => r.isFirst);
              },
            ),
          ],
        ],
      ],
    );
  }
}
