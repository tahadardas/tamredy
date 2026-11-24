import 'cancellation_sheet.dart';
import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../controller.dart';
import 'payment.dart';

/// The amount due, shown to the patient immediately when the nurse closes the visit.
class BillCard extends StatelessWidget {
  final BillInfo bill;
  const BillCard({super.key, required this.bill});
  @override
  Widget build(BuildContext context) => TamCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'المبلغ المطلوب',
          style: tamText(size: 12, color: TamreedyColors.subtext),
        ),
        Text(
          formatMoney(bill.due),
          style: tamText(
            size: 30,
            weight: FontWeight.w800,
            color: TamreedyColors.navy,
          ),
        ),
        const Divider(color: TamreedyColors.border),
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

  @override
  Widget build(BuildContext context) {
    final s = c.service;
    if (c.stage == VisitStage.unfulfilled) {
      return TamScaffold(
        title: 'لم يتم العثور على ممرض',
        subtitle: 'تعذر توفير كادر متاح حالياً',
        nav: nav,
        children: [
          TamCard(
            padding: const EdgeInsets.fromLTRB(20, 32, 20, 28),
            child: Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFFCA5A5), width: 2),
                  ),
                  child: const Icon(
                    Icons.person_off_outlined,
                    size: 42,
                    color: Color(0xFFDC2626),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'نعتذر منك، لم يُجب أحد على طلبك',
                  style: tamText(
                    size: 19,
                    weight: FontWeight.w800,
                    color: TamreedyColors.navy,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'جميع الكوادر التمريضية القريبة منك مشغولة حالياً بزيارات أخرى، أو خارج نطاق التغطية اللحظية. يمكنك إعادة المحاولة الآن أو اختيار وقت لاحق.',
                  textAlign: TextAlign.center,
                  style: tamText(size: 13, color: TamreedyColors.subtext, height: 1.6),
                ),
                const SizedBox(height: 24),
                KeyValueRow('نوع الخدمة', s?.title ?? '—'),
                KeyValueRow('موقع الزيارة', c.address),
                const SizedBox(height: 24),
                PrimaryButton(
                  'إعادة المحاولة الآن',
                  onPressed: c.busy ? null : () async {
                    await c.retryRequest();
                  },
                ),
                const SizedBox(height: 12),
                SoftButton(
                  'العودة إلى الرئيسية',
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
        if (c.stage == VisitStage.completed)
          PrimaryButton(
            'متابعة إلى الدفع',
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => PaymentScreen(c: c))),
          )
        else ...[
          PrimaryButton(
            'الاتصال بالممرض',
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'الاتصال الهاتفي المقنّع يُفعَّل مع خدمة الاتصالات',
                ),
              ),
            ),
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

  Widget _tile(String a, String b, String sub) => Container(
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: TamreedyColors.canvas,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(a, style: tamText(size: 12, color: TamreedyColors.subtext)),
        Text(
          b,
          style: tamText(
            size: 17,
            weight: FontWeight.w800,
            color: TamreedyColors.navy,
          ),
        ),
        Text(sub, style: tamText(size: 11, color: TamreedyColors.subtext)),
      ],
    ),
  );
}
