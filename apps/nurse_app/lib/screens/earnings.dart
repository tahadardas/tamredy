import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../controller.dart';

/// N06 — Nurse Earnings & Settlements Dashboard.
/// Supports Receivables, Prepaid, and Hybrid financial models from server data
/// without performing client-side dues math.
class EarningsScreen extends StatelessWidget {
  final NurseController c;
  final TamBottomNav nav;
  const EarningsScreen({super.key, required this.c, required this.nav});

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    final d = c.dues;
    final history = (d['history'] as List? ?? []).whereType<Map>().toList();

    return TamScaffold(
      title: 'مستحقاتي',
      subtitle: 'عرض الأرباح والحركات المحاسبية',
      nav: nav,
      onRefresh: c.loadLive,
      children: [
        TamFinancialSummary(
          title: 'صافي مستحقاتي',
          primaryValue: formatMoney(c.netDue),
          subtitle: 'إحصائيات الأرباح المعتمدة من الخادم',
          metrics: [
            (label: 'زيارات الشهر', value: '${c.monthVisits}', color: null),
            (label: 'عمولات المنصة', value: _n(c.commission), color: null),
          ],
        ),
        const SizedBox(height: TamSpacing.md),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AeroButton.secondary(
            'عرض سجل التسويات (${history.length})',
            height: 44,
            fontSize: 13.5,
            leadingIcon: Icon(Icons.receipt_long_rounded, size: 18, color: tc.primary),
            onPressed: () => _openSettlementsSheet(context, history),
          ),
        ),
        const SizedBox(height: TamSpacing.md),
        _duesCard(context),
        const SectionTitle('الحركات الأخيرة'),
        if (c.history.isEmpty)
          const TamEmptyState(
            icon: Icons.payments_outlined,
            title: 'لا توجد زيارات مكتملة بعد',
            message: 'ستظهر حصتك من كل زيارة مكتملة هنا فور انتهائها.',
          )
        else
          TamCard(
            child: Column(
              children: [
                for (var i = 0; i < c.history.length && i < 5; i++)
                  ListRow(
                    icon: Icons.payments_outlined,
                    title: c.history[i].title,
                    subtitle: '${c.history[i].date} • حصة الممرض',
                    trailing: StatusChip('+${_n(c.history[i].share)}'),
                    divider: i != (c.history.length < 5 ? c.history.length - 1 : 4),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  void _openSettlementsSheet(
    BuildContext context,
    List<Map> history,
  ) {
    TamBottomSheet.show(
      context,
      title: 'سجل التسويات المالية',
      subtitle: 'جميع حركات التسوية المسجلة من الإدارة',
      child: history.isEmpty
          ? const TamEmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: 'لا توجد تسويات مسجلة',
              message: 'ستظهر حركات توريد المستحقات أو التحويلات هنا عند تسجيلها.',
            )
          : Column(
              children: [
                for (final h in history)
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

  Widget _duesCard(BuildContext context) {
    final tc = context.tamColors;
    final d = c.dues;
    final balance = (num.tryParse('${d['balance']}') ?? 0).round();
    final limit = (num.tryParse('${d['limit']}') ?? 0).round();
    final prepaid = num.tryParse('${d['prepaidBalance'] ?? d['prepaid_balance']}');
    final held = num.tryParse('${d['heldBalance'] ?? d['held_balance']}');
    final model = d['financialModel'] ?? d['financial_model'];
    final blocked = d['blocked'] == true;
    final history = (d['history'] as List? ?? []).whereType<Map>().toList();

    return TamCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'مستحقات الشركة والتسويات',
                  style: aeroText(
                    size: 16,
                    weight: FontWeight.w800,
                    color: tc.textPrimary,
                  ),
                ),
              ),
              if (model != null)
                TamStatusBadge(
                  labelOverride: '$model',
                  compact: true,
                ),
            ],
          ),
          const SizedBox(height: TamSpacing.sm),
          KeyValueRow(
            balance >= 0 ? 'عليك للشركة' : 'للشركة لك',
            formatMoney(balance.abs()),
          ),
          if (limit > 0) KeyValueRow('حد الائتمان المسموح', formatMoney(limit)),
          if (prepaid != null)
            KeyValueRow('الرصيد المدفوع مسبقاً', formatMoney(prepaid.round())),
          if (held != null)
            KeyValueRow('الرصيد المحجوز', formatMoney(held.round())),
          const SizedBox(height: TamSpacing.xs),
          Text(
            blocked
                ? 'تجاوزتَ الحد المسموح: لن تصلك طلبات جديدة حتى تسوية المستحقات للشركة.'
                : 'تقبض النقد من المريض وتسلّم الشركة حصتها. تُسجَّل التسوية من الإدارة.',
            style: aeroText(
              size: 12,
              color: blocked ? tc.danger : tc.textSecondary,
              height: 1.55,
            ),
          ),
          if (history.isNotEmpty) ...[
            const SizedBox(height: TamSpacing.sm),
            Divider(color: tc.border),
            for (final h in history.take(3))
              KeyValueRow(
                h['direction'] == 'FROM_NURSE'
                    ? 'سلّمتَ للشركة'
                    : 'دفعت الشركة لك',
                formatMoney((num.tryParse('${h['amount']}') ?? 0).round()),
              ),
          ],
        ],
      ),
    );
  }

  static String _n(int v) => v.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );
}
