import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../controller.dart';
import '../main.dart';
export 'location.dart';
import 'location.dart';

const _serviceIcons = [
  Icons.vaccines_outlined,
  Icons.healing_outlined,
  Icons.monitor_heart_outlined,
  Icons.elderly_outlined,
];
const _serviceTones = [Tone.teal, Tone.blue, Tone.teal, Tone.orange];

class HomeScreen extends StatelessWidget {
  final PatientController c;
  final TamBottomNav nav;
  const HomeScreen({super.key, required this.c, required this.nav});

  @override
  Widget build(BuildContext context) {
    final last = c.history.isEmpty ? null : c.history.first;
    return TamScaffold(
      title: 'طلب تمريض منزلي',
      subtitle: 'رعاية مهنية موثوقة للعائلة',
      nav: nav,
      onRefresh: () => c.loadServices(),
      children: [
        const HeroCard(
          title: 'رعايتكم مسؤوليتنا',
          body: 'احجز ممرضًا مؤهلًا ليصل إلى عنوانك في دمشق وريف دمشق.',
        ),
        const SectionTitle('اختر الخدمة المطلوبة'),
        if (c.serviceState == ServiceLoadState.loading)
          const ServiceSkeletonGrid()
        else if (c.serviceState == ServiceLoadState.networkError || c.serviceState == ServiceLoadState.serverError)
          ServiceErrorCard(
            message: c.serviceError ?? 'تعذر الاتصال بالخادم لجلب الخدمات المتاحة.',
            onRetry: c.loadServices,
          )
        else if (c.serviceState == ServiceLoadState.empty)
          const NoticeBox('لا توجد خدمات منشورة حاليًا في منطقتك. تواصل مع الدعم للمساعدة.')
        else
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.95,
            children: [
              for (var i = 0; i < c.services.length; i++)
                TamCard(
                  onTap: () {
                    c.pick(c.services[i]);
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => ServiceScreen(c: c)),
                    );
                  },
                  child: SizedBox(
                    width: double.infinity,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            IconBox(
                              _serviceIcons[c.services[i].iconCode],
                              tone: _serviceTones[c.services[i].iconCode],
                              size: 46,
                            ),
                            const Spacer(),
                            if (c.services[i].requiresPrescription)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFFBEB),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFFFDE68A)),
                                ),
                                child: Text(
                                  'وصفة',
                                  style: tamText(size: 10, weight: FontWeight.w700, color: const Color(0xFFB45309)),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          c.services[i].title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tamText(
                            size: 14.5,
                            weight: FontWeight.w800,
                            color: TamreedyColors.navy,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          c.services[i].subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tamText(
                            size: 11,
                            color: TamreedyColors.subtext,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'من ${formatMoney(c.services[i].price)}',
                          style: tamText(
                            size: 12,
                            weight: FontWeight.w800,
                            color: TamreedyColors.teal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ClaimCodeCard(c: c),
        const SectionTitle('حجوزاتي الأخيرة'),
        if (last == null)
          const NoticeBox('لا توجد حجوزات سابقة بعد. اختر خدمة لتبدأ طلبك الأول.')
        else
          TamCard(
            child: ListRow(
              icon: Icons.check,
              title: last.title,
              subtitle: '${last.date} • ${formatMoney(last.price)}',
              trailing: StatusChip(last.status),
              divider: false,
            ),
          ),
      ],
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
class ServiceScreen extends StatelessWidget {
  final PatientController c;
  const ServiceScreen({super.key, required this.c});

  @override
  Widget build(BuildContext context) {
    final s = c.service!;
    return TamScaffold(
      title: 'تفاصيل الخدمة',
      subtitle: 'راجع البيانات قبل طلب الممرض',
      showBack: true,
      nav: patientNavBar(context, c, 0),
      children: [
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
                    size: 12.5,
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
        const SectionTitle('بيانات المستفيد'),
        TamCard(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          child: KeyValueRow('اسم المستفيد', c.beneficiary),
        ),
        const SectionTitle('بيانات الزيارة'),
        TamCard(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          child: const KeyValueRow('الوقت المطلوب', 'الآن'),
        ),
        TamCard(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          child: Row(
            children: [
              Text(
                'ملاحظات الحالة',
                style: tamText(size: 13, color: TamreedyColors.subtext),
              ),
              const Spacer(),
              Text(
                'إضافة ملاحظة',
                style: tamText(
                  size: 13,
                  weight: FontWeight.w700,
                  color: TamreedyColors.navy,
                ),
              ),
            ],
          ),
        ),
        EstimateCard(c: c),
        PrimaryButton(
          'متابعة',
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => LocationScreen(c: c))),
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
