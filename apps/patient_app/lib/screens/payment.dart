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
class RatingScreen extends StatefulWidget {
  final PatientController c;
  const RatingScreen({super.key, required this.c});

  @override
  State<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends State<RatingScreen> {
  bool _submitting = false;
  String? _error;
  late final TextEditingController _commentCtrl;

  @override
  void initState() {
    super.initState();
    _commentCtrl = TextEditingController(text: widget.c.ratingComment);
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  String _ratingLabel(int stars) => switch (stars) {
    1 => 'غير راضٍ',
    2 => 'مقبول',
    3 => 'جيد',
    4 => 'جيد جداً',
    5 => 'ممتاز',
    _ => 'اختر عدد النجوم لتقييم الزيارة',
  };

  Widget _criteriaRow({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    final tc = context.tamColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: tc.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TamTypography.cardTitle(color: tc.textPrimary)),
                    Text(subtitle, style: TamTypography.supporting(color: tc.textSecondary)),
                  ],
                ),
              ),
              if (value > 0)
                TamStatusBadge(labelOverride: _ratingLabel(value), compact: true),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 2,
            children: [
              for (var i = 1; i <= 5; i++)
                Semantics(
                  button: true,
                  label: '$title: $i من 5',
                  child: IconButton(
                    iconSize: 28,
                    onPressed: _submitting ? null : () => onChanged(i),
                    icon: Icon(
                      i <= value ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: i <= value ? const Color(0xFFF59E0B) : tc.borderStrong,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final tc = context.tamColors;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => TamScaffold(
        title: 'تقييم الزيارة',
        subtitle: 'رأيك يساعدنا في تحسين جودة الرعاية',
        nav: patientNavBar(context, c, 0),
        children: [
          TamCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(Icons.verified_outlined, size: 42, color: tc.primary),
                const SizedBox(height: 14),
                Text(
                  'تم إكمال الزيارة',
                  style: TamTypography.pageTitle(color: tc.textPrimary),
                ),
                const SizedBox(height: 6),
                Text(
                  'نشكر ثقتك بتمريضي',
                  style: TamTypography.supporting(color: tc.textSecondary),
                ),
                const SizedBox(height: 20),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 4,
                  children: [
                    for (var i = 1; i <= 5; i++)
                      Semantics(
                        button: true,
                        label: '$i من 5 نجوم',
                        child: IconButton(
                          iconSize: 36,
                          onPressed: _submitting ? null : () => c.setRating(i),
                          icon: Icon(
                            i <= c.rating ? Icons.star_rounded : Icons.star_outline_rounded,
                            color: i <= c.rating
                                ? const Color(0xFFF59E0B)
                                : tc.borderStrong,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _ratingLabel(c.rating),
                  style: TamTypography.cardTitle(
                    color: c.rating > 0 ? tc.primary : tc.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SectionTitle('معايير التقييم التفصيلية (اختياري)'),
          TamCard(
            child: Column(
              children: [
                _criteriaRow(
                  context: context,
                  icon: Icons.schedule_rounded,
                  title: 'الالتزام بالموعد',
                  subtitle: 'حضور الممرض في الوقت المتفق عليه',
                  value: c.punctualityRating,
                  onChanged: c.setPunctualityRating,
                ),
                Divider(color: tc.border),
                _criteriaRow(
                  context: context,
                  icon: Icons.medical_services_outlined,
                  title: 'الاحترافية',
                  subtitle: 'تنفيذ الخدمة بدقة ومهنية طبية',
                  value: c.clinicalRating,
                  onChanged: c.setClinicalRating,
                ),
                Divider(color: tc.border),
                _criteriaRow(
                  context: context,
                  icon: Icons.favorite_outline_rounded,
                  title: 'حسن التعامل',
                  subtitle: 'الاحترام واللباقة والتواصل الواضح',
                  value: c.conductRating,
                  onChanged: c.setConductRating,
                ),
                Divider(color: tc.border),
                const SizedBox(height: 8),
                TextField(
                  controller: _commentCtrl,
                  maxLines: 3,
                  enabled: !_submitting,
                  onChanged: c.setRatingComment,
                  decoration: InputDecoration(
                    labelText: 'ملاحظات إضافية (اختياري)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_error != null) NoticeBox(_error!),
          PrimaryButton(
            _submitting ? 'جارٍ حفظ التقييم...' : 'إرسال التقييم',
            onPressed: (_submitting || c.rating <= 0)
                ? null
                : () async {
                    setState(() {
                      _submitting = true;
                      _error = null;
                    });
                    try {
                      await c.submitRating();
                      c.reset();
                      if (context.mounted) {
                        Navigator.of(context).popUntil((r) => r.isFirst);
                      }
                    } catch (e) {
                      if (mounted) {
                        setState(() {
                          _error = explainError(e, fallback: 'تعذر حفظ التقييم، حاول مجدداً.');
                        });
                      }
                    } finally {
                      if (mounted) setState(() => _submitting = false);
                    }
                  },
          ),
        ],
      ),
    );
  }
}
