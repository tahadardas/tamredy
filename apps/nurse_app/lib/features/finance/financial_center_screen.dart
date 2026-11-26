import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../../core/nurse_session_coordinator.dart';

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
                          TamFinancialSummary(
                            title: 'صافي المستحقات الحالية',
                            primaryValue: store.netDue != null ? formatMoney(store.netDue!) : '—',
                            subtitle: 'بيانات موثقة ومطابقة لسجل القيود في الخادم',
                            metrics: [
                              (
                                label: 'زيارات الشهر',
                                value: store.monthVisits != null ? '${store.monthVisits}' : '—',
                                color: null,
                              ),
                              (
                                label: 'عمولات المنصة',
                                value: store.commission != null ? formatMoney(store.commission!) : '—',
                                color: null,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TamCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('تفصيل الرصيد والتوريد',
                                    style: aeroText(size: 14.5, weight: FontWeight.w800)),
                                const SizedBox(height: 8),
                                KeyValueRow('رصيد متاح لك', formatMoney(store.nurseOwedAmount)),
                                KeyValueRow('مستحق توريده للشركة', formatMoney(store.companyOwedAmount)),
                                if (store.balance != null)
                                  KeyValueRow('الرصيد الدفتري', formatMoney(store.balance!)),
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
                                  formatMoney((num.tryParse('${h['amount'] ?? 0}') ?? 0).round()),
                                ),
                              ),
                            for (final entry in store.ledgerEntries.take(20))
                              TamCard(
                                child: KeyValueRow(
                                  '${entry['description'] ?? entry['entry_type'] ?? 'قيد مالي'}',
                                  formatMoney((num.tryParse('${entry['amount'] ?? 0}') ?? 0).round()),
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
