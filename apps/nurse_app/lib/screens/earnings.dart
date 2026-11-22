import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../controller.dart';

/// N06 — earnings.
class EarningsScreen extends StatelessWidget {
  final NurseController c;
  final TamBottomNav nav;
  const EarningsScreen({super.key, required this.c, required this.nav});

  @override
  Widget build(BuildContext context) => TamScaffold(
    title: 'مستحقاتي',
    subtitle: 'عرض الأرباح والحركات المحاسبية',
    nav: nav,
    children: [
      HeroCard(
        caption: 'صافي مستحقاتي',
        title: formatMoney(c.netDue),
        titleSize: 34,
        trailing: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {},
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                child: Text(
                  'عرض التسويات',
                  style: tamText(
                    size: 13,
                    weight: FontWeight.w700,
                    color: TamreedyColors.navy,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      Row(
        children: [
          Expanded(child: StatCard('زيارات الشهر', '${c.monthVisits}')),
          const SizedBox(width: 12),
          Expanded(child: StatCard('عمولات المنصة', _n(c.commission))),
        ],
      ),
      _duesCard(),
      const SectionTitle('الحركات الأخيرة'),
      TamCard(
        child: Column(
          children: [
            for (var i = 0; i < c.history.length && i < 2; i++)
              ListRow(
                icon: Icons.payments_outlined,
                title: c.history[i].title,
                subtitle: '${i == 0 ? 'اليوم' : 'الأمس'} • حصة الممرض',
                trailing: StatusChip('+${_n(c.history[i].share)}'),
              ),
            const ListRow(
              icon: Icons.account_balance_wallet_outlined,
              title: 'تسوية نقدية',
              subtitle: 'تمت المراجعة',
              trailing: StatusChip('موثقة'),
              divider: false,
            ),
          ],
        ),
      ),
    ],
  );

  Widget _duesCard() {
    final d = c.dues;
    final balance = (num.tryParse('${d['balance']}') ?? 0).round();
    final limit = (num.tryParse('${d['limit']}') ?? 0).round();
    final blocked = d['blocked'] == true;
    return TamCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'مستحقات الشركة',
            style: tamText(
              size: 16,
              weight: FontWeight.w800,
              color: TamreedyColors.navy,
            ),
          ),
          const SizedBox(height: 10),
          KeyValueRow(
            balance >= 0 ? 'عليك للشركة' : 'للشركة عليها لك',
            formatMoney(balance.abs()),
          ),
          if (limit > 0) KeyValueRow('الحد المسموح', formatMoney(limit)),
          const SizedBox(height: 4),
          Text(
            blocked
                ? 'تجاوزتَ الحد: لن تصلك طلبات جديدة حتى تسلّم المستحقات للشركة.'
                : 'تقبض النقد من المريض وتسلّم الشركة حصتها (المبلغ المدفوع − نصيبك). تُسجَّل التسوية من الإدارة.',
            style: tamText(
              size: 11.5,
              color: blocked ? TamreedyColors.danger : TamreedyColors.subtext,
              height: 1.6,
            ),
          ),
          for (final h in (d['history'] as List? ?? []).take(3))
            KeyValueRow(
              h['direction'] == 'FROM_NURSE'
                  ? 'سلّمتَ للشركة'
                  : 'دفعت الشركة لك',
              formatMoney((num.tryParse('${h['amount']}') ?? 0).round()),
            ),
        ],
      ),
    );
  }

  static String _n(int v) => v.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );
}
