import 'dart:async';
import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import 'package:url_launcher/url_launcher.dart';
import '../controller.dart';
import '../main.dart';

/// Routes N02..N05 by the current stage.
class VisitFlowScreen extends StatelessWidget {
  final NurseController c;
  final TamBottomNav nav;
  const VisitFlowScreen({super.key, required this.c, required this.nav});

  @override
  Widget build(BuildContext context) {
    switch (c.stage) {
      case NurseStage.offer:
        return OfferScreen(c: c, nav: nav);
      case NurseStage.enRoute:
      case NurseStage.arrived:
        return _navigation(context);
      case NurseStage.inService:
        return _inService(context);
      default:
        return _complete(context);
    }
  }

  // N03
  Widget _navigation(BuildContext context) {
    final arrived = c.stage == NurseStage.arrived;
    return TamScaffold(
      title: arrived ? 'وصلت إلى الموقع' : 'تم قبول الطلب',
      subtitle: 'اتجه إلى موقع المريض المؤكد',
      nav: nav,
      children: [
        TamMap(
          height: 300,
          patient: c.dest ?? kDamascus,
          nurse: c.myPos,
          route: c.route,
        ),
        const SizedBox(height: 12),
        TamCard(
          child: Column(
            children: [
              ListRow(
                icon: Icons.location_on_outlined,
                title: 'موقع وعنوان الزيارة',
                subtitle: c.patientAddress.isNotEmpty
                    ? c.patientAddress
                    : 'الموقع المحدد على الخريطة',
              ),
              KeyValueRow('الحالة', arrived ? 'وصل' : 'في الطريق'),
              KeyValueRow(
                'زمن الوصول',
                arrived
                    ? '—'
                    : (c.route == null
                          ? '—'
                          : '${c.route!.etaLabel} • ${c.route!.distanceLabel}'),
              ),
            ],
          ),
        ),
        PrimaryButton(
          'فتح الملاحة في الخرائط',
          onPressed: () => launchUrl(
            Uri.parse(
              'https://www.google.com/maps/dir/?api=1&travelmode=driving&destination=${(c.dest ?? kDamascus).latitude},${(c.dest ?? kDamascus).longitude}',
            ),
            mode: LaunchMode.externalApplication,
          ),
        ),
        if (!arrived)
          SoftButton('وصلت إلى الموقع', onPressed: c.arrive)
        else
          PrimaryButton('بدء الزيارة', onPressed: c.start),
      ],
    );
  }

  // N04
  Widget _inService(BuildContext context) => TamScaffold(
    title: 'الزيارة قيد التنفيذ',
    subtitle: 'أنت غير متاح للطلبات الجديدة',
    nav: nav,
    children: [
      HeroCard(
        title: 'زيارة تمريض منزلية',
        body: 'بدأت الزيارة بنجاح',
        trailing: Align(
          alignment: AlignmentDirectional.centerStart,
          child: const StatusChip('قيد التنفيذ'),
        ),
      ),
      TamCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'قائمة إكمال الخدمة',
              style: tamText(
                size: 16,
                weight: FontWeight.w800,
                color: TamreedyColors.navy,
              ),
            ),
            const ListRow(
              icon: Icons.check,
              title: 'التحقق من المستفيد',
              subtitle: 'تم',
            ),
            const ListRow(
              icon: Icons.description_outlined,
              title: 'تنفيذ الإجراء المسموح',
              subtitle: 'ضمن صلاحياتك المهنية',
            ),
            const ListRow(
              icon: Icons.note_outlined,
              title: 'إضافة ملاحظات الزيارة',
              subtitle: 'لا تُرسل بيانات حساسة دون حاجة',
              divider: false,
            ),
          ],
        ),
      ),
      const SectionTitle('بعد انتهاء الزيارة'),
      PrimaryButton('إنهاء الزيارة والعودة متاحًا', onPressed: c.complete),
      SoftButton(
        'الإبلاغ عن مشكلة',
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => ReportScreen(c: c))),
      ),
    ],
  );

  // N05 — bill + cash collection. The nurse cannot go back to "available" until the bill is fully paid.
  Widget _complete(BuildContext context) {
    final bill = c.bill;
    final paid = bill?.status == 'PAID';
    return TamScaffold(
      title: 'إنهاء الزيارة',
      subtitle: 'المبلغ المطلوب والتحصيل',
      nav: nav,
      children: [
        TamCard(
          padding: const EdgeInsets.all(24),
          child: SizedBox(
            width: double.infinity,
            child: Column(
              children: [
                Icon(
                  paid ? Icons.check_circle : Icons.receipt_long,
                  size: 40,
                  color: TamreedyColors.teal,
                ),
                const SizedBox(height: 14),
                Text(
                  paid ? 'تم التحصيل بالكامل' : 'المبلغ المطلوب من المريض',
                  style: tamText(
                    size: 15,
                    weight: FontWeight.w700,
                    color: TamreedyColors.navy,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  bill == null ? '...' : formatMoney(bill.payable),
                  style: tamText(
                    size: 34,
                    weight: FontWeight.w800,
                    color: TamreedyColors.navy,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'يظهر نفس المبلغ للمريض الآن',
                  style: tamText(size: 11.5, color: TamreedyColors.subtext),
                ),
              ],
            ),
          ),
        ),
        if (bill != null)
          TamCard(
            child: Column(
              children: [
                KeyValueRow('مدة الزيارة', '${bill.minutes} دقيقة'),
                KeyValueRow(
                  'قيمة الخدمة',
                  formatMoney(bill.gross - bill.surcharge),
                ),
                if (bill.surcharge > 0)
                  KeyValueRow('رسم ليلي/عطلة', formatMoney(bill.surcharge)),
                if (bill.distanceFee > 0)
                  KeyValueRow(
                    'رسم المسافة (لك كاملًا)',
                    formatMoney(bill.distanceFee),
                  ),
                if (bill.discount > 0)
                  KeyValueRow('خصم المريض', '−${formatMoney(bill.discount)}'),
                if (bill.tax > 0)
                  KeyValueRow(bill.taxLabel, formatMoney(bill.tax)),
                if (bill.tip > 0)
                  KeyValueRow('إكرامية (لك كاملة)', formatMoney(bill.tip)),
                KeyValueRow('تم تحصيله', formatMoney(bill.collected)),
                KeyValueRow('المتبقي', formatMoney(bill.remaining)),
                const Divider(color: TamreedyColors.border),
                KeyValueRow(
                  'نصيبك من هذه الزيارة',
                  formatMoney(bill.nurseEarning + (kDemoMode ? bill.tip : 0)),
                ),
              ],
            ),
          ),
        if (bill != null && !paid) CollectionCard(c: c),
        if (c.collectMsg != null)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            width: double.infinity,
            decoration: BoxDecoration(
              color: c.collectShort
                  ? TamreedyColors.dangerTint
                  : const Color(0xFFDDF3EE),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              c.collectMsg!,
              style: tamText(
                size: 13,
                weight: FontWeight.w700,
                color: c.collectShort
                    ? TamreedyColors.danger
                    : TamreedyColors.success,
              ),
            ),
          ),
        const SectionTitle('الخطوة التالية'),
        PrimaryButton(
          paid ? 'العودة إلى شاشة متاح' : 'العودة إلى شاشة متاح (تحصيل لاحق)',
          onPressed: c.backToAvailable,
        ),
        SoftButton(
          'تقييم المريض وتقرير ما بعد الزيارة',
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => ReportScreen(c: c))),
        ),
      ],
    );
  }
}

/// Amount-received entry. Short amounts are rejected as "incomplete" and the remainder stays due.
class CollectionCard extends StatefulWidget {
  final NurseController c;
  const CollectionCard({super.key, required this.c});
  @override
  State<CollectionCard> createState() => _CollectionCardState();
}

class _CollectionCardState extends State<CollectionCard> {
  final _amount = TextEditingController();
  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return TamCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'المبلغ المستلم نقدًا',
            style: tamText(
              size: 15,
              weight: FontWeight.w800,
              color: TamreedyColors.navy,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              border: Border.all(color: TamreedyColors.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              textDirection: TextDirection.ltr,
              style: tamText(size: 20, weight: FontWeight.w800),
              decoration: InputDecoration(
                hintText: 'أدخل المبلغ',
                hintStyle: tamText(size: 14, color: TamreedyColors.subtext),
              ),
            ),
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            'تسجيل المبلغ المستلم',
            onPressed: c.busy
                ? null
                : () {
                    final v = int.tryParse(_amount.text.trim());
                    if (v == null || v <= 0) return;
                    c.collect(v);
                    _amount.clear();
                  },
          ),
        ],
      ),
    );
  }
}

/// N02 — incoming offer with countdown.
class OfferScreen extends StatefulWidget {
  final NurseController c;
  final TamBottomNav nav;
  const OfferScreen({super.key, required this.c, required this.nav});
  @override
  State<OfferScreen> createState() => _OfferScreenState();
}

class _OfferScreenState extends State<OfferScreen> {
  Timer? _t;
  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (widget.c.offer != null &&
          widget.c.offer!.expiresAt.isBefore(DateTime.now())) {
        widget.c.decline(expired: true);
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.c.offer;
    if (o == null) return const SizedBox.shrink();
    final left = o.expiresAt.difference(DateTime.now());
    return TamScaffold(
      title: 'طلب جديد قريب منك',
      subtitle: 'راجع تفاصيل الزيارة قبل القبول',
      nav: widget.nav,
      actions: Row(
        children: [
          Expanded(
            flex: 2,
            child: PrimaryButton(
              'قبول الطلب',
              onPressed: widget.c.busy || left <= Duration.zero
                  ? null
                  : widget.c.accept,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SoftButton(
              'رفض الطلب',
              onPressed: widget.c.busy ? null : widget.c.decline,
            ),
          ),
        ],
      ),
      children: [
        HeroCard(
          caption: 'الوقت المتبقي للقبول',
          title: o.service,
          trailing: Text(
            formatCountdown(left),
            textDirection: TextDirection.ltr,
            style: tamText(size: 26, weight: FontWeight.w800, color: Colors.white),
          ),
        ),
        TamCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListRow(
                icon: Icons.location_on_outlined,
                title: o.area,
                subtitle: '${o.km} كم تقريبًا',
              ),
              KeyValueRow('سعر الزيارة', formatMoney(o.price)),
              KeyValueRow('حصتك من الزيارة', formatMoney(o.nurseShare)),
            ],
          ),
        ),
        if (widget.c.error != null)
          NoticeBox(widget.c.error!),
      ],
    );
  }
}

/// N08 — post-visit internal report.
class ReportScreen extends StatefulWidget {
  final NurseController c;
  const ReportScreen({super.key, required this.c});
  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  int _stars = 5;
  final _note = TextEditingController();
  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TamScaffold(
    title: 'تقرير ما بعد الزيارة',
    subtitle: 'توثيق تجربة العمل بشكل مهني',
    showBack: true,
    nav: nurseNavBar(context, widget.c, 1),
    children: [
      TamCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'كيف جرت الزيارة؟',
              style: tamText(
                size: 22,
                weight: FontWeight.w800,
                color: TamreedyColors.navy,
              ),
            ),
            const SizedBox(height: 8),
            const ListRow(
              icon: Icons.location_on_outlined,
              title: 'العنوان صحيح',
              subtitle: 'تأكيد دقة موقع الزيارة',
              trailing: StatusChip('نعم'),
            ),
            const ListRow(
              icon: Icons.schedule,
              title: 'جاهزية المستفيد',
              subtitle: 'جاهز عند الوصول',
              trailing: StatusChip('نعم'),
            ),
            const ListRow(
              icon: Icons.payments_outlined,
              title: 'حالة الدفع',
              subtitle: 'مسجلة ومؤكدة',
              trailing: StatusChip('تم'),
            ),
            const ListRow(
              icon: Icons.warning_amber,
              title: 'بلاغ سلامة',
              subtitle: 'يذهب مباشرة للإشراف',
              trailing: StatusChip('لا يوجد'),
              divider: false,
            ),
          ],
        ),
      ),
      TamCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'قيّم المريض',
              style: tamText(
                size: 15,
                weight: FontWeight.w800,
                color: TamreedyColors.navy,
              ),
            ),
            Row(
              children: [
                for (var i = 1; i <= 5; i++)
                  IconButton(
                    onPressed: () => setState(() => _stars = i),
                    icon: Icon(
                      Icons.star,
                      size: 30,
                      color: i <= _stars
                          ? const Color(0xFFF2B01E)
                          : TamreedyColors.border,
                    ),
                  ),
              ],
            ),
            Text(
              'تقييمك يساعد في حماية الكوادر ولا يظهر للمريض.',
              style: tamText(size: 11.5, color: TamreedyColors.subtext),
            ),
          ],
        ),
      ),
      TamCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: TextField(
          controller: _note,
          maxLines: 3,
          style: tamText(size: 13),
          decoration: InputDecoration(
            hintText: 'ملاحظات مهنية داخلية...',
            hintStyle: tamText(size: 13, color: TamreedyColors.subtext),
          ),
        ),
      ),
      PrimaryButton(
        'حفظ تقرير الزيارة',
        onPressed: () {
          widget.c.submitReport(_stars, _note.text.trim());
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم حفظ التقرير (داخلي وغير علني)')),
          );
          Navigator.of(context).maybePop();
        },
      ),
    ],
  );
}
