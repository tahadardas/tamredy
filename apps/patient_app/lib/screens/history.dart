import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../controller.dart';
import 'commitment.dart';
import 'track.dart' show BillCard;

/// P09 — order history.
class HistoryScreen extends StatelessWidget {
  final PatientController c;
  final TamBottomNav nav;
  const HistoryScreen({super.key, required this.c, required this.nav});

  @override
  Widget build(BuildContext context) => TamScaffold(
    title: 'سجل طلباتي',
    subtitle: 'تابع الحجوزات والفواتير السابقة',
    nav: nav,
    onRefresh: kDemoMode ? null : c.loadHistory,
    children: [
      if (c.historyError != null) ...[
        NoticeBox(c.historyError!),
        OutlinedButton(
          onPressed: c.loadHistory,
          child: const Text('إعادة المحاولة'),
        ),
      ],
      if (c.history.isEmpty && c.historyError == null)
        const NoticeBox('لا توجد حجوزات بعد.')
      else if (c.history.isNotEmpty)
        TamCard(
          child: Column(
            children: [
              for (var i = 0; i < c.history.length; i++)
                ListRow(
                  icon: c.history[i].status == 'ملغاة'
                      ? Icons.calendar_today_outlined
                      : Icons.check,
                  title: c.history[i].title,
                  subtitle: c.history[i].status == 'مكتملة'
                      ? '${c.history[i].date} • ${formatMoney(c.history[i].price)}'
                      : c.history[i].date,
                  trailing: StatusChip(c.history[i].status),
                  divider: i != c.history.length - 1,
                  onTap:
                      c.history[i].requestId != null &&
                          c.history[i].status == 'مكتملة'
                      ? () => _showBill(context, c.history[i].requestId!)
                      : null,
                ),
            ],
          ),
        ),
      const SectionTitle('الخيارات'),
      SoftButton(
        'سجل الالتزام بالمواعيد',
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => CommitmentScreen(api: c.api))),
      ),
      TamCard(
        child: Column(
          children: [
            ListRow(
              icon: Icons.add,
              title: 'تكرار طلب',
              subtitle: 'حجز الخدمة مرة أخرى',
              trailing: const Icon(
                Icons.arrow_back,
                color: TamreedyColors.subtext,
              ),
              divider: false,
              onTap: () => c.setTab(0),
            ),
          ],
        ),
      ),
    ],
  );
  Future<void> _showBill(BuildContext context, String requestId) async {
    final bill = c.api
        .getMap('/v1/requests/$requestId/bill')
        .then(BillInfo.fromJson);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: FutureBuilder<BillInfo>(
            future: bill,
            builder: (context, snapshot) {
              if (snapshot.hasError)
                return const NoticeBox('تعذر تحميل الفاتورة. حاول مجددًا.');
              if (!snapshot.hasData) return const LinearProgressIndicator();
              return BillCard(bill: snapshot.data!);
            },
          ),
        ),
      ),
    );
  }
}
