import 'dart:async';
import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../../core/patient_session_coordinator.dart';
import 'rating_screen.dart';

class InvoicePaymentScreen extends StatefulWidget {
  final PatientSessionCoordinator session;
  final String requestId;

  const InvoicePaymentScreen({
    super.key,
    required this.session,
    required this.requestId,
  });

  @override
  State<InvoicePaymentScreen> createState() => _InvoicePaymentScreenState();
}

class _InvoicePaymentScreenState extends State<InvoicePaymentScreen> {
  BillInfo? _bill;
  bool _loading = true;
  bool _busyTip = false;
  String? _error;
  StreamSubscription<RealtimeEvent>? _paymentSub;

  @override
  void initState() {
    super.initState();
    _load();
    // BUG-045: Live auto-refresh invoice status when nurse collects cash or issues tip/bill updates.
    _paymentSub = widget.session.eventBus
        .whereType({'payment.paid', 'payment.partially_paid', 'payment.tip', 'visit.complete'})
        .listen((evt) {
      final evtReqId = evt.payload['requestId']?.toString() ?? evt.payload['request_id']?.toString();
      if (evtReqId == null || evtReqId.isEmpty || evtReqId == widget.requestId) {
        unawaited(_load(silent: true));
      }
    });
  }

  @override
  void dispose() {
    _paymentSub?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final b = await widget.session.finance.loadBill(widget.requestId);
      if (mounted) {
        setState(() {
          _bill = b;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && !silent) {
        setState(() {
          _error = explainError(e, fallback: 'تعذر تحميل الفاتورة');
          _loading = false;
        });
      }
    }
  }

  Future<void> _applyTip(int amount) async {
    if (_busyTip) return;
    setState(() => _busyTip = true);
    try {
      final updated = await widget.session.finance.applyTip(widget.requestId, amount);
      if (mounted) {
        setState(() => _bill = updated);
        TamToast.show(
          context,
          amount == 0 ? 'تم إلغاء الإكرامية' : 'تمت إضافة الإكرامية (${formatMoney(amount)})',
          tone: TamToastTone.success,
        );
      }
    } catch (e) {
      if (mounted) TamToast.show(context, explainError(e), tone: TamToastTone.error);
    } finally {
      if (mounted) setState(() => _busyTip = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    final bill = _bill;
    final paid = bill?.status == 'PAID';

    return TamScaffold(
      title: 'تفاصيل الفاتورة والدفع',
      subtitle: 'تُحتسب الفاتورة بناءً على مدة الزيارة والخدمات المنفذة',
      showBack: true,
      onRefresh: _load,
      children: [
        if (_loading && bill == null) ...[
          const TamSkeleton.card(height: 220),
        ] else if (_error != null && bill == null) ...[
          TamErrorState(
            title: 'تعذر عرض الفاتورة',
            message: _error!,
            onRetry: _load,
          ),
        ] else if (bill != null) ...[
          TamCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('المبلغ المستحق للدفع', style: aeroText(size: 12.5, color: tc.textSecondary)),
                const SizedBox(height: 4),
                Text(
                  formatMoney(bill.payable),
                  style: aeroText(size: 28, weight: FontWeight.w800, color: tc.textPrimary),
                ),
                const SizedBox(height: 8),
                TamStatusBadge(
                  status: bill.status,
                  labelOverride: paid
                      ? 'تم الدفع بالكامل'
                      : bill.status == 'PARTIAL'
                          ? 'مدفوع جزئياً'
                          : 'بانتظار الدفع النقدي للممرض',
                  compact: true,
                ),
                const Divider(height: 22),
                KeyValueRow('مدة الزيارة', '${bill.minutes} دقيقة'),
                KeyValueRow('قيمة الخدمات الأساسية', formatMoney(bill.gross - bill.surcharge)),
                if (bill.surcharge > 0) KeyValueRow('رسوم ليلي/عطلة', formatMoney(bill.surcharge)),
                if (bill.distanceFee > 0) KeyValueRow('رسوم المسافة', formatMoney(bill.distanceFee)),
                if (bill.discount > 0)
                  KeyValueRow(
                    bill.promoCode != null ? 'خصم ${bill.promoCode}' : 'الخصم',
                    '−${formatMoney(bill.discount)}',
                  ),
                if (bill.tax > 0) KeyValueRow(bill.taxLabel, formatMoney(bill.tax)),
                if (bill.tip > 0) KeyValueRow('إكرامية الممرض', formatMoney(bill.tip)),
                if (bill.collected > 0) KeyValueRow('المبلغ المستلم', formatMoney(bill.collected)),
                if (!paid && bill.collected > 0)
                  KeyValueRow('المتبقي', formatMoney(bill.remaining)),
              ],
            ),
          ),
          TamCard(
            child: Row(
              children: [
                Icon(Icons.payments_outlined, color: tc.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('طريقة الدفع المعتمدة: نقداً عند إكمال الزيارة',
                          style: aeroText(size: 13.5, weight: FontWeight.w800)),
                      Text(
                        'سلّم المبلغ للممرض ليقوم بتوثيق التحصيل في النظام فوراً.',
                        style: aeroText(size: 12, color: tc.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (!paid) ...[
            const SectionTitle('إكرامية اختيارية للممرض'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tipAmt in const [0, 5000, 10000, 20000])
                  ChoiceChip(
                    label: Text(tipAmt == 0 ? 'بدون' : formatMoney(tipAmt)),
                    selected: bill.tip == tipAmt,
                    onSelected: _busyTip ? null : (_) => _applyTip(tipAmt),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            PrimaryButton(
              'تحديث حالة التحصيل',
              onPressed: _load,
            ),
          ] else ...[
            PrimaryButton(
              'تقييم الزيارة والممرض',
              onPressed: () {
                final visitId = bill.visitId;
                if (visitId == null || visitId.isEmpty) {
                  TamToast.show(context, 'تعذر العثور على معرف الزيارة للتقييم', tone: TamToastTone.warning);
                  return;
                }
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute<void>(
                    builder: (_) => VisitRatingScreen(
                      session: widget.session,
                      visitId: visitId,
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ],
    );
  }
}
