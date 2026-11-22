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

/// P04 (searching) and P05 (nurse tracking) driven by the request stage.
class TrackScreen extends StatelessWidget {
  final PatientController c;
  final TamBottomNav nav;
  const TrackScreen({super.key, required this.c, required this.nav});

  @override
  Widget build(BuildContext context) {
    final s = c.service;
    if (c.stage == VisitStage.searching) {
      return TamScaffold(
        title: 'جارٍ البحث عن ممرض',
        subtitle: 'نبحث عن كادر مؤهل قريب منك',
        nav: nav,
        children: [
          TamMap(height: 200, patient: c.position ?? kDamascus),
          const SizedBox(height: 12),
          TamCard(
            padding: const EdgeInsets.fromLTRB(18, 28, 18, 18),
            child: Column(
              children: [
                const Icon(Icons.search, size: 40, color: TamreedyColors.teal),
                const SizedBox(height: 18),
                Text(
                  'جارٍ عرض طلبك',
                  style: tamText(
                    size: 22,
                    weight: FontWeight.w800,
                    color: TamreedyColors.navy,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'سيظهر الممرض المكلّف فور قبول الطلب',
                  style: tamText(size: 12, color: TamreedyColors.subtext),
                ),
                const SizedBox(height: 22),
                const StepBar(filled: 2),
                const SizedBox(height: 12),
                KeyValueRow('نوع الخدمة', s?.title ?? '—'),
                KeyValueRow('موقع الطلب', c.address),
              ],
            ),
          ),
          SoftButton(
            'إلغاء الطلب',
            onPressed: c.busy ? null : () => _confirmCancel(context, c),
          ),
        ],
      );
    }
    final titles = {
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
          if (c.stage == VisitStage.enRoute)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SoftButton(
                'إلغاء الطلب',
                onPressed: c.busy ? null : () => _confirmCancel(context, c),
              ),
            ),
        ],
      ],
    );
  }

  static Future<void> _confirmCancel(BuildContext context, PatientController c) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد إلغاء الطلب'),
        content: const Text('هل أنت متأكد من رغبتك في إلغاء هذا الطلب؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('تراجع'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('نعم، إلغاء الطلب', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      final success = await c.cancel();
      if (!success && context.mounted && c.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(c.error!), backgroundColor: Colors.red),
        );
      }
    }
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
