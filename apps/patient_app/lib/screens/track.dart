import 'cancellation_sheet.dart';
import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../controller.dart';
import 'payment.dart';
import 'chat.dart';
import 'proposals_view.dart';

/// The amount due, shown to the patient immediately when the nurse closes the visit.
class BillCard extends StatelessWidget {
  final BillInfo bill;
  const BillCard({super.key, required this.bill});
  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    return TamCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'المبلغ المطلوب',
            style: tamText(size: 12, color: tc.textSecondary),
          ),
          Text(
            formatMoney(bill.due),
            style: tamText(
              size: 30,
              weight: FontWeight.w800,
              color: tc.textPrimary,
            ),
          ),
          Divider(color: tc.border),
          KeyValueRow('مدة الزيارة', '${bill.minutes} دقيقة'),
          KeyValueRow('قيمة الخدمة', formatMoney(bill.gross - bill.surcharge)),
          if (bill.surcharge > 0)
            KeyValueRow('رسم ليلي/عطلة', formatMoney(bill.surcharge)),
          if (bill.distanceFee > 0)
            KeyValueRow('رسم المسافة', formatMoney(bill.distanceFee)),
          if (bill.discount > 0)
            KeyValueRow(
              bill.promoCode == null ? 'الخصم' : 'خصم ${bill.promoCode}',
              '−${formatMoney(bill.discount)}',
            ),
          if (bill.tax > 0) KeyValueRow(bill.taxLabel, formatMoney(bill.tax)),
          if (bill.tip > 0) KeyValueRow('إكرامية للممرض', formatMoney(bill.tip)),
          if (bill.collected > 0)
            KeyValueRow('المدفوع', formatMoney(bill.collected)),
          if (bill.status == 'PARTIAL')
            KeyValueRow('المتبقي', formatMoney(bill.remaining)),
        ],
      ),
    );
  }
}

/// Animated radar ripple for searching phase (P04).
class SearchingRadarAnimation extends StatefulWidget {
  final double size;
  const SearchingRadarAnimation({super.key, this.size = 140});

  @override
  State<SearchingRadarAnimation> createState() => _SearchingRadarAnimationState();
}

class _SearchingRadarAnimationState extends State<SearchingRadarAnimation> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              for (int i = 0; i < 3; i++) _buildRipple((_controller.value + (i * 0.33)) % 1.0),
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: TamreedyColors.teal,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: TamreedyColors.teal.withValues(alpha: 0.35),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(Icons.health_and_safety_outlined, color: Colors.white, size: 30),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRipple(double value) {
    final clamped = (1.0 - value).clamp(0.0, 1.0);
    return Container(
      width: widget.size * value,
      height: widget.size * value,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: TamreedyColors.teal.withValues(alpha: clamped * 0.6),
          width: 2.0,
        ),
      ),
    );
  }
}

/// P04 (searching) and P05 (nurse tracking) driven by the request stage.
class TrackScreen extends StatelessWidget {
  final PatientController c;
  final TamBottomNav nav;
  const TrackScreen({super.key, required this.c, required this.nav});

  Future<void> _runRecoveryAction(
    BuildContext context,
    Future<bool> Function() action,
  ) async {
    final succeeded = await action();
    if (!succeeded && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            c.error ?? 'تعذر تنفيذ الإجراء. حاول مرة أخرى',
            textDirection: TextDirection.rtl,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = c.service;

    // 1. Open Marketplace State
    if (c.stage == VisitStage.openMarketplace) {
      final remainingMins = c.openExpiresAt?.difference(DateTime.now()).inMinutes;
      final expiryLabel = remainingMins != null && remainingMins > 0
          ? 'متبقي نحو $remainingMins دقيقة على انتهاء النشر'
          : 'ينتهي النشر قريباً';

      return TamScaffold(
        title: 'السوق المفتوح',
        subtitle: 'طلبك منشور لاستقبال عروض الجاهزية',
        nav: nav,
        children: [
          TamMap(height: 180, patient: c.position ?? kDamascus),
          const SizedBox(height: 12),
          TamCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AeroColors.aeroTintLight,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AeroColors.accentTeal.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.storefront_rounded, color: AeroColors.accentTeal, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'منشور في سوق الطلبات',
                        style: aeroText(size: 12, weight: FontWeight.w700, color: AeroColors.accentTeal),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  c.activeProposalsCount > 0
                      ? 'وصلك ${c.activeProposalsCount} عروض جاهزية!'
                      : 'بانتظار عروض الممرضين المؤهلين',
                  style: tamText(size: 18, weight: FontWeight.w800, color: TamreedyColors.navy),
                ),
                const SizedBox(height: 8),
                Text(
                  c.activeProposalsCount > 0
                      ? 'يمكنك الاطلاع على وقت الوصول المقترح لكل ممرض وتأكيد المناسب لك فوراً.'
                      : 'يتم إشعار الكوادر التمريضية المرخصة في منطقتك. ستصلك عروضهم هنا فور تقديمها.',
                  textAlign: TextAlign.center,
                  style: tamText(size: 13, color: TamreedyColors.subtext, height: 1.5),
                ),
                const SizedBox(height: 20),
                KeyValueRow('نوع الخدمة', s?.title ?? '—'),
                KeyValueRow('موقع الزيارة', c.address),
                KeyValueRow('صلاحية النشر', expiryLabel),
                const SizedBox(height: 20),
                if (c.activeProposalsCount > 0) ...[
                  AeroButton(
                    'استعراض العروض المقدمة (${c.activeProposalsCount})',
                    leadingIcon: const Icon(Icons.people_alt_rounded, color: Colors.white, size: 20),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => ProposalsViewScreen(c: c)),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                ],
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.timer_outlined, size: 18),
                        label: const Text('تمديد الوقت (+30د)'),
                        onPressed: c.busy ? null : () => c.extendWaitWindow(additionalMinutes: 30),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('تحديث العروض'),
                        onPressed: c.busy ? null : () => c.loadProposals(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SoftButton(
                  'إلغاء الطلب (مجاناً)',
                  onPressed: c.busy ? null : () => showCancellationSheet(context, c),
                ),
              ],
            ),
          ),
          _RequestJourneyInfographic(c: c),
        ],
      );
    }

    // 2. Unfulfilled / Search Timeout State
    if (c.stage == VisitStage.unfulfilled) {
      return TamScaffold(
        title: 'لم نجد ممرضاً متاحاً فوراً',
        subtitle: 'تعذر توفير كادر فوري في هذه اللحظة',
        nav: nav,
        children: [
          TamCard(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AeroColors.warning.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: AeroColors.warning.withValues(alpha: 0.4), width: 2),
                  ),
                  child: const Icon(
                    Icons.hourglass_empty_rounded,
                    size: 36,
                    color: AeroColors.warning,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'الممرضون الأقرب إليك منشغلون حالياً',
                  style: tamText(
                    size: 18,
                    weight: FontWeight.w800,
                    color: TamreedyColors.navy,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'جميع الكوادر التمريضية القريبة منك مشغولة حالياً بزيارات أخرى. اختر الخيار الأنسب لك:',
                  textAlign: TextAlign.center,
                  style: tamText(size: 13, color: TamreedyColors.subtext, height: 1.5),
                ),
                const SizedBox(height: 20),
                KeyValueRow('نوع الخدمة', s?.title ?? '—'),
                KeyValueRow('موقع الزيارة', c.address),
                const SizedBox(height: 20),

                // Recovery Action 1: Keep Open
                AeroButton(
                  'إبقاء الطلب مفتوحاً للعروض',
                  leadingIcon: const Icon(Icons.storefront_rounded, color: Colors.white, size: 20),
                  isLoading: c.recoveryAction == RecoveryAction.openMarketplace,
                  onPressed: c.busy
                      ? null
                      : () => _runRecoveryAction(
                          context,
                          c.switchToOpenMarketplace,
                        ),
                ),
                const SizedBox(height: 10),

                // Recovery Action 2: Retry Instant
                AeroButton(
                  'إعادة البحث الفوري الآن',
                  variant: AeroButtonVariant.secondary,
                  leadingIcon: const Icon(Icons.refresh_rounded, color: AeroColors.primaryNavy, size: 20),
                  isLoading: c.recoveryAction == RecoveryAction.retryInstant,
                  onPressed: c.busy
                      ? null
                      : () => _runRecoveryAction(
                          context,
                          c.retryInstantDispatch,
                        ),
                ),
                const SizedBox(height: 10),

                // Recovery Action 3: Cancel / Back
                SoftButton(
                  'إلغاء الطلب والعودة للرئيسية',
                  onPressed: () {
                    c.resetToHome();
                  },
                ),
              ],
            ),
          ),
        ],
      );
    }
    if (c.stage == VisitStage.interrupted) {
      return TamScaffold(
        title: 'توقفت الزيارة',
        subtitle: 'أُغلقت متابعة هذا الطلب',
        nav: nav,
        children: [
          const NoticeBox('يمكنك مراجعة حالة الطلب من سجل الزيارات.'),
          SoftButton('عرض سجل الطلبات', onPressed: () {
            c.resetToHome();
            c.setTab(1);
          }),
        ],
      );
    }
    if (c.stage == VisitStage.scheduled) {
      return TamScaffold(
        title: 'زيارة مجدولة',
        subtitle: 'يبدأ البحث عن ممرض قبل الموعد بـ15 دقيقة',
        nav: nav,
        children: [
          TamMap(height: 200, patient: c.position),
          if (c.scheduledAt case final DateTime appointment)
            KeyValueRow('الموعد', '${MaterialLocalizations.of(context).formatMediumDate(appointment)} • ${TimeOfDay.fromDateTime(appointment).format(context)}'),
          KeyValueRow('عنوان الزيارة', c.visitAddress),
          const NoticeBox('بانتظار بدء البحث عن ممرض. سنخبرك عند تأكيد الإسناد.'),
          _RequestJourneyInfographic(c: c),
          SoftButton('إلغاء الطلب', onPressed: c.busy ? null : () => showCancellationSheet(context, c)),
        ],
      );
    }
    if (c.stage == VisitStage.searching) {
      return TamScaffold(
        title: 'جارٍ البحث عن ممرض',
        subtitle: 'نبحث عن كادر مؤهل ومرخص قريب منك',
        nav: nav,
        children: [
          TamMap(height: 200, patient: c.position ?? kDamascus),
          const SizedBox(height: 12),
          TamCard(
            padding: const EdgeInsets.fromLTRB(18, 28, 18, 24),
            child: Column(
              children: [
                const SearchingRadarAnimation(size: 130),
                const SizedBox(height: 20),
                Text(
                  'يتم فحص الكوادر التمريضية القريبة',
                  style: tamText(
                    size: 20,
                    weight: FontWeight.w800,
                    color: TamreedyColors.navy,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'نقوم بإرسال طلبك تباعاً لأقرب الممرضين المعتمدين والمناسبين للخدمة. سيتم إشعارك فور قبول الممرض للزيارة.',
                  textAlign: TextAlign.center,
                  style: tamText(size: 12.5, color: TamreedyColors.subtext, height: 1.6),
                ),
                const SizedBox(height: 22),
                const StepBar(filled: 2),
                const SizedBox(height: 14),
                KeyValueRow('نوع الخدمة', s?.title ?? '—'),
                KeyValueRow('موقع الزيارة', c.address),
              ],
            ),
          ),
          _RequestJourneyInfographic(c: c),
          SoftButton(
            'إلغاء الطلب',
            onPressed: c.busy ? null : () => showCancellationSheet(context, c),
          ),
        ],
      );
    }
    final titles = {
      VisitStage.assigned: ('تم إسناد الزيارة', 'بانتظار تأكيد انطلاق الممرض', 'معيّنة'),
      VisitStage.enRoute: (
        'الممرض في الطريق',
        'يمكنك متابعة وصوله على الخريطة',
        'في الطريق',
      ),
      VisitStage.arrived: ('وصل الممرض', 'الممرض عند موقع الزيارة', 'وصل'),
      VisitStage.inService: (
        'الزيارة قيد التنفيذ',
        'تتم الخدمة الآن',
        'قيد التنفيذ',
      ),
      VisitStage.completed: (
        'تم إكمال الزيارة',
        'أكّد الدفع لإنهاء الطلب',
        'مكتملة',
      ),
    };
    final t = titles[c.stage]!;
    return TamScaffold(
      title: t.$1,
      subtitle: t.$2,
      nav: nav,
      children: [
        TamMap(
          height: 340,
          patient: c.position ?? kDamascus,
          nurse: c.nursePos,
          route: c.route,
        ),
        const SizedBox(height: 12),
        TamCard(
          child: Column(
            children: [
              ListRow(
                icon: Icons.person_outline,
                title: 'الممرض المعتمد',
                subtitle: c.nurseBadge?['badge'] == true
                    ? 'ممرض مميز ⭐ ${c.nurseBadge!['rating']} (${c.nurseBadge!['reviews']} تقييم)'
                    : 'تم التحقق من الترخيص والتخصص',
                trailing: StatusChip(t.$3),
              ),
              Row(
                children: [
                  Expanded(
                    child: _tile(
                      'وصول',
                      c.stage == VisitStage.enRoute
                          ? (c.route?.etaLabel ?? '—')
                          : '—',
                      'تقديري',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _tile(
                      'مسافة',
                      c.route?.distanceLabel ?? '—',
                      'تقريبية',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (c.stage == VisitStage.completed && c.bill != null)
          BillCard(bill: c.bill!),
        if (c.stage != VisitStage.completed)
          TamCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'مراحل الزيارة',
                  style: aeroText(
                    size: 14.5,
                    weight: FontWeight.w700,
                    color: context.tamColors.textPrimary,
                  ),
                ),
                const SizedBox(height: TamSpacing.md),
                TamTimeline(
                  items: [
                    TamTimelineItem(
                      title: 'تم الإسناد إلى الممرض',
                      isDone: c.stage.index > VisitStage.assigned.index,
                      isCurrent: c.stage == VisitStage.assigned,
                    ),
                    TamTimelineItem(
                      title: 'الممرض في الطريق',
                      subtitle: c.route?.etaLabel != null
                          ? 'الوصول التقديري: ${c.route!.etaLabel}'
                          : null,
                      isDone: c.stage.index > VisitStage.enRoute.index,
                      isCurrent: c.stage == VisitStage.enRoute,
                    ),
                    TamTimelineItem(
                      title: 'وصل الممرض إلى الموقع',
                      isDone: c.stage.index > VisitStage.arrived.index,
                      isCurrent: c.stage == VisitStage.arrived,
                    ),
                    TamTimelineItem(
                      title: 'الخدمة قيد التنفيذ',
                      isDone: c.stage == VisitStage.completed,
                      isCurrent: c.stage == VisitStage.inService,
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (c.stage == VisitStage.completed)
          PrimaryButton(
            'متابعة إلى الدفع',
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => PaymentScreen(c: c))),
          )
        else ...[
          Row(
            children: [
              Expanded(
                child: PrimaryButton(
                  'محادثة',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PatientChatScreen(
                        c: c,
                        requestId: c.requestId ?? '',
                        nurseName: c.nurseBadge?['name']?.toString() ?? 'الممرض المعتمد',
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SoftButton(
                  'اتصال عبر التطبيق',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => TamInAppCallScreen(
                        api: c.api,
                        requestId: c.requestId ?? '',
                        peerName: c.nurseBadge?['name']?.toString() ?? 'الممرض المعتمد',
                        peerRole: 'ممرض مرخص معتمد',
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (c.stage == VisitStage.assigned || c.stage == VisitStage.enRoute)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SoftButton(
                'إلغاء الطلب',
                onPressed: c.busy ? null : () => showCancellationSheet(context, c),
              ),
            ),
        ],
      ],
    );
  }

  Widget _tile(String a, String b, String sub) => Builder(
    builder: (context) {
      final tc = context.tamColors;
      return Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: tc.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tc.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(a, style: tamText(size: 12, color: tc.textSecondary)),
            Text(
              b,
              style: tamText(
                size: 17,
                weight: FontWeight.w800,
                color: tc.textPrimary,
              ),
            ),
            Text(sub, style: tamText(size: 11, color: tc.textSecondary)),
          ],
        ),
      );
    },
  );
}


/// Visual step-by-step infographic of the patient's request journey across all stages.
class _RequestJourneyInfographic extends StatelessWidget {
  final PatientController c;
  const _RequestJourneyInfographic({required this.c});

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    final st = c.stage;
    final statusCode = switch (st) {
      VisitStage.scheduled => 'SCHEDULED',
      VisitStage.searching => 'OFFERING',
      VisitStage.openMarketplace => 'OPEN_FOR_PROPOSALS',
      VisitStage.unfulfilled => 'UNFULFILLED',
      VisitStage.assigned => 'ASSIGNED',
      VisitStage.enRoute => 'EN_ROUTE',
      VisitStage.arrived => 'ARRIVED',
      VisitStage.inService => 'IN_SERVICE',
      VisitStage.completed => 'COMPLETED',
      VisitStage.interrupted => 'ESCALATED',
      VisitStage.none => 'DRAFT',
    };

    final pastSearching = [
      VisitStage.assigned,
      VisitStage.enRoute,
      VisitStage.arrived,
      VisitStage.inService,
      VisitStage.completed,
    ].contains(st);

    return TamCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.route_rounded, color: tc.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'مسار الطلب والخطوات',
                  style: aeroText(
                    size: 15,
                    weight: FontWeight.w800,
                    color: tc.textPrimary,
                  ),
                ),
              ),
              TamStatusBadge(status: statusCode, compact: true),
            ],
          ),
          const SizedBox(height: TamSpacing.md),
          TamTimeline(
            items: [
              const TamTimelineItem(
                title: 'تم استلام طلبك بنجاح',
                subtitle: 'تأكيد الخدمة وموقع الزيارة',
                isDone: true,
              ),
              TamTimelineItem(
                title: st == VisitStage.openMarketplace
                    ? 'منشور في سوق الطلبات المفتوح'
                    : st == VisitStage.scheduled
                        ? 'مجدول للموعد المحدد'
                        : 'البحث عن أقرب ممرض مؤهل',
                subtitle: st == VisitStage.openMarketplace
                    ? (c.activeProposalsCount > 0
                        ? 'وصلك ${c.activeProposalsCount} عروض جاهزية للمقارنة'
                        : 'بانتظار تقديم الممرضين لعروضهم')
                    : st == VisitStage.unfulfilled
                        ? 'لم يقبل ممرض فورياً — يمكنك النشر في السوق أو إعادة البحث'
                        : null,
                isDone: pastSearching,
                isCurrent: st == VisitStage.searching ||
                    st == VisitStage.openMarketplace ||
                    st == VisitStage.scheduled,
                isError: st == VisitStage.unfulfilled,
              ),
              TamTimelineItem(
                title: 'تم إسناد الطلب إلى ممرض',
                isDone: st.index > VisitStage.assigned.index && pastSearching,
                isCurrent: st == VisitStage.assigned,
              ),
              TamTimelineItem(
                title: 'الممرض في الطريق إليك',
                subtitle: c.route?.etaLabel != null && st == VisitStage.enRoute
                    ? 'الوصول التقديري: ${c.route!.etaLabel}'
                    : null,
                isDone: st.index > VisitStage.enRoute.index && pastSearching,
                isCurrent: st == VisitStage.enRoute,
              ),
              TamTimelineItem(
                title: 'وصول الممرض وبدء الرعاية',
                isDone: st == VisitStage.completed,
                isCurrent:
                    st == VisitStage.arrived || st == VisitStage.inService,
              ),
              TamTimelineItem(
                title: 'اكتمال الزيارة والفاتورة',
                isDone: st == VisitStage.completed,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
