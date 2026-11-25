import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../controller.dart';
import '../main.dart';
import 'track.dart' show BillCard;

/// P07 — payment. The patient pays the nurse in cash; the nurse records the amount received,
/// and this screen follows that status live (partial payments show the remaining amount).
class PaymentScreen extends StatefulWidget {
  final PatientController c;
  const PaymentScreen({super.key, required this.c});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  PatientController get c => widget.c;
  bool _refreshing = false;

  Future<void> _refreshPayment() async {
    setState(() => _refreshing = true);
    final refreshed = await c.loadBill();
    if (!mounted) return;

    setState(() => _refreshing = false);
    final bill = c.bill;
    final message = !refreshed || bill == null
        ? 'تعذر تحديث الفاتورة. حاول مجددًا.'
        : switch (bill.status) {
            'PAID' => 'تم تأكيد الدفع بالكامل.',
            'PARTIAL' => 'تم تسجيل دفعة جزئية. المتبقي ${formatMoney(bill.remaining)}.',
            _ => 'لم يسجّل الممرض استلام المبلغ بعد.',
          };
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    return ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final bill = c.bill;
      final paid = bill?.status == 'PAID';
      Widget option(
        String id,
        IconData icon,
        String title,
        String sub, {
        bool enabled = true,
      }) => Opacity(
        opacity: enabled ? 1 : .45,
        child: ListRow(
          icon: icon,
          title: title,
          subtitle: enabled ? sub : 'غير متاح حاليًا',
          onTap: enabled ? () => c.setPay(id) : null,
          divider: id != 'mixed',
          trailing: Icon(
            c.payMethod == id
                ? Icons.radio_button_checked
                : Icons.radio_button_off,
            color: c.payMethod == id ? tc.primary : tc.textSecondary,
          ),
        ),
      );
      return TamScaffold(
        title: 'تأكيد الدفع',
        subtitle: 'المبلغ يُحسب من مدة الزيارة',
        showBack: true,
        nav: patientNavBar(context, c, 0),
        children: [
          if (bill != null)
            BillCard(bill: bill)
          else
            const TamCard(child: Text('حدّث حالة الدفع لعرض الفاتورة.')),
          const SectionTitle('طريقة الدفع'),
          TamCard(
            child: Column(
              children: [
                option(
                  'cash',
                  Icons.payments_outlined,
                  'الدفع النقدي للممرض',
                  'يسجّل الممرض المبلغ الذي استلمه',
                ),
                // Wallet needs a licensed payment provider (ADR-006): selectable in the demo only.
                option(
                  'wallet',
                  Icons.account_balance_wallet_outlined,
                  'الدفع من المحفظة',
                  'رصيد متاح ${formatMoney(c.balance)}',
                  enabled: kDemoMode,
                ),
                option(
                  'mixed',
                  Icons.add,
                  'دفع مختلط',
                  'محفظة + نقد',
                  enabled: kDemoMode,
                ),
              ],
            ),
          ),
          if (bill != null && !paid) ...[
            const SectionTitle('إكرامية للممرض (اختياري)'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in const [0, 500, 1000, 2000])
                  ChoiceChip(
                    label: Text(
                      t == 0 ? 'بدون' : formatMoney(t),
                      style: tamText(
                        size: 12.5,
                        weight: FontWeight.w700,
                        color: bill.tip == t ? tc.primaryDark : tc.textPrimary,
                      ),
                    ),
                    selected: bill.tip == t,
                    onSelected: (_) => c.setTip(t),
                    selectedColor: tc.primaryTint,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'تُضاف إلى المبلغ المسلَّم للممرض وتعود إليه كاملة.',
              style: tamText(size: 11.5, color: tc.textSecondary),
            ),
          ],
          if (bill != null && !paid)
            NoticeBox(
              bill.status == 'PARTIAL'
                  ? 'تم استلام ${formatMoney(bill.collected)} والمتبقي ${formatMoney(bill.remaining)}. أكمل الدفع للممرض.'
                  : 'سلّم المبلغ للممرض؛ سيظهر هنا فور تسجيله.',
            ),
          if (paid) const StatusChip('تم الدفع بالكامل'),
          const SizedBox(height: 10),
          PrimaryButton(
            _refreshing
                ? 'جارٍ تحديث حالة الدفع…'
                : paid || (kDemoMode && bill != null)
                ? 'متابعة إلى التقييم'
                : 'تحديث حالة الدفع',
            onPressed: _refreshing
                ? null
                : paid || (kDemoMode && bill != null)
                ? () {
                    c.finishPayment();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => RatingScreen(c: c)),
                    );
                  }
                : _refreshPayment,
          ),
        ],
      );
    },
  );
  }
}

/// P08 — rate the visit.
class RatingScreen extends StatelessWidget {
  final PatientController c;
  const RatingScreen({super.key, required this.c});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) => TamScaffold(
      title: 'تقييم الزيارة',
      subtitle: 'رأيك يساعدنا في تحسين الجودة',
      nav: patientNavBar(context, c, 0),
      children: [
        TamCard(
          padding: const EdgeInsets.all(26),
          child: Column(
            children: [
              const Icon(Icons.check, size: 40, color: TamreedyColors.teal),
              const SizedBox(height: 16),
              Text(
                'تم إكمال الزيارة',
                style: tamText(
                  size: 22,
                  weight: FontWeight.w800,
                  color: TamreedyColors.navy,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'نشكر ثقتك بتمريضي',
                style: tamText(size: 12, color: TamreedyColors.subtext),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 1; i <= 5; i++)
                    IconButton(
                      onPressed: () => c.setRating(i),
                      icon: Icon(
                        Icons.star,
                        size: 34,
                        color: i <= c.rating
                            ? const Color(0xFFF2B01E)
                            : TamreedyColors.border,
                      ),
                    ),
                ],
              ),
              Text(
                'كيف تقيّم الممرض؟',
                style: tamText(size: 14, weight: FontWeight.w600),
              ),
            ],
          ),
        ),
        const SectionTitle('قيّم جوانب الخدمة'),
        TamCard(
          child: Column(
            children: const [
              ListRow(
                icon: Icons.schedule,
                title: 'الالتزام بالموعد',
                subtitle: 'الممرض حضر في الوقت المتفق عليه',
                trailing: StatusChip('ممتاز'),
              ),
              ListRow(
                icon: Icons.check,
                title: 'الاحترافية',
                subtitle: 'تم تنفيذ الخدمة بطريقة مهنية',
                trailing: StatusChip('ممتاز'),
              ),
              ListRow(
                icon: Icons.favorite_border,
                title: 'حسن التعامل',
                subtitle: 'احترام ولباقة',
                trailing: StatusChip('ممتاز'),
                divider: false,
              ),
            ],
          ),
        ),
        PrimaryButton(
          'إرسال التقييم',
          onPressed: () async {
            await c.submitRating();
            c.reset();
            if (context.mounted) {
              Navigator.of(context).popUntil((r) => r.isFirst);
            }
          },
        ),
      ],
    ),
  );
}
