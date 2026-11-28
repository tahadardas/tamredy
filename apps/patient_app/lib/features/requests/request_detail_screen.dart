import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../../app/patient_router.dart';
import '../../core/patient_session_coordinator.dart';
import '../communication/visit_chat_screen.dart';
import '../finance/invoice_payment_screen.dart';
import '../tracking/tracking_screen.dart';
import 'cancellation_sheet.dart';
import 'open_proposals_screen.dart';

class RequestDetailScreen extends StatefulWidget {
  final PatientSessionCoordinator session;
  final String requestId;

  const RequestDetailScreen({
    super.key,
    required this.session,
    required this.requestId,
  });

  @override
  State<RequestDetailScreen> createState() => _RequestDetailScreenState();
}

class _RequestDetailScreenState extends State<RequestDetailScreen> {
  bool _busyAction = false;

  @override
  void initState() {
    super.initState();
    widget.session.requests.loadRequestDetail(widget.requestId);
  }

  Future<void> _uploadEvidence(String type) async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
      );
      if (file == null) return;
      final length = await file.length();
      if (length == null || length == 0 || length > 8 * 1024 * 1024) {
        if (mounted) {
          TamToast.show(context, 'حجم الملف غير صالح أو يتجاوز 8 ميغابايت', tone: TamToastTone.warning);
        }
        return;
      }
      final bytes = await file.readAsBytes();
      setState(() => _busyAction = true);
      await widget.session.api.uploadClinicalEvidence(
        widget.requestId,
        type,
        bytes,
        file.name,
      );
      await widget.session.requests.loadRequestDetail(widget.requestId);
      if (mounted) {
        TamToast.show(context, 'تم رفع المستند للمراجعة السريرية بنجاح', tone: TamToastTone.success);
      }
    } catch (e) {
      if (mounted) TamToast.show(context, explainError(e), tone: TamToastTone.error);
    } finally {
      if (mounted) setState(() => _busyAction = false);
    }
  }

  Future<void> _switchToOpen() async {
    setState(() => _busyAction = true);
    try {
      await widget.session.requests.switchToOpenMarketplace(widget.requestId);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => OpenProposalsScreen(session: widget.session, requestId: widget.requestId),
        ),
      );
    } catch (e) {
      if (mounted) TamToast.show(context, explainError(e), tone: TamToastTone.error);
    } finally {
      if (mounted) setState(() => _busyAction = false);
    }
  }

  Future<void> _retryInstant() async {
    setState(() => _busyAction = true);
    try {
      await widget.session.requests.retryInstantDispatch(widget.requestId);
      if (!mounted) return;
      PatientRouter.openRequestSmart(
        context,
        widget.session,
        widget.session.requests.requestById(widget.requestId)!,
      );
    } catch (e) {
      if (mounted) TamToast.show(context, explainError(e), tone: TamToastTone.error);
    } finally {
      if (mounted) setState(() => _busyAction = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;

    return ListenableBuilder(
      listenable: Listenable.merge([widget.session.requests, widget.session.bookingDraft]),
      builder: (context, _) {
        final req = widget.session.requests.requestById(widget.requestId);
        return TamScaffold(
          title: 'تفاصيل الطلب',
          subtitle: req == null ? 'جارٍ التحديث' : requestStatusAr(req.status),
          showBack: true,
          onRefresh: () => widget.session.requests.loadRequestDetail(widget.requestId),
          children: [
            if (widget.session.requests.detailErrors[widget.requestId] case final String message)
              TamErrorState(title: 'تعذر تحديث تفاصيل الطلب', message: message,
                onRetry: () => widget.session.requests.loadRequestDetail(widget.requestId, force: true)),
            if (widget.session.requests.reconciliationPending.contains(widget.requestId))
              const NoticeBox('تجري مطابقة حالة الطلب مع الخادم؛ البيانات المعروضة آخر حالة مؤكدة'),
            if (req == null && !widget.session.requests.detailErrors.containsKey(widget.requestId))
              const TamSkeleton.card(height: 180),
            if (req != null) ...[
              if (req.visitOutcome == 'NOT_PERFORMED')
                NoticeBox(req.visitOutcomeReason ?? 'أُغلقت الزيارة دون تقديم خدمات؛ لا توجد فاتورة للتحصيل'),
              TamCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            req.serviceTitle.isNotEmpty ? req.serviceTitle : 'زيارة تمريضية',
                            style: aeroText(size: 16.5, weight: FontWeight.w800, color: tc.textPrimary),
                          ),
                        ),
                        TamStatusBadge(status: req.status, compact: true),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (req.beneficiaryName.isNotEmpty) KeyValueRow('المستفيد', req.beneficiaryName),
                    if (req.addressText != null) KeyValueRow('العنوان', req.addressText!),
                    if (req.nurseName != null) KeyValueRow('الممرض', req.nurseName!),
                    if (req.scheduledAt != null)
                      KeyValueRow(
                        'الموعد',
                        '${MaterialLocalizations.of(context).formatMediumDate(req.scheduledAt!.toLocal())} • ${TimeOfDay.fromDateTime(req.scheduledAt!.toLocal()).format(context)}',
                      ),
                    KeyValueRow('القيمة التقديرية', req.formattedTotal),
                  ],
                ),
              ),
              if (req.items.isNotEmpty)
                TamCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('الخدمات المشمولة', style: aeroText(size: 14.5, weight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      for (final item in req.items)
                        KeyValueRow(
                          '${item.titleAr} × ${item.quantity}',
                          requestStatusAr(item.itemStatus),
                        ),
                    ],
                  ),
                ),
              if (req.clinicalApprovalStatus == 'PENDING' ||
                  req.clinicalApprovalStatus == 'REJECTED')
                TamCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        req.clinicalApprovalStatus == 'PENDING'
                            ? 'المراجعة السريرية قيد الانتظار'
                            : 'تم رفض المستندات السريرية',
                        style: aeroText(
                          size: 14.5,
                          weight: FontWeight.w800,
                          color: req.clinicalApprovalStatus == 'REJECTED' ? tc.danger : tc.warning,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (widget.session.bookingDraft.pendingEvidenceRequestId == req.id &&
                          widget.session.bookingDraft.stagedEvidence != null) ...[
                        if (widget.session.bookingDraft.pendingEvidenceError != null)
                          NoticeBox(widget.session.bookingDraft.pendingEvidenceError!),
                        AeroButton(
                          widget.session.bookingDraft.uploadingPendingEvidence
                              ? 'جارٍ إعادة رفع المستند...'
                              : 'إعادة رفع المستند المرفق مسبقاً',
                          isLoading: widget.session.bookingDraft.uploadingPendingEvidence,
                          onPressed: widget.session.bookingDraft.uploadingPendingEvidence
                              ? null
                              : () async {
                                  final ok = await widget.session.bookingDraft.retryPendingEvidenceUpload();
                                  if (ok && mounted) {
                                    await widget.session.requests.loadRequestDetail(req.id, force: true);
                                  }
                                },
                        ),
                        const SizedBox(height: 8),
                      ],
                      Text(
                        req.clinicalApprovalStatus == 'REJECTED'
                            ? 'يرجى رفع مستند أوضح لإعادة التقديم للمراجعة، أو يمكنك إغلاق الطلب.'
                            : 'يرجى رفع صورة واضحة للوصفة الطبية أو التقرير ليتم استكمال البحث.',
                        style: aeroText(size: 12.5, color: tc.textSecondary),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _busyAction ? null : () => _uploadEvidence('PRESCRIPTION'),
                            icon: const Icon(Icons.upload_file_rounded, size: 18),
                            label: Text(req.clinicalApprovalStatus == 'REJECTED'
                                ? 'إعادة رفع وصفة طبية'
                                : 'رفع وصفة طبية'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _busyAction ? null : () => _uploadEvidence('CLINICAL_REPORT'),
                            icon: const Icon(Icons.description_outlined, size: 18),
                            label: Text(req.clinicalApprovalStatus == 'REJECTED'
                                ? 'إعادة رفع تقرير طبي'
                                : 'رفع تقرير طبي'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              if (req.status == 'UNFULFILLED' || req.status == 'AWAITING_RECOVERY_CHOICE') ...[
                TamCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'لم يتوفر ممرض فوري الآن',
                        style: aeroText(size: 15, weight: FontWeight.w800, color: tc.warning),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'يمكنك نشر الطلب في السوق المفتوح لاستقبال عروض الممرضين أو إعادة البحث الفوري.',
                        style: aeroText(size: 12.5, color: tc.textSecondary, height: 1.45),
                      ),
                      const SizedBox(height: 12),
                      AeroButton(
                        'نشر الطلب في السوق المفتوح للعروض',
                        isLoading: _busyAction,
                        onPressed: _busyAction ? null : _switchToOpen,
                      ),
                      const SizedBox(height: 8),
                      SoftButton(
                        'إعادة البحث الفوري الآن',
                        onPressed: _busyAction ? null : _retryInstant,
                      ),
                    ],
                  ),
                ),
              ],
              if (req.hasAssignedNurse) ...[
                PrimaryButton(
                  'متابعة التتبع المباشر والوصول',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => TrackingScreen(session: widget.session, requestId: req.id),
                    ),
                  ),
                ),
                SoftButton(
                  'محادثة الممرض',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => VisitChatScreen(
                        session: widget.session,
                        requestId: req.id,
                        peerName: req.nurseName ?? 'الممرض المعتمد',
                      ),
                    ),
                  ),
                ),
              ],
              if (req.status == 'OPEN_FOR_PROPOSALS')
                PrimaryButton(
                  'استعراض العروض المقدمة (${req.activeProposalsCount})',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => OpenProposalsScreen(session: widget.session, requestId: req.id),
                    ),
                  ),
                ),
              if (req.status == 'COMPLETED' && req.visitOutcome != 'NOT_PERFORMED')
                PrimaryButton(
                  req.isUnpaid ? 'إتمام الدفع والتقييم' : 'عرض الفاتورة والتقييم',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => InvoicePaymentScreen(session: widget.session, requestId: req.id),
                    ),
                  ),
                ),
              if (req.isActive && req.status != 'IN_SERVICE' && req.status != 'ARRIVED')
                SoftButton(
                  'إلغاء الطلب',
                  onPressed: () => showPatientCancellationSheet(
                    context,
                    widget.session,
                    req.id,
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}
