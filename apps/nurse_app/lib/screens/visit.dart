import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import 'package:url_launcher/url_launcher.dart';
import '../alarm.dart';
import '../controller.dart';
import '../main.dart';
import 'chat.dart';
import 'clinical_notes.dart';
import 'service_outcomes.dart';

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
      case NurseStage.assigned:
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
    final assigned = c.stage == NurseStage.assigned;
    final arrived = c.stage == NurseStage.arrived;
    final destination = c.dest;
    return TamScaffold(
      title: arrived ? 'وصلت إلى الموقع' : assigned ? 'تم إسناد الزيارة' : 'في الطريق إلى المريض',
      subtitle: assigned ? 'أكّد الانطلاق عندما تبدأ التوجه' : 'موقع الزيارة المؤكد',
      nav: nav,
      children: [
        TamStepper(
          steps: const ['تم الإسناد', 'في الطريق', 'وصلت للموقع', 'بدء الخدمة'],
          currentStep: assigned ? 0 : arrived ? 2 : 1,
        ),
        const SizedBox(height: TamSpacing.md),
        if (destination != null) TamMap(
          height: 300,
          patient: destination,
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
              KeyValueRow('الحالة', arrived ? 'وصل' : assigned ? 'بانتظار الانطلاق' : 'في الطريق'),
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
          onPressed: destination == null ? null : () => launchUrl(
            Uri.parse(
              'https://www.google.com/maps/dir/?api=1&travelmode=driving&destination=${destination.latitude},${destination.longitude}',
            ),
            mode: LaunchMode.externalApplication,
          ),
        ),
        Row(
          children: [
            Expanded(
              child: SoftButton(
                'محادثة',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => NurseChatScreen(
                      c: c,
                      requestId: c.requestId ?? '',
                      patientName: 'المريض',
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SoftButton(
                'اتصال عبر التطبيق',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TamInAppCallScreen(
                      api: c.api,
                      requestId: c.requestId ?? '',
                      peerName: 'المريض',
                      peerRole: 'المريض / المستفيد',
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (assigned)
          PrimaryButton('بدأت التوجه إلى المريض', onPressed: c.busy ? null : c.depart)
        else if (!arrived) ...[
          SoftButton('وصلت إلى الموقع', onPressed: c.busy ? null : () => c.arrive()),
          if (c.arrivalOverrideAvailable)
            SoftButton('توثيق استثناء الموقع', onPressed: c.busy ? null : () => _arrivalOverride(context)),
        ]
        else
          PrimaryButton('بدء الزيارة', onPressed: c.start),
      ],
    );
  }

  Future<void> _arrivalOverride(BuildContext context) async {
    var reason='';
    final result=await showDialog<String>(
      context:context,
      builder:(dialogContext)=>StatefulBuilder(builder:(dialogContext,update)=>AlertDialog(
        title:const Text('سبب تعذر التحقق من الموقع'),
        content:TextField(maxLength:500,maxLines:3,onChanged:(value)=>update(()=>reason=value.trim())),
        actions:[
          TextButton(onPressed:()=>Navigator.of(dialogContext).pop(),child:const Text('إلغاء')),
          TextButton(onPressed:reason.length<5 ? null : ()=>Navigator.of(dialogContext).pop(reason),
            child:const Text('حفظ السبب')),
        ],
      )),
    );
    if (result!=null && context.mounted) await c.arrive(overrideReason:result);
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
      const SectionTitle('التوثيق السريري والملاحظات'),
      PrimaryButton(
        'توثيق العلامات الحيوية والملاحظات السريرية',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => NurseClinicalNotesScreen(
              c: c,
              requestId: c.requestId ?? '',
              patientName: 'المريض',
            ),
          ),
        ),
      ),
      const SectionTitle('بعد انتهاء الزيارة'),
      PrimaryButton(
        'توثيق نتائج الخدمات وإنهاء الزيارة',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ServiceOutcomesScreen(c: c)),
        ),
      ),
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
                Divider(color: context.tamColors.border),
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
                  ? context.tamColors.dangerTint
                  : context.tamColors.successTint,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              c.collectMsg!,
              style: tamText(
                size: 13,
                weight: FontWeight.w700,
                color: c.collectShort
                    ? context.tamColors.danger
                    : context.tamColors.success,
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
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    final v = int.tryParse(_amount.text.trim());
    if (v == null || v <= 0) {
      setState(() => _error = 'أدخل مبلغاً نقدياً صحيحاً أكبر من 0');
      return;
    }
    setState(() => _error = null);
    widget.c.collect(v);
    _amount.clear();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final tc = context.tamColors;
    final remaining = c.bill?.remaining ?? 0;
    return TamCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'المبلغ المستلم نقدًا',
            style: tamText(
              size: 15,
              weight: FontWeight.w800,
              color: tc.textPrimary,
            ),
          ),
          if (remaining > 0) ...[
            const SizedBox(height: TamSpacing.sm),
            Wrap(
              spacing: 8,
              children: [
                ActionChip(
                  avatar: Icon(Icons.bolt_rounded, size: 16, color: tc.primary),
                  label: Text(
                    'تعبئة كامل المتبقي (${formatMoney(remaining)})',
                    style: aeroText(size: 12, weight: FontWeight.w700, color: tc.primaryDark),
                  ),
                  backgroundColor: tc.primaryTint,
                  onPressed: () {
                    setState(() {
                      _amount.text = '$remaining';
                      _error = null;
                    });
                  },
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          TamTextField(
            controller: _amount,
            hint: 'أدخل المبلغ بالليرة السورية',
            errorText: _error,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            textDirection: TextDirection.ltr,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) {
              if (!c.busy) _submit();
            },
          ),
          const SizedBox(height: 12),
          AeroButton.teal(
            'تسجيل المبلغ المستلم',
            isLoading: c.busy,
            onPressed: c.busy ? null : _submit,
          ),
        ],
      ),
    );
  }
}

/// N02 — Full-Screen Deep Navy Offer (#102F49) with glowing aura & insistent alarm.
class OfferScreen extends StatefulWidget {
  final NurseController c;
  final TamBottomNav nav;
  const OfferScreen({super.key, required this.c, required this.nav});
  @override
  State<OfferScreen> createState() => _OfferScreenState();
}

class _OfferScreenState extends State<OfferScreen> with SingleTickerProviderStateMixin {
  Timer? _t;
  bool _muted = false;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

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
    _pulseController.dispose();
    super.dispose();
  }

  void _muteAlarm() {
    OfferAlarm.cancelAll();
    setState(() => _muted = true);
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.c.offer;
    if (o == null) return const SizedBox.shrink();
    final left = o.expiresAt.difference(DateTime.now());
    final secondsLeft = left.inSeconds.clamp(0, 60);

    return Scaffold(
      backgroundColor: AeroColors.deepNavyOffer,
      body: Stack(
        children: [
          // Ambient teal glowing aura in the center
          Positioned(
            top: 140,
            left: 0,
            right: 0,
            child: Center(
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, _) => Container(
                  width: 260 + (_pulseController.value * 40),
                  height: 260 + (_pulseController.value * 40),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AeroColors.accentTeal.withValues(alpha: 0.18 + (_pulseController.value * 0.14)),
                        blurRadius: 60,
                        spreadRadius: 10,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Top bar: Dispatch title + Mute button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AeroRadii.dock),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFF34D399),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'عرض زيارة جديد',
                              style: aeroText(size: 13, weight: FontWeight.w700, color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: _muted ? 'تم كتم التنبيه' : 'كتم الصوت',
                        onPressed: _muteAlarm,
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                            color: _muted ? Colors.white60 : Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const Spacer(flex: 1),

                  // Countdown circle & countdown timer
                  Center(
                    child: Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.08),
                        border: Border.all(
                          color: AeroColors.accentTeal,
                          width: 3,
                        ),
                        boxShadow: AeroShadows.deepNavyHalo,
                      ),
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$secondsLeft',
                            style: aeroText(
                              size: 32,
                              weight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'ثانية',
                            style: aeroText(
                              size: 11,
                              weight: FontWeight.w600,
                              color: AeroColors.accentTeal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Offer details card (frosted dark card)
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(AeroRadii.heroCard),
                      border: Border.all(
                        color: AeroColors.accentTeal.withValues(alpha: 0.4),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          o.service,
                          style: aeroText(
                            size: 20,
                            weight: FontWeight.w800,
                            color: Colors.white,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Icon(Icons.location_on_rounded, color: AeroColors.accentTeal, size: 16),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '${o.area} • ${o.km} كم',
                                style: aeroText(size: 13, weight: FontWeight.w600, color: Colors.white),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Container(height: 1, color: Colors.white.withValues(alpha: 0.12)),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'سعر الزيارة:',
                                style: aeroText(size: 13, color: Colors.white70),
                              ),
                            ),
                            Text(
                              formatMoney(o.price),
                              style: aeroText(size: 14, weight: FontWeight.w700, color: Colors.white),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'صافي حصتك:',
                                style: aeroText(size: 14, weight: FontWeight.w700, color: Colors.white),
                              ),
                            ),
                            Text(
                              formatMoney(o.nurseShare),
                              style: aeroText(
                                size: 18,
                                weight: FontWeight.w900,
                                color: const Color(0xFF2DD4BF),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  if (widget.c.offerCommitment != null)
                  FutureBuilder(
                    future: widget.c.offerCommitment,
                    builder: (context, snapshot) {
                      final summary = snapshot.data;
                      if (summary == null) return const SizedBox.shrink();
                      final text = summary['sufficient'] == true
                          ? 'آخر ${summary['lookbackDays']} يومًا: ${summary['assignedVisits']} زيارة مسندة، ${summary['countedCancellations']} إلغاء محتسب بعد الانطلاق. تستثنى الحالات المعذورة.'
                          : 'لا توجد بيانات كافية عن سجل الالتزام';
                      return Text(text, style: tamText(size: 12, color: Colors.white70));
                    },
                  ),
                if (widget.c.error != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        widget.c.error!,
                        style: aeroText(size: 12.5, color: Colors.red[200]!),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],

                  const Spacer(flex: 2),

                  // Actions: Large Teal Accept + Ghost Decline
                  AeroButton.teal(
                    'قبول الطلب',
                    onPressed: widget.c.busy || left <= Duration.zero
                        ? null
                        : () {
                            OfferAlarm.cancelAll();
                            widget.c.accept();
                          },
                    height: 54,
                    fontSize: 17,
                    leadingIcon: const Icon(Icons.check_circle_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(height: 8),
                  AeroButton.ghost(
                    'رفض الطلب',
                    onPressed: widget.c.busy
                        ? null
                        : () {
                            OfferAlarm.cancelAll();
                            widget.c.decline();
                          },
                    height: 48,
                    fontSize: 15,
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
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
