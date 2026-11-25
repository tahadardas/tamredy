import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../controller.dart';

/// P06 — wallet. Funding is disabled until a licensed payment provider exists.
class WalletScreen extends StatefulWidget {
  final PatientController c;
  final TamBottomNav nav;
  const WalletScreen({super.key, required this.c, required this.nav});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  PatientController get c => widget.c;
  late Future<Map<String, dynamic>> _status;

  @override
  void initState() {
    super.initState();
    if (!kDemoMode) _status = _loadStatus();
  }

  Future<Map<String, dynamic>> _loadStatus() =>
      c.api.getMap('/v1/wallet/status');

  Future<void> _refreshStatus() async {
    final status = _loadStatus();
    setState(() {
      _status = status;
    });
    try {
      await status;
    } catch (_) {
      // FutureBuilder shows the retry state.
    }
  }

  Widget _liveStatus() => FutureBuilder<Map<String, dynamic>>(
    future: _status,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Column(
          children: [
            TamSkeleton.card(height: 120),
            SizedBox(height: TamSpacing.md),
            TamSkeleton.card(height: 80),
          ],
        );
      }
      if (snapshot.hasError || snapshot.data?['mode'] != 'DISABLED') {
        return TamErrorState(
          title: 'تعذر عرض حالة المحفظة',
          message: 'تعذر التحقق من حالة المحفظة الإلكترونية من الخادم.',
          onRetry: _refreshStatus,
        );
      }
      final reason = snapshot.data?['reason'];
      final msg = reason == 'LICENSED_PAYMENT_PROVIDER_REQUIRED'
          ? 'شحن المحفظة والدفع عبرها غير متاحين حاليًا. يمكنك الدفع نقدًا للممرض.'
          : 'المحفظة غير متاحة حاليًا. يمكنك الدفع نقدًا للممرض.';
      return Column(
        children: [
          TamCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const TamStatusBadge(
                  labelOverride: 'الدفع النقدي مفعّل',
                  iconOverride: Icons.payments_outlined,
                ),
                const SizedBox(height: TamSpacing.md),
                Text(
                  'حالة المحفظة الإلكترونية',
                  style: aeroText(
                    size: 16,
                    weight: FontWeight.w800,
                    color: context.tamColors.textPrimary,
                  ),
                ),
                const SizedBox(height: TamSpacing.xs),
                Text(
                  msg,
                  style: aeroText(
                    size: 13,
                    color: context.tamColors.textSecondary,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
          const NoticeBox(
            'لا تتوفر عمليات شحن رصيد حالياً؛ يتم تسديد الفواتير نقداً للممرض.',
          ),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) => TamScaffold(
    title: 'محفظتي',
    subtitle: 'الرصيد والحركات المالية',
    nav: widget.nav,
    onRefresh: kDemoMode ? null : _refreshStatus,
    children: kDemoMode
        ? [
            TamFinancialSummary(
              title: 'الرصيد المتاح (وضع تجريبي)',
              primaryValue: formatMoney(c.balance),
              subtitle: 'التعبئة الفعلية مرتبطة بمزود دفع مرخّص',
              metrics: const [
                (label: 'الشحن', value: 'من مزود معتمد', color: null),
                (label: 'الكشف', value: 'قابل للتتبع', color: null),
              ],
            ),
            const SectionTitle('آخر الحركات'),
            TamCard(
              child: Column(
                children: [
                  for (var i = 0; i < c.txs.length; i++)
                    ListRow(
                      icon: c.txs[i].amount > 0 &&
                              c.txs[i].title.startsWith('شحن')
                          ? Icons.add_rounded
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
            const NoticeBox(
              'التعبئة والدفع الفعليان مرتبطان بمزود خدمات دفع مرخّص.',
            ),
          ]
        : [_liveStatus()],
  );
}
