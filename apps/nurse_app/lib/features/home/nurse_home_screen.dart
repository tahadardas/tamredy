import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../../app/nurse_router.dart';
import '../../availability_manager.dart';
import '../../core/nurse_session_coordinator.dart';
import '../../guardian.dart';
import '../profile/nurse_notifications_screen.dart';
import '../safety/guardian_sheet.dart';

class NurseHomeScreen extends StatelessWidget {
  final NurseSessionCoordinator session;

  const NurseHomeScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;

    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([
          session.loadProfile(),
          session.visit.restoreActiveAssignment(),
          session.finance.refresh(),
          if (session.availability.intentAvailable && !session.visit.hasActiveWork)
            session.availability.syncNow(),
        ]);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: TamBreakpoints.maxContentWidth),
              child: ListenableBuilder(
                listenable: Listenable.merge([
                  session,
                  session.availability,
                  session.visit,
                  session.finance,
                  session.calendar,
                ]),
                builder: (context, _) {
                  final blocked = session.finance.isBlocked;
                  final activeVisit = session.visit.hasActiveWork;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _HomeTopBar(session: session),
                      const SizedBox(height: TamSpacing.md),
                      if (session.visit.cancellationNotice != null)
                        TamCard(
                          child: Row(
                            children: [
                              Icon(Icons.info_outline_rounded, color: tc.warning),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  session.visit.cancellationNotice!,
                                  style: aeroText(size: 13, weight: FontWeight.w700, color: tc.textPrimary),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close_rounded, size: 18),
                                onPressed: session.visit.clearCancellationNotice,
                              ),
                            ],
                          ),
                        ),
                      if (blocked)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: tc.dangerTint,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: tc.danger.withValues(alpha: 0.4)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.warning_amber_rounded, color: tc.danger),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'استقبال الطلبات متوقف بسبب التسويات المالية',
                                      style: aeroText(size: 14, weight: FontWeight.w800, color: tc.danger),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'تجاوزت المستحقات النقدية غير الموردة الحد المسموح. راجع المركز المالي للتسوية.',
                                style: aeroText(size: 12.5, color: tc.textPrimary),
                              ),
                              const SizedBox(height: 6),
                              TextButton(
                                onPressed: () => NurseRouter.switchTab(3),
                                child: const Text('فتح المركز المالي'),
                              ),
                            ],
                          ),
                        ),
                      if (activeVisit) _ActiveVisitBanner(session: session),
                      if (session.visit.unpaidInvoices.isNotEmpty)
                        _UnpaidInvoicesSection(session: session),
                      _AvailabilityStatusCard(
                        session: session,
                        lockedByAssignmentOrDebt: blocked || activeVisit,
                      ),
                      const SizedBox(height: 12),
                      _EarningsQuickGrid(session: session),
                      const SizedBox(height: 12),
                      _QuickShortcutsRow(session: session),
                      if (kDemoMode && !activeVisit) ...[
                        const SizedBox(height: 14),
                        SoftButton(
                          'محاكاة وصول طلب فوري (وضع التجربة)',
                          onPressed: session.offers.triggerDemoOffer,
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeTopBar extends StatelessWidget {
  final NurseSessionCoordinator session;
  const _HomeTopBar({required this.session});

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    return Row(
      children: [
        Image.asset(
          'assets/images/logo_mark.png',
          package: kFontPackage,
          width: 34,
          height: 34,
          excludeFromSemantics: true,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                session.nurseFullName.isEmpty ? 'لوحة الممرض' : session.nurseFullName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: aeroText(size: 15.5, weight: FontWeight.w800, color: tc.textPrimary),
              ),
              Text(
                '⭐ ${session.ratingAvg.toStringAsFixed(1)} ${session.nurseNumber.isNotEmpty ? "• ${session.nurseNumber}" : ""}',
                style: aeroText(size: 12, color: tc.textSecondary),
              ),
            ],
          ),
        ),
        if (guardianEnabled) ...[
          IconButton(
            tooltip: 'مركز الأمان Guardian',
            onPressed: () => openGuardianSheet(context, session),
            icon: Icon(Icons.shield_outlined, color: tc.primary),
          ),
        ],
        ValueListenableBuilder<int>(
          valueListenable: session.unreadNotifications,
          builder: (context, unread, _) => Stack(
            clipBehavior: Clip.none,
            children: [
              Material(
                color: tc.surface,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => NurseNotificationsScreen(session: session),
                    ),
                  ),
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: tc.border),
                    ),
                    child: Icon(Icons.notifications_none_rounded, color: tc.textPrimary),
                  ),
                ),
              ),
              if (unread > 0)
                PositionedDirectional(
                  top: -4,
                  end: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(color: tc.danger, borderRadius: BorderRadius.circular(99)),
                    child: Text(
                      unread > 99 ? '99+' : '$unread',
                      style: aeroText(size: 10, weight: FontWeight.w800, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActiveVisitBanner extends StatelessWidget {
  final NurseSessionCoordinator session;
  const _ActiveVisitBanner({required this.session});

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    final v = session.visit;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [tc.heroStart, tc.heroEnd],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: tc.elevatedShadow,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => NurseRouter.openVisitWorkspace(context, session),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.medical_services_rounded, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      v.serviceTitle ?? 'زيارة قيد التنفيذ',
                      style: aeroText(size: 15, weight: FontWeight.w800, color: Colors.white),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      v.addressText ?? 'اضغط لمتابعة خطوات الزيارة',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: aeroText(size: 12.5, color: Colors.white.withValues(alpha: 0.88)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _AvailabilityStatusCard extends StatelessWidget {
  final NurseSessionCoordinator session;
  final bool lockedByAssignmentOrDebt;

  const _AvailabilityStatusCard({
    required this.session,
    required this.lockedByAssignmentOrDebt,
  });

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    final store = session.availability;
    final st = store.state;
    final on = store.intentAvailable;

    return TamCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: st.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(st.icon, color: st.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(st.label, style: aeroText(size: 15, weight: FontWeight.w800, color: tc.textPrimary)),
                    Text(
                      lockedByAssignmentOrDebt
                          ? 'مغلق مؤقتاً حتى إتمام العمل الحالي'
                          : on
                              ? 'تتلقى طلبات جديدة في منطقتك الآن'
                              : 'فعّل التوفر لبدء استقبال العروض الفورية',
                      style: aeroText(size: 12, color: tc.textSecondary),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: on,
                onChanged: (lockedByAssignmentOrDebt || store.toggling)
                    ? null
                    : (val) => store.setAvailability(val),
              ),
            ],
          ),
          if (st != NurseReadinessState.ready && st != NurseReadinessState.offline) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: st.color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      st.description,
                      style: aeroText(size: 12, color: tc.textPrimary, height: 1.45),
                    ),
                  ),
                  if (st == NurseReadinessState.locationRequired ||
                      st == NurseReadinessState.locationStale ||
                      st == NurseReadinessState.connectionLost)
                    TextButton(
                      onPressed: store.syncNow,
                      child: const Text('تحديث الموقع'),
                    ),
                ],
              ),
            ),
          ],
          if (store.toggleError != null) ...[
            const SizedBox(height: 8),
            Text(store.toggleError!, style: aeroText(size: 12, color: tc.danger)),
          ],
        ],
      ),
    );
  }
}

class _EarningsQuickGrid extends StatelessWidget {
  final NurseSessionCoordinator session;
  const _EarningsQuickGrid({required this.session});

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    final f = session.finance;

    if (f.loading && f.todayEarnings == null) {
      return const TamSkeleton.card(height: 92);
    }
    if (f.error != null && f.todayEarnings == null) {
      return TamErrorState(
        title: 'تعذر تحميل ملخص الأرباح',
        message: f.error!,
        onRetry: f.refresh,
      );
    }

    return Row(
      children: [
        Expanded(
          child: TamCard(
            onTap: () => NurseRouter.switchTab(3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('أرباح اليوم', style: aeroText(size: 12, color: tc.textSecondary)),
                const SizedBox(height: 4),
                Text(
                  f.todayEarnings != null ? formatMoney(f.todayEarnings!) : '—',
                  style: aeroText(size: 16, weight: FontWeight.w800, color: tc.primary),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TamCard(
            onTap: () => NurseRouter.switchTab(3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('زيارات الشهر', style: aeroText(size: 12, color: tc.textSecondary)),
                const SizedBox(height: 4),
                Text(
                  f.monthVisits != null ? '${f.monthVisits}' : '—',
                  style: aeroText(size: 16, weight: FontWeight.w800, color: tc.textPrimary),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _QuickShortcutsRow extends StatelessWidget {
  final NurseSessionCoordinator session;
  const _QuickShortcutsRow({required this.session});

  @override
  Widget build(BuildContext context) {
    final marketCount = session.marketplace.requests.length;
    final upcomingCount = session.calendar.items
        .where((i) => i['block_type'] == 'SCHEDULED_VISIT')
        .length;

    return TamCard(
      child: Column(
        children: [
          ListRow(
            icon: Icons.storefront_outlined,
            title: 'السوق المفتوح للطلبات',
            subtitle: marketCount > 0
                ? 'يوجد $marketCount طلب قريب متاح لتقديم عرض'
                : 'تصفح الطلبات المفتوحة في منطقتك',
            trailing: Icon(Icons.chevron_left_rounded, color: context.tamColors.textSecondary),
            onTap: () => NurseRouter.switchTab(1),
          ),
          ListRow(
            icon: Icons.calendar_today_outlined,
            title: 'جدول المواعيد القادمة',
            subtitle: upcomingCount > 0
                ? '$upcomingCount زيارة مجدولة خلال الأسبوع'
                : 'لا توجد مواعيد قادمة حالياً',
            divider: false,
            trailing: Icon(Icons.chevron_left_rounded, color: context.tamColors.textSecondary),
            onTap: () => NurseRouter.switchTab(2),
          ),
        ],
      ),
    );
  }
}

class _UnpaidInvoicesSection extends StatelessWidget {
  final NurseSessionCoordinator session;
  const _UnpaidInvoicesSection({required this.session});

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    final invoices = session.visit.unpaidInvoices;
    if (invoices.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: TamCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.receipt_long_rounded, color: tc.warning, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'فواتير معلّقة للتحصيل (${invoices.length})',
                    style: aeroText(size: 14.5, weight: FontWeight.w800, color: tc.textPrimary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < invoices.length; i++) ...[
              ListRow(
                icon: Icons.payments_outlined,
                title: invoices[i].serviceTitle ?? 'فاتورة زيارة #${invoices[i].requestId.substring(0, invoices[i].requestId.length.clamp(0, 6))}',
                subtitle: 'المتبقي: ${formatMoney(invoices[i].remaining)} ${invoices[i].currencyCode}',
                divider: i < invoices.length - 1,
                trailing: Icon(Icons.chevron_left_rounded, color: tc.textSecondary),
                onTap: () async {
                  await session.visit.openUnpaidInvoice(invoices[i]);
                  if (context.mounted) {
                    NurseRouter.openVisitWorkspace(context, session);
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
