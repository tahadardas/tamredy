import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../../app/patient_router.dart';
import '../../core/patient_session_coordinator.dart';
import '../catalog/catalog_store.dart';
import '../profile/notifications_screen.dart';

class PatientHomeScreen extends StatefulWidget {
  final PatientSessionCoordinator session;

  const PatientHomeScreen({super.key, required this.session});

  @override
  State<PatientHomeScreen> createState() => _PatientHomeScreenState();
}

class _PatientHomeScreenState extends State<PatientHomeScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    final session = widget.session;

    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([
          session.catalog.load(forceRefresh: true),
          session.requests.refreshAll(),
          session.refreshUnreadNotifications(),
        ]);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: TamBreakpoints.maxContentWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TopHeader(session: session),
                  const SizedBox(height: TamSpacing.md),
                  _ActiveOrUnpaidBanner(session: session),
                  _HeroBookingCard(
                    onRequestNow: () => PatientRouter.openServiceCatalog(context, session),
                    onScheduleVisit: () => PatientRouter.openBookingWizard(
                      context,
                      session,
                      startScheduled: true,
                    ),
                  ),
                  const SizedBox(height: TamSpacing.md),
                  _QuickSearchBar(
                    controller: _searchCtrl,
                    onSubmit: (query) => PatientRouter.openServiceCatalog(
                      context,
                      session,
                      initialQuery: query,
                    ),
                  ),
                  const SizedBox(height: TamSpacing.lg),
                  _CategoriesSection(session: session),
                  const SizedBox(height: TamSpacing.lg),
                  _PopularServicesSection(session: session),
                  const SizedBox(height: TamSpacing.lg),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: tc.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: tc.border),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.verified_user_outlined, color: tc.primary, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'جميع الممرضين مرخصون ومعتمدون سريرياً، والتسعير تقديري وواضح قبل إرسال الطلب.',
                            style: aeroText(size: 12.5, color: tc.textSecondary, height: 1.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopHeader extends StatelessWidget {
  final PatientSessionCoordinator session;
  const _TopHeader({required this.session});

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    return ListenableBuilder(
      listenable: session.bookingDraft,
      builder: (context, _) {
        final addr = session.bookingDraft.addressLabel;
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
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => PatientRouter.openBookingWizard(context, session),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'تمريضي',
                      style: aeroText(size: 16, weight: FontWeight.w800, color: tc.primary),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.location_on_outlined, size: 14, color: tc.textSecondary),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            addr.isEmpty ? 'حدّد موقع الزيارة' : addr,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: aeroText(size: 12, color: tc.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
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
                          builder: (_) => PatientNotificationsScreen(session: session),
                        ),
                      ),
                      child: Container(
                        width: 44,
                        height: 44,
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
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: tc.danger,
                          borderRadius: BorderRadius.circular(99),
                        ),
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
      },
    );
  }
}

class _ActiveOrUnpaidBanner extends StatelessWidget {
  final PatientSessionCoordinator session;
  const _ActiveOrUnpaidBanner({required this.session});

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    return ListenableBuilder(
      listenable: session.requests,
      builder: (context, _) {
        final active = session.requests.primaryActiveRequest;
        final unpaid = session.requests.unpaidBills.firstOrNull;
        final target = active ?? unpaid;
        if (target == null) return const SizedBox.shrink();

        final isUnpaid = active == null && unpaid != null;
        final title = isUnpaid
            ? 'فاتورة بانتظار تأكيد الدفع'
            : target.serviceTitle.isNotEmpty
                ? target.serviceTitle
                : 'لديك طلب نشط الآن';
        final subtitle = isUnpaid
            ? 'المبلغ المستحق ${formatMoney(target.amountDue ?? target.priceAmount)}'
            : target.status == 'OPEN_FOR_PROPOSALS' && target.activeProposalsCount > 0
                ? 'وصلك ${target.activeProposalsCount} عروض جاهزية — اضغط للمقارنة'
                : 'الحالة: ${requestStatusAr(target.status)}';

        return Container(
          margin: const EdgeInsets.only(bottom: TamSpacing.md),
          decoration: BoxDecoration(
            color: isUnpaid ? tc.warningTint : tc.primaryTint,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: (isUnpaid ? tc.warning : tc.primary).withValues(alpha: 0.35),
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => PatientRouter.openRequestSmart(context, session, target),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: isUnpaid ? tc.warning : tc.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isUnpaid ? Icons.receipt_long_rounded : Icons.local_hospital_rounded,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: aeroText(size: 14.5, weight: FontWeight.w800, color: tc.textPrimary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: aeroText(size: 12.5, color: tc.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_left_rounded, color: tc.textPrimary),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HeroBookingCard extends StatelessWidget {
  final VoidCallback onRequestNow;
  final VoidCallback onScheduleVisit;

  const _HeroBookingCard({
    required this.onRequestNow,
    required this.onScheduleVisit,
  });

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [tc.heroStart, tc.heroEnd],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: tc.elevatedShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                'خدمة تمريض منزلي 24/7',
                style: aeroText(size: 11.5, weight: FontWeight.w700, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'رعاية تمريضية آمنة تصل إلى منزلك',
            style: aeroText(size: 21, weight: FontWeight.w800, color: Colors.white, height: 1.3),
          ),
          const SizedBox(height: 6),
          Text(
            'اختر الخدمة، حدّد الموقع وطريقة الحجز المناسبة، وتابع الممرض مباشرة حتى إكمال الزيارة.',
            style: aeroText(
              size: 13,
              color: Colors.white.withValues(alpha: 0.88),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: tc.heroStart,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: onRequestNow,
                icon: const Icon(Icons.medical_services_rounded, size: 20),
                label: Text(
                  'طلب ممرض الآن',
                  style: aeroText(size: 14.5, weight: FontWeight.w800, color: tc.heroStart),
                ),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: onScheduleVisit,
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
                label: Text(
                  'حجز موعد لاحق',
                  style: aeroText(size: 13.5, weight: FontWeight.w700, color: Colors.white),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onSubmit;

  const _QuickSearchBar({required this.controller, required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    return Material(
      color: tc.surface,
      borderRadius: BorderRadius.circular(16),
      child: TextField(
        controller: controller,
        textInputAction: TextInputAction.search,
        onSubmitted: onSubmit,
        decoration: InputDecoration(
          hintText: 'ابحث عن خدمة: حقنة، غيار جرح، سيروم، قياس ضغط...',
          hintStyle: aeroText(size: 13.5, color: tc.textSecondary),
          prefixIcon: Icon(Icons.search_rounded, color: tc.primary),
          suffixIcon: IconButton(
            tooltip: 'تصفح جميع الخدمات',
            icon: Icon(Icons.arrow_forward_rounded, color: tc.textSecondary),
            onPressed: () => onSubmit(controller.text),
          ),
          filled: true,
          fillColor: tc.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: tc.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: tc.border),
          ),
        ),
      ),
    );
  }
}

class _CategoriesSection extends StatelessWidget {
  final PatientSessionCoordinator session;
  const _CategoriesSection({required this.session});

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    return ListenableBuilder(
      listenable: session.catalog,
      builder: (context, _) {
        final cats = session.catalog.categories;
        if (session.catalog.loading && cats.isEmpty) {
          return const TamSkeleton.card(height: 76);
        }
        if (cats.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'التصنيفات الطبية',
                    style: aeroText(size: 16, weight: FontWeight.w800, color: tc.textPrimary),
                  ),
                ),
                TextButton(
                  onPressed: () => PatientRouter.openServiceCatalog(context, session),
                  child: const Text('كل الخدمات'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: cats.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final cat = cats[index];
                  return ActionChip(
                    avatar: Icon(Icons.medical_information_outlined, size: 17, color: tc.primary),
                    label: Text(
                      cat.titleAr,
                      style: aeroText(size: 13, weight: FontWeight.w700, color: tc.textPrimary),
                    ),
                    backgroundColor: tc.surface,
                    side: BorderSide(color: tc.border),
                    onPressed: () => PatientRouter.openServiceCatalog(
                      context,
                      session,
                      initialCategoryId: cat.id,
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PopularServicesSection extends StatelessWidget {
  final PatientSessionCoordinator session;
  const _PopularServicesSection({required this.session});

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    return ListenableBuilder(
      listenable: session.catalog,
      builder: (context, _) {
        if (session.catalog.loading && session.catalog.services.isEmpty) {
          return const Column(
            children: [
              TamSkeleton.card(height: 92),
              SizedBox(height: 10),
              TamSkeleton.card(height: 92),
            ],
          );
        }
        if (session.catalog.error != null && session.catalog.services.isEmpty) {
          return TamErrorState(
            title: 'تعذر تحميل الخدمات',
            message: session.catalog.error!,
            onRetry: () => session.catalog.load(forceRefresh: true),
          );
        }

        final list = session.catalog.popularServices;
        if (list.isEmpty) {
          return const TamEmptyState(
            icon: Icons.medical_services_outlined,
            title: 'لا توجد خدمات متاحة حالياً',
            message: 'حدّث الصفحة للتحقق من الخدمات المفعلة.',
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'الخدمات الأكثر طلباً',
              style: aeroText(size: 16, weight: FontWeight.w800, color: tc.textPrimary),
            ),
            const SizedBox(height: 10),
            for (final svc in list) _ServiceTile(svc: svc, session: session),
          ],
        );
      },
    );
  }
}

class _ServiceTile extends StatelessWidget {
  final PatientService svc;
  final PatientSessionCoordinator session;

  const _ServiceTile({required this.svc, required this.session});

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: tc.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tc.border),
        boxShadow: tc.cardShadow,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => PatientRouter.openBookingWizard(
          context,
          session,
          preselectedService: svc,
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: tc.primaryTint,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(Icons.healing_rounded, color: tc.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      svc.titleAr,
                      style: aeroText(size: 14.5, weight: FontWeight.w800, color: tc.textPrimary),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      svc.descriptionAr,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: aeroText(size: 12, color: tc.textSecondary, height: 1.4),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(
                          formatMoney(svc.priceAmount),
                          style: aeroText(size: 13, weight: FontWeight.w800, color: tc.primary),
                        ),
                        Text(
                          '• ${svc.expectedMinutes} د',
                          style: aeroText(size: 12, color: tc.textSecondary),
                        ),
                        if (svc.requiresPrescription)
                          Text(
                            '• وصفة طبية',
                            style: aeroText(size: 12, weight: FontWeight.w700, color: tc.warning),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, size: 16, color: tc.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
