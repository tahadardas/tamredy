import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../../core/nurse_session_coordinator.dart';

String _money(Object? amount, Object? currency) {
  if (amount == null || currency is! String || currency.isEmpty) return '—';
  return formatMoney(amount,currency:currency);
}

class FinancialCenterScreen extends StatelessWidget {
  final NurseSessionCoordinator session;

  const FinancialCenterScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    final store = session.finance;

    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          return RefreshIndicator(
            onRefresh: store.refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: TamBreakpoints.maxContentWidth),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('المركز المالي والمستحقات',
                            style: aeroText(size: 18, weight: FontWeight.w800, color: tc.textPrimary)),
                        const SizedBox(height: 12),
                        if (store.loading && store.netDue == null)
                          const TamSkeleton.card(height: 150)
                        else if (store.error != null && store.netDue == null)
                          TamErrorState(
                            title: 'تعذر تحميل البيانات المالية',
                            message: store.error!,
                            onRetry: store.refresh,
                          )
                        else ...[
                          if (store.financialSetupRequired)
                            const NoticeBox('حسابك معتمد طبيًا، ويحتاج إلى استكمال الإعداد المالي من الإدارة.'),
                          if (store.legacyReconciliationRequired)
                            const NoticeBox('الرصيد التاريخي يحتاج تسوية إدارية لإثبات العملة قبل استخدامه'),
                          for (final account in store.financialAccountsByCurrency)
                            TamCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('حساب ${account['currencyCode']}', style: aeroText(size: 15, weight: FontWeight.w800)),
                              KeyValueRow('الرصيد المسبق', _money(account['prepaidBalance'],account['currencyCode'])),
                              KeyValueRow('المحجوز', _money(account['reservedBalance'],account['currencyCode'])),
                              KeyValueRow('المتاح', _money(account['availableBalance'],account['currencyCode'])),
                              KeyValueRow('الحد الائتماني', _money(account['creditLimit'],account['currencyCode'])),
                              if (account['settlementRequired'] == true) const NoticeBox('يحتاج الحساب إلى تسوية'),
                            ])),
                          TamFinancialSummary(
                            title: 'صافي المستحقات الحالية',
                            primaryValue: _money(store.primaryPosition?['balanceExact'] ?? store.primaryPosition?['balance'],store.currencyCode),
                            subtitle: 'بيانات موثقة ومطابقة لسجل القيود في الخادم',
                            metrics: [
                              (
                                label: 'زيارات الشهر',
                                value: store.monthVisits != null ? '${store.monthVisits}' : '—',
                                color: null,
                              ),
                              (
                                label: 'عمولات المنصة',
                                value: _money(store.commission,store.currencyCode),
                                color: null,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (store.currencyCode != null) TamCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('تفصيل الرصيد والتوريد (${store.currencyCode})',
                                    style: aeroText(size: 14.5, weight: FontWeight.w800)),
                                const SizedBox(height: 8),
                                KeyValueRow('رصيد متاح لك', _money(store.primaryPosition?['nursePayableExact'] ?? store.primaryPosition?['nursePayable'],store.currencyCode)),
                                KeyValueRow('مستحق توريده للشركة', _money(store.primaryPosition?['cashHeldExact'] ?? store.primaryPosition?['cashHeld'],store.currencyCode)),
                                if (store.balance != null)
                                  KeyValueRow('الرصيد الدفتري', _money(store.primaryPosition?['balanceExact'] ?? store.primaryPosition?['balance'],store.currencyCode)),
                              ],
                            ),
                          ),
                          const SectionTitle('سجل التسويات والحركات'),
                          if (store.settlementHistory.isEmpty && store.ledgerEntries.isEmpty)
                            const TamEmptyState(
                              icon: Icons.account_balance_wallet_outlined,
                              title: 'لا توجد قيود مالية مسجلة بعد',
                              message: 'تظهر جميع حركات العمولات والتحصيل والتوريد هنا تلقائياً.',
                            )
                          else ...[
                            for (final h in store.settlementHistory)
                              TamCard(
                                child: KeyValueRow(
                                  h['direction'] == 'FROM_NURSE' ? 'توريد للشركة' : 'دفعة مستلمة من الشركة',
                                  _money(h['amount'],h['currency_code']),
                                ),
                              ),
                            for (final entry in store.ledgerEntries.take(20))
                              TamCard(
                                child: KeyValueRow(
                                  '${entry['description'] ?? entry['entry_type'] ?? 'قيد مالي'}',
                                  _money(entry['amount'] ?? entry['debit_amount'] ?? entry['credit_amount'],entry['currency']),
                                ),
                              ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
