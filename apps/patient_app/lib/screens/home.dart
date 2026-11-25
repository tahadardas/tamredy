import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../controller.dart';
import '../main.dart';
export 'location.dart';
import 'location.dart';
import 'care_plans.dart';
import 'favorite_nurses.dart';
import 'health_record.dart';

const _serviceIcons = [
  Icons.vaccines_outlined,
  Icons.healing_outlined,
  Icons.monitor_heart_outlined,
  Icons.elderly_outlined,
];
const _serviceTones = [Tone.teal, Tone.blue, Tone.teal, Tone.orange];

class HomeScreen extends StatefulWidget {
  final PatientController c;
  final TamBottomNav nav;
  const HomeScreen({super.key, required this.c, required this.nav});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _search = TextEditingController();
  String _query = '';
  PatientController get c => widget.c;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    final last = c.history.isEmpty ? null : c.history.first;
    final filteredServices = _query.trim().isEmpty
        ? c.services
        : c.services.where((s) {
            final q = _query.trim();
            return s.title.contains(q) || s.note.contains(q);
          }).toList();

    return Scaffold(
      backgroundColor: tc.background,
      bottomNavigationBar: MediaQuery.viewInsetsOf(context).bottom == 0
          ? widget.nav
          : null,
      drawer: Drawer(
        backgroundColor: tc.surface,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: TamSpacing.sm),
            children: [
              Padding(
                padding: const EdgeInsets.all(TamSpacing.lg),
                child: Row(
                  children: [
                    Image.asset(
                      'assets/images/logo_mark.png',
                      package: kFontPackage,
                      width: 36,
                      height: 36,
                      excludeFromSemantics: true,
                    ),
                    const SizedBox(width: TamSpacing.md),
                    Text(
                      'تمريضي',
                      style: aeroText(
                        size: 20,
                        weight: FontWeight.w800,
                        color: tc.primary,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(color: tc.border),
              for (final item in [
                (Icons.calendar_today_outlined, 'طلباتي', 1),
                (Icons.account_balance_wallet_outlined, 'محفظتي', 2),
                (Icons.person_outline, 'حسابي', 3),
              ])
                ListTile(
                  leading: Icon(item.$1, color: tc.textSecondary),
                  title: Text(
                    item.$2,
                    style: aeroText(
                      size: 14,
                      weight: FontWeight.w600,
                      color: tc.textPrimary,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    c.setTab(item.$3);
                  },
                ),
              Divider(color: tc.border),
              ListTile(
                leading: Icon(Icons.calendar_month, color: tc.primary),
                title: Text(
                  'خطط الرعاية المستمرة',
                  style: aeroText(size: 14, color: tc.textPrimary),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => CarePlansScreen(c: c)),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.favorite, color: tc.danger),
                title: Text(
                  'الممرضون المفضلون',
                  style: aeroText(size: 14, color: tc.textPrimary),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => FavoriteNursesScreen(c: c),
                    ),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.folder_shared_outlined, color: tc.secondary),
                title: Text(
                  'السجل الصحي والتقارير',
                  style: aeroText(size: 14, color: tc.textPrimary),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => HealthRecordScreen(c: c),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Clean Medical Top Bar
            Container(
              decoration: BoxDecoration(
                color: tc.surface,
                border: Border(bottom: BorderSide(color: tc.border)),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: TamSpacing.lg,
                vertical: TamSpacing.md,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: TamBreakpoints.maxContentWidth,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Builder(
                            builder: (ctx) => TamIconButton(
                              icon: Icons.menu_rounded,
                              tooltip: 'فتح القائمة',
                              onPressed: () => Scaffold.of(ctx).openDrawer(),
                            ),
                          ),
                          const SizedBox(width: TamSpacing.md),
                          Image.asset(
                            'assets/images/logo_mark.png',
                            package: kFontPackage,
                            width: 34,
                            height: 34,
                            excludeFromSemantics: true,
                          ),
                          const SizedBox(width: TamSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'تمريضي',
                                  style: aeroText(
                                    size: 18,
                                    weight: FontWeight.w800,
                                    color: tc.textPrimary,
                                  ),
                                ),
                                Text(
                                  'الرعاية التمريضية المنزلية',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: aeroText(
                                    size: 11.5,
                                    color: tc.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TamIconButton(
                            icon: Icons.folder_shared_outlined,
                            tooltip: 'السجل الصحي',
                            color: tc.primary,
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => HealthRecordScreen(c: c),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: TamSpacing.md),
                      // Current Visit Address Selector
                      InkWell(
                        onTap: c.stage != VisitStage.none || c.busy
                            ? null
                            : () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) =>
                                        LocationScreen(c: c, addressOnly: true),
                                  ),
                                ),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: TamSpacing.md,
                            vertical: TamSpacing.sm,
                          ),
                          decoration: BoxDecoration(
                            color: tc.surfaceElevated,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: tc.border),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.location_on_rounded,
                                size: 18,
                                color: tc.primary,
                              ),
                              const SizedBox(width: TamSpacing.sm),
                              Expanded(
                                child: Text(
                                  c.position == null
                                      ? 'تحديد عنوان الزيارة'
                                      : c.visitAddress,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: aeroText(
                                    size: 13,
                                    weight: FontWeight.w600,
                                    color: tc.textPrimary,
                                  ),
                                ),
                              ),
                              Text(
                                'تغيير',
                                style: aeroText(
                                  size: 12,
                                  weight: FontWeight.w700,
                                  color: tc.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Scrollable Hub Content
            Expanded(
              child: RefreshIndicator(
                color: tc.primary,
                onRefresh: c.loadServices,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: TamBreakpoints.maxContentWidth,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (c.stage != VisitStage.none)
                              ActiveOrderBanner(c: c),
                            // Quick Nursing Request Hero
                            HeroCard(
                              caption: 'رعاية طبية موثوقة',
                              title: 'طلب تمريض منزلي',
                              body:
                                  'اختر الخدمة المناسبة أو طريقة الحجز وسيصلك ممرض معتمد في الوقت المحدد.',
                              trailing: c.services.isNotEmpty
                                  ? AeroButton.teal(
                                      'ابدأ طلب تمريض الآن',
                                      height: 46,
                                      fontSize: 14,
                                      trailingIcon: const Icon(
                                        Icons.arrow_forward_rounded,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                      onPressed: () {
                                        c.pick(c.services.first);
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                ServiceScreen(c: c),
                                          ),
                                        );
                                      },
                                    )
                                  : null,
                            ),
                            // Search Bar
                            TamSearchField(
                              controller: _search,
                              hint: 'ابحث عن خدمة تمريضية...',
                              onChanged: (v) => setState(() => _query = v),
                            ),
                            const SectionTitle('طرق الحجز'),
                            _BookingModeStrip(
                              selectedMode: c.bookingMode,
                              onSelect: (mode) =>
                                  setState(() => c.bookingMode = mode),
                            ),
                            const SectionTitle('ما الخدمة التي تحتاجها؟'),
                            if (c.serviceState == ServiceLoadState.loading)
                              const ServiceSkeletonGrid()
                            else if (c.serviceState ==
                                    ServiceLoadState.networkError ||
                                c.serviceState == ServiceLoadState.serverError)
                              ServiceErrorCard(
                                message: c.serviceError ??
                                    'تعذر الاتصال بالخادم لجلب الخدمات المتاحة.',
                                onRetry: c.loadServices,
                              )
                            else if (c.serviceState == ServiceLoadState.empty)
                              const TamEmptyState(
                                icon: Icons.medical_services_outlined,
                                title: 'لا توجد خدمات منشورة حاليًا',
                                message:
                                    'لا توجد خدمات منشورة في منطقتك حاليًا. تواصل مع الدعم للمساعدة.',
                              )
                            else if (filteredServices.isEmpty)
                              TamEmptyState(
                                icon: Icons.search_off_rounded,
                                title: 'لا توجد نتائج مطابقة',
                                message: 'جرّب البحث بكلمة أخرى.',
                                actionLabel: 'عرض كل الخدمات',
                                onAction: () {
                                  _search.clear();
                                  setState(() => _query = '');
                                },
                              )
                            else
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  const gap = 12.0;
                                  final width = constraints.maxWidth >= 420
                                      ? (constraints.maxWidth - gap) / 2
                                      : constraints.maxWidth;
                                  return Wrap(
                                    spacing: gap,
                                    runSpacing: gap,
                                    children: [
                                      for (final service in filteredServices)
                                        SizedBox(
                                          width: width,
                                          child: _ServiceOption(
                                            service: service,
                                            onTap: () {
                                              c.pick(service);
                                              Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      ServiceScreen(c: c),
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                    ],
                                  );
                                },
                              ),
                            const SizedBox(height: TamSpacing.md),
                            ClaimCodeCard(c: c),
                            const SectionTitle('حجوزاتي الأخيرة'),
                            if (last == null)
                              const TamEmptyState(
                                icon: Icons.history_rounded,
                                title: 'لا توجد حجوزات سابقة بعد',
                                message: 'اختر خدمة تمريضية لتبدأ طلبك الأول.',
                              )
                            else
                              TamAppointmentCard(
                                title: last.title,
                                dateTimeLabel: last.date,
                                status: last.status,
                                priceLabel: formatMoney(last.price),
                                onTap: () => c.setTab(1),
                              ),
                            EmergencyNoticeBanner(api: c.api),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookingModeStrip extends StatelessWidget {
  final String selectedMode;
  final ValueChanged<String> onSelect;

  const _BookingModeStrip({
    required this.selectedMode,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    final modes = [
      (
        id: 'INSTANT',
        title: 'طلب فوري',
        sub: 'أقرب ممرض متاح',
        icon: Icons.bolt_rounded,
      ),
      (
        id: 'OPEN',
        title: 'سوق العروض',
        sub: 'قارن العروض',
        icon: Icons.storefront_rounded,
      ),
      (
        id: 'SCHEDULED',
        title: 'حجز مسبق',
        sub: 'حدد التاريخ والوقت',
        icon: Icons.event_available_rounded,
      ),
    ];

    return Row(
      children: modes.map((m) {
        final active = selectedMode == m.id;
        return Expanded(
          child: Padding(
            padding: EdgeInsetsDirectional.only(
              end: m.id != 'SCHEDULED' ? TamSpacing.sm : 0,
            ),
            child: InkWell(
              onTap: () => onSelect(m.id),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(TamSpacing.md),
                decoration: BoxDecoration(
                  color: active
                      ? tc.primaryTint.withValues(alpha: tc.isDark ? 0.35 : 0.65)
                      : tc.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: active ? tc.primary : tc.border,
                    width: active ? 1.5 : 1.0,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      m.icon,
                      size: 20,
                      color: active ? tc.primary : tc.textSecondary,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      m.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: aeroText(
                        size: 12.5,
                        weight: FontWeight.w700,
                        color: active ? tc.primaryDark : tc.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      m.sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: aeroText(size: 10.5, color: tc.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ServiceOption extends StatelessWidget {
  final ServiceItem service;
  final VoidCallback onTap;
  const _ServiceOption({required this.service, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    return TamCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBox(
            _serviceIcons[service.iconCode],
            tone: _serviceTones[service.iconCode],
            size: 38,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service.title,
                  style: tamText(
                    size: 14,
                    weight: FontWeight.w800,
                    color: tc.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'من ${formatMoney(service.price)}',
                  style: tamText(
                    size: 12,
                    weight: FontWeight.w700,
                    color: tc.primary,
                  ),
                ),
                if (service.requiresPrescription)
                  Text(
                    'تتطلب وصفة طبية',
                    style: tamText(size: 11, color: tc.warning),
                  ),
              ],
            ),
          ),
          Icon(Icons.chevron_left_rounded, size: 20, color: tc.primary),
        ],
      ),
    );
  }
}

class ActiveOrderBanner extends StatelessWidget {
  final PatientController c;
  const ActiveOrderBanner({super.key, required this.c});

  @override
  Widget build(BuildContext context) {
    String statusTitle;
    String statusSub;
    IconData icon;
    Color statusColor;

    switch (c.stage) {
      case VisitStage.interrupted:
        statusTitle = 'توقفت الزيارة';
        statusSub = 'حالة الطلب محدثة في سجل الزيارات';
        icon = Icons.info_outline;
        statusColor = TamreedyColors.navy;
        break;
      case VisitStage.scheduled:
        statusTitle = 'زيارة مجدولة';
        statusSub = 'يبدأ البحث قبل الموعد المحدد';
        icon = Icons.event_outlined;
        statusColor = TamreedyColors.teal;
        break;
      case VisitStage.searching:
        statusTitle = 'جارٍ البحث عن ممرض...';
        statusSub = 'يتم عرض طلبك على الكوادر التمريضية القريبة';
        icon = Icons.radar;
        statusColor = TamreedyColors.teal;
        break;
      case VisitStage.openMarketplace:
        statusTitle = c.activeProposalsCount > 0
            ? 'وصلك ${c.activeProposalsCount} عروض جاهزية!'
            : 'منشور في السوق المفتوح';
        statusSub = c.activeProposalsCount > 0
            ? 'اضغط لاستعراض العروض واختيار الممرض'
            : 'بانتظار تقديم الممرضين المؤهلين لعروضهم';
        icon = Icons.storefront_rounded;
        statusColor = AeroColors.accentTeal;
        break;
      case VisitStage.assigned:
        statusTitle = 'تم إسناد الزيارة';
        statusSub = 'بانتظار تأكيد انطلاق الممرض';
        icon = Icons.check_circle_outline;
        statusColor = TamreedyColors.teal;
        break;
      case VisitStage.enRoute:
        statusTitle = 'الممرض في الطريق إليك';
        statusSub = c.route?.etaLabel != null ? 'الوصول التقديري: ${c.route!.etaLabel}' : 'الممرض في طريقه لموقعك';
        icon = Icons.directions_car_filled_outlined;
        statusColor = const Color(0xFF2563EB);
        break;
      case VisitStage.arrived:
        statusTitle = 'وصل الممرض إلى موقعك';
        statusSub = 'الممرض متواجد عند العنوان المحدد';
        icon = Icons.pin_drop_outlined;
        statusColor = const Color(0xFF059669);
        break;
      case VisitStage.inService:
        statusTitle = 'الزيارة قيد التنفيذ';
        statusSub = 'يتم تقديم الخدمة التمريضية الآن';
        icon = Icons.healing_outlined;
        statusColor = const Color(0xFF7C3AED);
        break;
      case VisitStage.completed:
        statusTitle = 'تم إكمال الزيارة';
        statusSub = 'يرجى مراجعة تفاصيل الفاتورة والدفع';
        icon = Icons.task_alt;
        statusColor = const Color(0xFF0D9488);
        break;
      case VisitStage.unfulfilled:
        statusTitle = 'لم يُجب أحد على طلبك';
        statusSub = 'جميع الممرضين مشغولون حالياً، اضغط لإعادة المحاولة';
        icon = Icons.person_off_outlined;
        statusColor = const Color(0xFFDC2626);
        break;
      case VisitStage.none:
        return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withValues(alpha: 0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: statusColor.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => c.setTab(1),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: statusColor, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  statusTitle,
                                  style: tamText(size: 15, weight: FontWeight.w800, color: TamreedyColors.navy),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  'طلب نشط',
                                  style: tamText(size: 11, weight: FontWeight.w700, color: statusColor),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            statusSub,
                            style: tamText(size: 12, color: TamreedyColors.subtext),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'متابعة تفاصيل الطلب والتتبع المباشر',
                        style: tamText(size: 13, weight: FontWeight.w700, color: statusColor),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.arrow_back_ios_new, size: 13, color: statusColor),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class EmergencyNoticeBanner extends StatelessWidget {
  final TamreedyApi api;
  const EmergencyNoticeBanner({super.key, required this.api});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 16, bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: const BoxDecoration(
              color: Color(0xFFEF4444),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.emergency_outlined, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'تنبيه طبي للحالات الإسعافية',
                  style: tamText(size: 13, weight: FontWeight.w800, color: const Color(0xFF991B1B)),
                ),
                const SizedBox(height: 3),
                Text(
                  'منصة تمريضي مخصصة لخدمات الرعاية والتمريض المنزلي المجدولة وغير الطارئة. في الحالات الإسعافية الطارئة، اتصل بخدمات الطوارئ المحلية فورًا.',
                  style: tamText(size: 11.5, color: const Color(0xFF7F1D1D), height: 1.5),
                ),
                if (!kDemoMode)
                  TextButton(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => EmergencyDirectoryScreen(api: api),
                    )),
                    child: const Text('فتح دليل الطوارئ'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ServiceSkeletonGrid extends StatefulWidget {
  const ServiceSkeletonGrid({super.key});
  @override
  State<ServiceSkeletonGrid> createState() => _ServiceSkeletonGridState();
}

class _ServiceSkeletonGridState extends State<ServiceSkeletonGrid> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.35, end: 0.85).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        final opacity = _anim.value;
        return GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.95,
          children: List.generate(4, (i) => Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: TamreedyColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Opacity(
                  opacity: opacity,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: TamreedyColors.teal.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Opacity(
                  opacity: opacity,
                  child: Container(
                    width: 85,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Opacity(
                  opacity: opacity,
                  child: Container(
                    width: 60,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
          )),
        );
      },
    );
  }
}

class ServiceErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const ServiceErrorCard({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5F5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFEB2B2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.wifi_off_rounded, color: Color(0xFFE53E3E), size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: tamText(size: 13, weight: FontWeight.w600, color: const Color(0xFF9B2C2C)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('إعادة المحاولة'),
              style: ElevatedButton.styleFrom(
                backgroundColor: TamreedyColors.teal,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// P02 — service details.
class ServiceScreen extends StatefulWidget {
  final PatientController c;
  const ServiceScreen({super.key, required this.c});

  @override
  State<ServiceScreen> createState() => _ServiceScreenState();
}

class _ServiceScreenState extends State<ServiceScreen> {
  bool _nonEmergencyConfirmed = false;
  bool _prescriptionConfirmed = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final s = c.service!;
    final canProceed = _nonEmergencyConfirmed && (!s.requiresPrescription || _prescriptionConfirmed);

    return TamScaffold(
      title: 'تفاصيل الخدمة',
      subtitle: 'راجع البيانات والاشتراطات قبل طلب الممرض',
      showBack: true,
      nav: patientNavBar(context, c, 0),
      children: [
        const TamStepper(
          steps: ['الخدمة والمتطلبات', 'تحديد الموقع', 'مراجعة وتأكيد'],
          currentStep: 0,
        ),
        const SizedBox(height: TamSpacing.lg),
        TamCard(
          child: SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconBox(_serviceIcons[s.iconCode], size: 66),
                const SizedBox(height: 20),
                Text(
                  s.title == 'تغيير ضماد' ? 'العناية بالجروح' : s.title,
                  style: tamText(
                    size: 24,
                    weight: FontWeight.w800,
                    color: TamreedyColors.navy,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  s.note,
                  style: tamText(
                    size: 13,
                    color: TamreedyColors.subtext,
                    height: 1.7,
                  ),
                ),
                if (s.requiresPrescription) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.medical_information_outlined, color: Color(0xFFD97706), size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'تتطلب هذه الخدمة وجود وصفة طبية صالحة ومعتمدة. سيتحقق الممرض من الوصفة وتفاصيل الجرعة قبل تقديم الرعاية لسلامتكم.',
                            style: tamText(size: 12, color: const Color(0xFF92400E), height: 1.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (s.needsConfirmation) ...[
                  const SizedBox(height: 14),
                  const StatusChip('تحتاج تأكيد الحالة', warning: true),
                ],
              ],
            ),
          ),
        ),
        const SectionTitle('بيانات المستفيد والزيارة'),
        TamCard(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          child: Column(
            children: [
              if (c.beneficiaries.length > 1)
                DropdownButtonFormField<String>(
                  key: ValueKey(c.selectedBeneficiaryId),
                  initialValue: c.selectedBeneficiaryId,
                  decoration: const InputDecoration(labelText: 'المستفيد'),
                  isExpanded: true,
                  items: [
                    for (final person in c.beneficiaries)
                      DropdownMenuItem(value: person.id, child: Text(person.name)),
                  ],
                  onChanged: (id) {
                    if (id != null) c.selectBeneficiary(id);
                  },
                )
              else
                KeyValueRow('اسم المستفيد', c.beneficiary.isEmpty ? 'غير محدد' : c.beneficiary),
              const Divider(color: TamreedyColors.border, height: 1),
              InkWell(
                onTap: () {
                  showAeroModalBottomSheet(
                    context: context,
                    builder: (_) => AeroBookingModePickerSheet(
                      initialMode: c.bookingMode == 'OPEN'
                          ? AeroBookingMode.openMarketplace
                          : c.bookingMode == 'SCHEDULED'
                              ? AeroBookingMode.scheduled
                              : AeroBookingMode.instant,
                      onSelectMode: (mode) {
                        setState(() {
                          c.bookingMode = switch (mode) {
                            AeroBookingMode.openMarketplace => 'OPEN',
                            AeroBookingMode.scheduled => 'SCHEDULED',
                            AeroBookingMode.instant => 'INSTANT',
                          };
                        });
                      },
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('طريقة الحجز والوقت', style: tamText(size: 12, color: TamreedyColors.subtext)),
                            const SizedBox(height: 2),
                            Text(
                              c.bookingMode == 'OPEN'
                                  ? 'السوق المفتوح (استقبال عروض الجاهزية)'
                                  : c.bookingMode == 'SCHEDULED'
                                      ? 'حجز موعد مسبق'
                                      : 'طلب فوري (أقرب ممرض متاح)',
                              style: tamText(size: 13, weight: FontWeight.w700, color: AeroColors.primaryNavy),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Row(
                        children: [
                          Text('تغيير', style: aeroText(size: 12, weight: FontWeight.w600, color: AeroColors.accentTeal)),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_forward_ios_rounded, size: 13, color: AeroColors.accentTeal),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        EstimateCard(c: c),
        const SectionTitle('إقرارات السلامة الطبية الإلزامية'),
        TamCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: TamreedyColors.teal,
                value: _nonEmergencyConfirmed,
                onChanged: (val) => setState(() => _nonEmergencyConfirmed = val ?? false),
                title: Text(
                  'أقر بأن الحالة مستقرة وليست حالة إسعافية طارئة (للحالات الإسعافية اتصل بخدمات الطوارئ المحلية فورًا)',
                  style: tamText(size: 13, weight: FontWeight.w700, color: TamreedyColors.navy, height: 1.4),
                ),
              ),
              if (s.requiresPrescription) ...[
                const Divider(color: TamreedyColors.border, height: 16),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: TamreedyColors.teal,
                  value: _prescriptionConfirmed,
                  onChanged: (val) => setState(() => _prescriptionConfirmed = val ?? false),
                  title: Text(
                    'أؤكد وجود وصفة طبية رسمية وسارية المفعول ومستعد لإبرازها للممرض قبل تقديم الخدمة',
                    style: tamText(size: 13, weight: FontWeight.w700, color: const Color(0xFF92400E), height: 1.4),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        PrimaryButton(
          'متابعة إلى تحديد الموقع',
          onPressed: canProceed
              ? () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => LocationScreen(c: c)),
                  )
              : null,
        ),
      ],
    );
  }
}

/// Instant price estimate + promo code entry (P02).
class EstimateCard extends StatefulWidget {
  final PatientController c;
  const EstimateCard({super.key, required this.c});
  @override
  State<EstimateCard> createState() => _EstimateCardState();
}

class _EstimateCardState extends State<EstimateCard> {
  final _code = TextEditingController();
  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.c,
    builder: (context, _) {
      final c = widget.c;
      final s = c.service!;
      final e = c.est ?? estimatePrice(s.rule);
      final range = e.expected > e.min
          ? 'من ${formatMoney(e.min)} إلى نحو ${formatMoney(e.expected)}'
          : formatMoney(e.min);
      return TamCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            KeyValueRow('السعر المتوقع', range),
            if (c.quoteInfo['autoDiscount'] != null)
              KeyValueRow('خصم تلقائي', '${c.quoteInfo['promoCode']}'),
            KeyValueRow(
              'مشمول بالسعر الأساسي',
              'حتى ${s.rule.includedMinutes} دقيقة',
            ),
            if (s.rule.blockPrice > 0)
              KeyValueRow(
                'بعد ذلك',
                '${formatMoney(s.rule.blockPrice)} لكل ${s.rule.blockMinutes} دقيقة',
              ),
            if ((num.tryParse('${c.quoteInfo['surchargePercent']}') ?? 0) > 0)
              KeyValueRow(
                c.quoteInfo['holidayApplied'] == true
                    ? 'رسم العطلة (مُطبَّق الآن)'
                    : 'رسم ليلي (مُطبَّق الآن)',
                '+${c.quoteInfo['surchargePercent']}%',
              ),
            if ((num.tryParse('${c.quoteInfo['taxPercent']}') ?? 0) > 0)
              KeyValueRow('ضريبة', '${c.quoteInfo['taxPercent']}%'),
            if (c.quoteInfo['travelFeeMayApply'] == true)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'قد يُضاف رسم مسافة (${formatMoney((num.tryParse('${c.quoteInfo['perKm']}') ?? 0).round())} لكل كم بعد ${c.quoteInfo['freeKm']} كم) إن كان الممرض بعيدًا.',
                  style: tamText(
                    size: 11.5,
                    color: TamreedyColors.warning,
                    height: 1.6,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 10),
              child: Text(
                'السعر النهائي يُحسب من مدة بقاء الممرض عندك، ويظهر لك فور انتهاء الزيارة.',
                style: tamText(
                  size: 11.5,
                  color: TamreedyColors.subtext,
                  height: 1.6,
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: TamreedyColors.border),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      controller: _code,
                      textCapitalization: TextCapitalization.characters,
                      textDirection: TextDirection.ltr,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) {
                        FocusScope.of(context).unfocus();
                        c.applyPromo(_code.text.trim());
                      },
                      style: tamText(size: 14, weight: FontWeight.w700),
                      decoration: InputDecoration(
                        hintText: 'كود الخصم',
                        hintStyle: tamText(
                          size: 13,
                          color: TamreedyColors.subtext,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 44,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: TamreedyColors.teal,
                    ),
                    onPressed: () => c.applyPromo(_code.text),
                    child: Text(
                      'تطبيق',
                      style: tamText(
                        size: 13,
                        weight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (c.promoMsg != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  c.promoMsg!,
                  style: tamText(
                    size: 12,
                    weight: FontWeight.w700,
                    color: c.promoCode.isEmpty
                        ? TamreedyColors.danger
                        : TamreedyColors.success,
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

/// Home card: save the company's welcome code once; it is applied to the next order automatically.
class ClaimCodeCard extends StatefulWidget {
  final PatientController c;
  const ClaimCodeCard({super.key, required this.c});
  @override
  State<ClaimCodeCard> createState() => _ClaimCodeCardState();
}

class _ClaimCodeCardState extends State<ClaimCodeCard> {
  final _code = TextEditingController();
  String? _msg;
  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TamCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'لديك كود خصم؟',
          style: tamText(
            size: 15,
            weight: FontWeight.w800,
            color: TamreedyColors.navy,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: TamreedyColors.border),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  controller: _code,
                  textCapitalization: TextCapitalization.characters,
                  textDirection: TextDirection.ltr,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) async {
                    FocusScope.of(context).unfocus();
                    final m = await widget.c.claimCode(_code.text.trim());
                    if (mounted) setState(() => _msg = m);
                  },
                  style: tamText(size: 14, weight: FontWeight.w700),
                  decoration: InputDecoration(
                    hintText: 'أدخل الكود',
                    hintStyle: tamText(size: 13, color: TamreedyColors.subtext),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 44,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: TamreedyColors.teal,
                ),
                onPressed: () async {
                  final m = await widget.c.claimCode(_code.text);
                  if (mounted) setState(() => _msg = m);
                },
                child: Text(
                  'حفظ',
                  style: tamText(
                    size: 13,
                    weight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (_msg != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _msg!,
              style: tamText(
                size: 12,
                weight: FontWeight.w700,
                color: TamreedyColors.success,
              ),
            ),
          ),
      ],
    ),
  );
}
