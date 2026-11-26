import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../../core/patient_session_coordinator.dart';
import '../communication/visit_chat_screen.dart';
import '../finance/invoice_payment_screen.dart';
import '../requests/cancellation_sheet.dart';
import 'tracking_store.dart';

class TrackingScreen extends StatefulWidget {
  final PatientSessionCoordinator session;
  final String requestId;

  const TrackingScreen({
    super.key,
    required this.session,
    required this.requestId,
  });

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  late final TrackingStore _store;

  @override
  void initState() {
    super.initState();
    _store = TrackingStore(
      api: widget.session.api,
      eventBus: widget.session.eventBus,
      requestId: widget.requestId,
    )..start();
  }

  @override
  void dispose() {
    _store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;

    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final st = _store.status;
        final canCancel = st == 'ASSIGNED' || st == 'EN_ROUTE' || st == 'SCHEDULED' || st == 'OFFERING';
        final headerTuple = switch (st) {
          'ASSIGNED' => ('تم إسناد الزيارة', 'بانتظار انطلاق الممرض نحوك', 'معيّنة'),
          'EN_ROUTE' => ('الممرض في الطريق', 'يمكنك متابعة موقعه مباشرة على الخريطة', 'في الطريق'),
          'ARRIVED' => ('وصل الممرض', 'الممرض عند موقع الزيارة الآن', 'وصل'),
          'IN_SERVICE' => ('الزيارة قيد التنفيذ', 'تُنفذ الرعاية التمريضية حالياً', 'قيد التنفيذ'),
          'COMPLETED' => ('اكتملت الزيارة', 'راجع الفاتورة وأكّد الدفع والتقييم', 'مكتملة'),
          'ESCALATED' => ('توقفت الزيارة', 'أُغلقت متابعة هذه الزيارة', 'متوقفة'),
          _ => ('متابعة الزيارة', 'بيانات الزيارة المباشرة', requestStatusAr(st)),
        };

        return TamScaffold(
          title: headerTuple.$1,
          subtitle: headerTuple.$2,
          showBack: true,
          onRefresh: () => _store.refresh(),
          children: [
            if (_store.loading && st.isEmpty) ...[
              const TamSkeleton.card(height: 260),
              const SizedBox(height: 12),
              const TamSkeleton.card(height: 140),
            ] else if (_store.error != null && st.isEmpty) ...[
              TamErrorState(
                title: 'تعذر تحميل التتبع',
                message: _store.error!,
                onRetry: () => _store.refresh(),
              ),
            ] else ...[
              TamMap(
                height: 310,
                patient: _store.patientPos ?? kDamascus,
                nurse: _store.nursePos,
                route: _store.route,
              ),
              const SizedBox(height: 12),
              TamCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: tc.primaryTint,
                          child: Icon(Icons.person_outline_rounded, color: tc.primary),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _store.nurseName ?? 'الممرض المعتمد',
                                style: aeroText(size: 15, weight: FontWeight.w800, color: tc.textPrimary),
                              ),
                              Text(
                                _store.nurseBadge?['badge'] == true
                                    ? 'ممرض مميز ⭐ ${_store.nurseBadge!['rating']} (${_store.nurseBadge!['reviews']} تقييم)'
                                    : 'مرخص ومعتمد سريرياً',
                                style: aeroText(size: 12.5, color: tc.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        TamStatusBadge(status: st, labelOverride: headerTuple.$3, compact: true),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _MetricTile(
                            label: 'الوصول المتوقع',
                            value: st == 'EN_ROUTE' ? (_store.route?.etaLabel ?? 'قيد الحساب') : '—',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _MetricTile(
                            label: 'المسافة المتبقية',
                            value: st == 'EN_ROUTE' ? (_store.route?.distanceLabel ?? '—') : '—',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              TamCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('مراحل الزيارة', style: aeroText(size: 14.5, weight: FontWeight.w800)),
                    const SizedBox(height: 10),
                    TamTimeline(
                      items: [
                        TamTimelineItem(
                          title: 'تم إسناد الطلب إلى الممرض',
                          isDone: const {'EN_ROUTE', 'ARRIVED', 'IN_SERVICE', 'COMPLETED'}.contains(st),
                          isCurrent: st == 'ASSIGNED',
                        ),
                        TamTimelineItem(
                          title: 'الممرض في الطريق إليك',
                          subtitle: _store.route?.etaLabel != null && st == 'EN_ROUTE'
                              ? 'الوصول التقديري: ${_store.route!.etaLabel}'
                              : null,
                          isDone: const {'ARRIVED', 'IN_SERVICE', 'COMPLETED'}.contains(st),
                          isCurrent: st == 'EN_ROUTE',
                        ),
                        TamTimelineItem(
                          title: 'وصل الممرض إلى موقع الزيارة',
                          isDone: const {'IN_SERVICE', 'COMPLETED'}.contains(st),
                          isCurrent: st == 'ARRIVED',
                        ),
                        TamTimelineItem(
                          title: 'تنفيذ الرعاية التمريضية',
                          isDone: st == 'COMPLETED',
                          isCurrent: st == 'IN_SERVICE',
                        ),
                        TamTimelineItem(
                          title: 'اكتمال الزيارة وإصدار الفاتورة',
                          isDone: st == 'COMPLETED',
                          isCurrent: st == 'COMPLETED',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (st == 'COMPLETED')
                PrimaryButton(
                  'عرض الفاتورة وتأكيد الدفع',
                  onPressed: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute<void>(
                      builder: (_) => InvoicePaymentScreen(
                        session: widget.session,
                        requestId: widget.requestId,
                      ),
                    ),
                  ),
                )
              else if (st != 'ESCALATED' && st != 'CANCELLED') ...[
                Row(
                  children: [
                    Expanded(
                      child: PrimaryButton(
                        'محادثة الممرض',
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => VisitChatScreen(
                              session: widget.session,
                              requestId: widget.requestId,
                              peerName: _store.nurseName ?? 'الممرض المعتمد',
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SoftButton(
                        'اتصال صوتي آمن',
                        onPressed: () => widget.session.callManager.startOutgoing(
                          requestId: widget.requestId,
                          peerName: _store.nurseName ?? 'الممرض المعتمد',
                          peerRole: 'ممرض مرخص معتمد',
                        ),
                      ),
                    ),
                  ],
                ),
                if (canCancel)
                  SoftButton(
                    'إلغاء الطلب',
                    onPressed: () => showPatientCancellationSheet(
                      context,
                      widget.session,
                      widget.requestId,
                    ),
                  ),
              ],
            ],
          ],
        );
      },
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;

  const _MetricTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tc.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tc.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: aeroText(size: 11.5, color: tc.textSecondary)),
          const SizedBox(height: 3),
          Text(value, style: aeroText(size: 15, weight: FontWeight.w800, color: tc.textPrimary)),
        ],
      ),
    );
  }
}
