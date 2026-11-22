import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../controller.dart';

/// P06 — wallet. Funding is disabled until a licensed payment provider exists.
class WalletScreen extends StatelessWidget {
  final PatientController c;
  final TamBottomNav nav;
  const WalletScreen({super.key, required this.c, required this.nav});

  @override
  Widget build(BuildContext context) => TamScaffold(
    title: 'محفظتي',
    subtitle: 'الرصيد والحركات المالية',
    nav: nav,
    children: [
      HeroCard(
        caption: 'الرصيد المتاح',
        title: formatMoney(c.balance),
        titleSize: 34,
      ),
      Row(
        children: const [
          Expanded(child: StatCard('شحن رصيد', 'من مزود معتمد')),
          SizedBox(width: 12),
          Expanded(child: StatCard('كشف الحركات', 'قابل للتتبع')),
        ],
      ),
      const SectionTitle('آخر الحركات'),
      TamCard(
        child: Column(
          children: [
            for (var i = 0; i < c.txs.length; i++)
              ListRow(
                icon: c.txs[i].amount > 0 && c.txs[i].title.startsWith('شحن')
                    ? Icons.add
                    : (c.txs[i].amount > 0
                          ? Icons.account_balance_wallet_outlined
                          : Icons.payments_outlined),
                title: c.txs[i].title,
                subtitle: c.txs[i].sub,
                trailing: StatusChip(
                  '${c.txs[i].amount > 0 ? '+' : '−'}${c.txs[i].amount.abs().toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},')}',
                ),
                divider: i != c.txs.length - 1,
              ),
          ],
        ),
      ),
      const NoticeBox('التعبئة والدفع الفعليان مرتبطان بمزود خدمات دفع مرخّص.'),
    ],
  );
}
