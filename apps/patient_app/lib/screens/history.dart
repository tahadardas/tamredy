import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../controller.dart';
import 'commitment.dart';

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
    children: [
      TamCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'البحث في الطلبات والتواريخ',
                style: tamText(size: 13, color: TamreedyColors.subtext),
              ),
            ),
            const Icon(Icons.search, color: TamreedyColors.navy),
          ],
        ),
      ),
      const SectionTitle('هذا الشهر'),
      if (c.history.isEmpty)
        const NoticeBox('لا توجد حجوزات بعد.')
      else
      TamCard(
        child: Column(
          children: [
            for (var i = 0; i < c.history.length; i++)
              ListRow(
                icon: c.history[i].status == 'ملغاة'
                    ? Icons.calendar_today_outlined
                    : Icons.check,
                title: c.history[i].title,
                subtitle:
                    '${c.history[i].date} • ${c.history[i].price == 0 ? 'أُلغي' : formatMoney(c.history[i].price)}',
                trailing: StatusChip(c.history[i].status),
                divider: i != c.history.length - 1,
              ),
          ],
        ),
      ),
      const SectionTitle('الخيارات'),
      SoftButton('سجل الالتزام بالمواعيد', onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => CommitmentScreen(api: c.api)),
      )),
      TamCard(
        child: Column(
          children: [
            ListRow(
              icon: Icons.description_outlined,
              title: 'عرض فاتورة',
              subtitle: 'نسخة إلكترونية مفصلة',
              trailing: const Icon(
                Icons.arrow_back,
                color: TamreedyColors.subtext,
              ),
              onTap: () {},
            ),
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
}
