import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../../app/patient_router.dart';
import '../../core/patient_session_coordinator.dart';
import 'booking_draft_store.dart';

class BookingWizardScreen extends StatefulWidget {
  final PatientSessionCoordinator session;

  const BookingWizardScreen({super.key, required this.session});

  @override
  State<BookingWizardScreen> createState() => _BookingWizardScreenState();
}

class _BookingWizardScreenState extends State<BookingWizardScreen> {
  int _step = 0; // 0: Services, 1: Beneficiary & Location, 2: Mode & Time, 3: Review & Confirm
  late final TextEditingController _detailsCtrl;
  late final TextEditingController _promoCtrl;

  BookingDraftStore get draft => widget.session.bookingDraft;

  @override
  void initState() {
    super.initState();
    _detailsCtrl = TextEditingController(text: draft.addressDetails);
    _promoCtrl = TextEditingController(text: draft.promoCode);
    draft.loadPrerequisites();
    if (draft.serviceQuantities.isNotEmpty) {
      _step = 1;
    }
  }

  @override
  void dispose() {
    _detailsCtrl.dispose();
    _promoCtrl.dispose();
    super.dispose();
  }

  bool get _canProceed {
    switch (_step) {
      case 0:
        return draft.serviceQuantities.isNotEmpty;
      case 1:
        return draft.locationPoint != null && draft.selectedBeneficiary != null;
      case 2:
        if (draft.bookingMode == 'SCHEDULED') return draft.scheduledAt != null;
        return true;
      default:
        return draft.serviceQuantities.isNotEmpty && draft.locationPoint != null;
    }
  }

  Future<void> _submitOrder() async {
    final created = await draft.submit();
    if (!mounted) return;
    if (created == null) {
      TamToast.show(
        context,
        draft.submitError ?? 'تعذر إرسال الطلب',
        tone: TamToastTone.error,
      );
      return;
    }
    widget.session.requests.registerCreatedRequest(created);
    Navigator.of(context).pop();
    await PatientRouter.openRequestSmart(context, widget.session, created);
  }

  Future<void> _pickClinicalFile(String evidenceType) async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
      );
      if (file == null) return;
      final length = await file.length();
      if (length == null || length == 0 || length > 8 * 1024 * 1024) {
        if (mounted) {
          TamToast.show(
            context,
            'يرجى اختيار صورة أو ملف PDF بحجم لا يتجاوز 8 ميغابايت',
            tone: TamToastTone.warning,
          );
        }
        return;
      }
      final bytes = await file.readAsBytes();
      draft.setStagedEvidence(
        StagedEvidence(
          evidenceType: evidenceType,
          filename: file.name,
          bytes: bytes,
        ),
      );
    } catch (_) {
      if (mounted) {
        TamToast.show(context, 'تعذر قراءة الملف المختار', tone: TamToastTone.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: ListenableBuilder(
        listenable: Listenable.merge([draft, widget.session.catalog]),
        builder: (context, _) {
          return Scaffold(
            backgroundColor: tc.background,
            appBar: AppBar(
              backgroundColor: tc.surface,
              elevation: 0,
              title: Text(
                'حجز زيارة تمريضية',
                style: aeroText(size: 16, weight: FontWeight.w800, color: tc.textPrimary),
              ),
              leading: IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: draft.submitting ? null : () => Navigator.of(context).maybePop(),
              ),
            ),
            body: Column(
              children: [
                _StepIndicator(
                  step: _step,
                  onTapStep: (idx) {
                    if (idx < _step) setState(() => _step = idx);
                  },
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: TamBreakpoints.maxContentWidth),
                        child: switch (_step) {
                          0 => _StepServices(session: widget.session),
                          1 => _StepLocationBeneficiary(
                              draft: draft,
                              detailsCtrl: _detailsCtrl,
                              onAddBeneficiary: () => _showAddBeneficiaryDialog(context),
                            ),
                          2 => _StepModeSchedule(
                              draft: draft,
                              onPickDateTime: () => _pickScheduleDateTime(context),
                              onPickFile: _pickClinicalFile,
                            ),
                          _ => _StepReview(
                              draft: draft,
                              promoCtrl: _promoCtrl,
                            ),
                        },
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: tc.surface,
                      border: Border(top: BorderSide(color: tc.border)),
                    ),
                    child: Row(
                      children: [
                        if (_step > 0) ...[
                          OutlinedButton(
                            onPressed: draft.submitting ? null : () => setState(() => _step--),
                            child: const Text('السابق'),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: AeroButton(
                            _step < 3
                                ? 'التالي'
                                : (draft.submitting ? 'جارٍ إرسال الطلب...' : 'تأكيد وإرسال الطلب'),
                            isLoading: draft.submitting,
                            onPressed: (!_canProceed || draft.submitting)
                                ? null
                                : () {
                                    if (_step < 3) {
                                      setState(() => _step++);
                                    } else {
                                      _submitOrder();
                                    }
                                  },
                          ),
                        ),
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

  Future<void> _showAddBeneficiaryDialog(BuildContext context) async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    String relationship = 'PARENT';
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('إضافة مستفيد جديد'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'الاسم الكامل للمريض'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: relationship,
                  decoration: const InputDecoration(labelText: 'صلة القرابة'),
                  items: const [
                    DropdownMenuItem(value: 'SELF', child: Text('نفسي')),
                    DropdownMenuItem(value: 'PARENT', child: Text('الوالد / الوالدة')),
                    DropdownMenuItem(value: 'SPOUSE', child: Text('الزوج / الزوجة')),
                    DropdownMenuItem(value: 'CHILD', child: Text('الابن / الابنة')),
                    DropdownMenuItem(value: 'OTHER', child: Text('قريب آخر')),
                  ],
                  onChanged: (v) => setDialogState(() => relationship = v ?? 'OTHER'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'هاتف طوارئ (اختياري)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.of(ctx).pop(),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (nameCtrl.text.trim().length < 2) return;
                      setDialogState(() => saving = true);
                      try {
                        await draft.createBeneficiary(
                          displayName: nameCtrl.text,
                          relationship: relationship,
                          emergencyContactPhone: phoneCtrl.text,
                        );
                        if (ctx.mounted) Navigator.of(ctx).pop();
                      } catch (e) {
                        setDialogState(() => saving = false);
                        if (ctx.mounted) {
                          TamToast.show(ctx, explainError(e), tone: TamToastTone.error);
                        }
                      }
                    },
              child: Text(saving ? 'جارٍ الحفظ...' : 'حفظ المستفيد'),
            ),
          ],
        ),
      ),
    );
    nameCtrl.dispose();
    phoneCtrl.dispose();
  }

  Future<void> _pickScheduleDateTime(BuildContext context) async {
    final minHours = (num.tryParse('${draft.schedulingPolicy?['minLeadHours'] ?? 2}') ?? 2).toInt();
    final maxDays = (num.tryParse('${draft.schedulingPolicy?['maxHorizonDays'] ?? 30}') ?? 30).toInt();
    final now = DateTime.now();
    final earliest = now.add(Duration(hours: minHours));
    final pickedDate = await showDatePicker(
      context: context,
      firstDate: DateTime(earliest.year, earliest.month, earliest.day),
      lastDate: now.add(Duration(days: maxDays)),
      initialDate: draft.scheduledAt ?? earliest,
    );
    if (pickedDate == null || !context.mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(draft.scheduledAt ?? earliest),
    );
    if (pickedTime == null || !context.mounted) return;

    final combined = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
    if (combined.isBefore(earliest)) {
      TamToast.show(
        context,
        'يجب أن يكون الموعد بعد ساعتين على الأقل من الآن',
        tone: TamToastTone.warning,
      );
      return;
    }
    draft.setScheduledAt(combined);
  }
}

class _StepIndicator extends StatelessWidget {
  final int step;
  final ValueChanged<int> onTapStep;

  const _StepIndicator({required this.step, required this.onTapStep});

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    const labels = ['الخدمات', 'الموقع والمستفيد', 'الموعد والنوع', 'التأكيد'];
    return Container(
      color: tc.surface,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            Expanded(
              child: GestureDetector(
                onTap: () => onTapStep(i),
                child: Column(
                  children: [
                    Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: i <= step ? tc.primary : tc.border,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      labels[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: aeroText(
                        size: 11,
                        weight: i == step ? FontWeight.w800 : FontWeight.w600,
                        color: i <= step ? tc.primary : tc.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (i < labels.length - 1) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

class _StepServices extends StatelessWidget {
  final PatientSessionCoordinator session;
  const _StepServices({required this.session});

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    final draft = session.bookingDraft;
    final services = session.catalog.services;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'اختر الخدمات المطلوبة للزيارة',
          style: aeroText(size: 16, weight: FontWeight.w800, color: tc.textPrimary),
        ),
        const SizedBox(height: 4),
        Text(
          'يمكنك جمع أكثر من خدمة في زيارة واحدة برسوم انتقال واحدة.',
          style: aeroText(size: 12.5, color: tc.textSecondary),
        ),
        const SizedBox(height: 12),
        if (session.catalog.loading && services.isEmpty)
          const TamSkeleton.card(height: 120)
        else
          for (final svc in services)
            Builder(builder: (context) {
              final qty = draft.serviceQuantities[svc.id] ?? 0;
              return TamCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            svc.titleAr,
                            style: aeroText(size: 14.5, weight: FontWeight.w800, color: tc.textPrimary),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${formatMoney(svc.priceAmount)} • ${svc.expectedMinutes} د',
                            style: aeroText(size: 12.5, color: tc.primary, weight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                    if (qty == 0)
                      OutlinedButton(
                        onPressed: () => draft.setServiceQuantity(svc, 1),
                        child: const Text('إضافة'),
                      )
                    else
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: () => draft.setServiceQuantity(svc, qty - 1),
                            icon: Icon(Icons.remove_circle_outline, color: tc.primary),
                          ),
                          Text('$qty', style: aeroText(size: 15, weight: FontWeight.w800)),
                          IconButton(
                            onPressed: qty >= 10 ? null : () => draft.setServiceQuantity(svc, qty + 1),
                            icon: Icon(Icons.add_circle_outline, color: tc.primary),
                          ),
                        ],
                      ),
                  ],
                ),
              );
            }),
      ],
    );
  }
}

class _StepLocationBeneficiary extends StatelessWidget {
  final BookingDraftStore draft;
  final TextEditingController detailsCtrl;
  final VoidCallback onAddBeneficiary;

  const _StepLocationBeneficiary({
    required this.draft,
    required this.detailsCtrl,
    required this.onAddBeneficiary,
  });

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'المستفيد من الرعاية',
                style: aeroText(size: 15.5, weight: FontWeight.w800, color: tc.textPrimary),
              ),
            ),
            TextButton.icon(
              onPressed: onAddBeneficiary,
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
              label: const Text('إضافة مستفيد'),
            ),
          ],
        ),
        if (draft.loadingBeneficiaries && draft.beneficiaries.isEmpty)
          const TamSkeleton.card(height: 54)
        else if (draft.beneficiaries.isEmpty)
          TamCard(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'أضف ملف المستفيد للمتابعة',
                    style: aeroText(size: 13.5, color: tc.textSecondary),
                  ),
                ),
                ElevatedButton(onPressed: onAddBeneficiary, child: const Text('إضافة')),
              ],
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final b in draft.beneficiaries)
                ChoiceChip(
                  label: Text(b.displayName),
                  selected: draft.selectedBeneficiaryId == b.id,
                  onSelected: (_) => draft.selectBeneficiary(b.id),
                ),
            ],
          ),
        const SizedBox(height: 16),
        Text(
          'موقع الزيارة',
          style: aeroText(size: 15.5, weight: FontWeight.w800, color: tc.textPrimary),
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: tc.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: draft.locatingGps ? null : draft.captureGpsLocation,
          icon: const Icon(Icons.my_location_rounded),
          label: Text(draft.locatingGps ? 'جارٍ تحديد موقعك...' : 'استخدام موقعي الحالي (GPS)'),
        ),
        if (draft.locationError != null) ...[
          const SizedBox(height: 8),
          NoticeBox(draft.locationError!),
        ],
        if (draft.savedPlaces.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('الأماكن المحفوظة', style: aeroText(size: 13.5, weight: FontWeight.w700, color: tc.textSecondary)),
          const SizedBox(height: 6),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: draft.savedPlaces.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, idx) {
                final place = draft.savedPlaces[idx];
                return ActionChip(
                  avatar: Icon(Icons.bookmark_outline_rounded, size: 16, color: tc.primary),
                  label: Text(place.label),
                  onPressed: () {
                    draft.applySavedPlace(place);
                    detailsCtrl.text = draft.addressDetails;
                  },
                );
              },
            ),
          ),
        ],
        if (draft.regions.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('اختيار سريع للمنطقة', style: aeroText(size: 13.5, weight: FontWeight.w700, color: tc.textSecondary)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final r in draft.regions.take(10))
                ActionChip(
                  label: Text('${r.name}، ${r.governorate}', style: aeroText(size: 12)),
                  onPressed: () => draft.setMapPoint(
                    r.lat != null && r.lng != null ? LatLng(r.lat!, r.lng!) : kDamascus,
                    '${r.name}، ${r.governorate}',
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        TamLocationPicker(
          initial: draft.locationPoint ?? kDamascus,
          height: 220,
          onChanged: (pt, addr) => draft.setMapPoint(pt, addr),
        ),
        const SizedBox(height: 10),
        if (draft.addressLabel.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: KeyValueRow('الموقع المحدد', draft.addressLabel),
          ),
        TextField(
          controller: detailsCtrl,
          onChanged: draft.setAddressDetails,
          decoration: InputDecoration(
            labelText: 'تفاصيل العنوان (البناء، الطابق، أقرب معلم)',
            filled: true,
            fillColor: tc.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ],
    );
  }
}

class _StepModeSchedule extends StatelessWidget {
  final BookingDraftStore draft;
  final VoidCallback onPickDateTime;
  final ValueChanged<String> onPickFile;

  const _StepModeSchedule({
    required this.draft,
    required this.onPickDateTime,
    required this.onPickFile,
  });

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'اختر طريقة تنفيذ الطلب',
          style: aeroText(size: 15.5, weight: FontWeight.w800, color: tc.textPrimary),
        ),
        const SizedBox(height: 10),
        _ModeTile(
          selected: draft.bookingMode == 'INSTANT',
          icon: Icons.bolt_rounded,
          title: 'طلب فوري الآن',
          subtitle: 'يرسل النظام طلبك مباشرة لأقرب ممرض مؤهل ومتاح حالياً.',
          onTap: () => draft.setBookingMode('INSTANT'),
        ),
        _ModeTile(
          selected: draft.bookingMode == 'OPEN',
          icon: Icons.storefront_rounded,
          title: 'السوق المفتوح للعروض',
          subtitle: 'استقبل عروض الجاهزية من عدة ممرضين مع وقت الوصول المتوقع وقارن بينهم.',
          onTap: () => draft.setBookingMode('OPEN'),
        ),
        _ModeTile(
          selected: draft.bookingMode == 'SCHEDULED',
          icon: Icons.calendar_month_rounded,
          title: 'حجز موعد لاحق',
          subtitle: 'اختر التاريخ والساعة المناسبة للزيارة، وسنؤكد الممرض قبل الموعد.',
          onTap: () => draft.setBookingMode('SCHEDULED'),
        ),
        if (draft.bookingMode == 'OPEN') ...[
          const SizedBox(height: 8),
          TamCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('مدة استقبال العروض', style: aeroText(size: 13.5, weight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final m in const [30, 60, 90])
                      ChoiceChip(
                        label: Text('$m دقيقة'),
                        selected: draft.openDurationMinutes == m,
                        onSelected: (_) => draft.setOpenDurationMinutes(m),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
        if (draft.bookingMode == 'SCHEDULED') ...[
          const SizedBox(height: 8),
          TamCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  draft.scheduledAt == null
                      ? 'لم يتم تحديد الموعد بعد'
                      : 'الموعد: ${MaterialLocalizations.of(context).formatMediumDate(draft.scheduledAt!)} • ${TimeOfDay.fromDateTime(draft.scheduledAt!).format(context)}',
                  style: aeroText(size: 14, weight: FontWeight.w800, color: tc.primary),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: onPickDateTime,
                  icon: const Icon(Icons.edit_calendar_rounded),
                  label: Text(draft.scheduledAt == null ? 'اختيار التاريخ والساعة' : 'تغيير الموعد'),
                ),
              ],
            ),
          ),
        ],
        if (draft.requiresPrescription || draft.requiresClinicalReview) ...[
          const SizedBox(height: 12),
          TamCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.description_outlined, color: tc.warning),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'الوصفة أو التقرير الطبي',
                        style: aeroText(size: 14.5, weight: FontWeight.w800, color: tc.textPrimary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'تتطلب إحدى الخدمات وصفة طبية سارية. يمكنك إرفاقها الآن ليتم اعتمادها سريرياً بسرعة.',
                  style: aeroText(size: 12.5, color: tc.textSecondary, height: 1.45),
                ),
                const SizedBox(height: 10),
                if (draft.stagedEvidence != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: StatusChip('مرفق جاهز: ${draft.stagedEvidence!.filename}'),
                  ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => onPickFile('PRESCRIPTION'),
                      icon: const Icon(Icons.upload_file_rounded, size: 18),
                      label: const Text('إرفاق وصفة طبية'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => onPickFile('CLINICAL_REPORT'),
                      icon: const Icon(Icons.medical_information_outlined, size: 18),
                      label: const Text('إرفاق تقرير طبي'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ModeTile extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ModeTile({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: selected ? tc.primaryTint.withValues(alpha: tc.isDark ? 0.25 : 0.45) : tc.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: selected ? tc.primary : tc.border, width: selected ? 1.6 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, color: selected ? tc.primary : tc.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: aeroText(size: 14.5, weight: FontWeight.w800, color: tc.textPrimary)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: aeroText(size: 12, color: tc.textSecondary, height: 1.4)),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? tc.primary : tc.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepReview extends StatelessWidget {
  final BookingDraftStore draft;
  final TextEditingController promoCtrl;

  const _StepReview({required this.draft, required this.promoCtrl});

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    final est = draft.estimate;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TamCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ملخص الطلب', style: aeroText(size: 15.5, weight: FontWeight.w800, color: tc.textPrimary)),
              const SizedBox(height: 10),
              for (final s in draft.selectedServices)
                KeyValueRow(
                  '${s.titleAr} × ${draft.serviceQuantities[s.id] ?? 1}',
                  formatMoney(s.priceAmount * (draft.serviceQuantities[s.id] ?? 1)),
                ),
              const Divider(),
              KeyValueRow('المستفيد', draft.selectedBeneficiary?.displayName ?? 'غير محدد'),
              KeyValueRow('العنوان', draft.fullAddress),
              KeyValueRow(
                'نوع الطلب',
                switch (draft.bookingMode) {
                  'OPEN' => 'السوق المفتوح (${draft.openDurationMinutes} د)',
                  'SCHEDULED' => 'زيارة مجدولة',
                  _ => 'طلب فوري الآن',
                },
              ),
              if (draft.scheduledAt != null)
                KeyValueRow(
                  'الموعد',
                  '${MaterialLocalizations.of(context).formatMediumDate(draft.scheduledAt!)} • ${TimeOfDay.fromDateTime(draft.scheduledAt!).format(context)}',
                ),
              if (draft.estimateStatus == EstimateStatus.verified && est != null) ...[
                const Divider(),
                KeyValueRow('المدة التقديرية', '${est.totalExpectedMinutes} دقيقة'),
                KeyValueRow('الإجمالي التقديري المعتمد', formatMoney(est.expectedEstimate)),
                if (est.promoDiscount > 0)
                  KeyValueRow('الخصم', '−${formatMoney(est.promoDiscount)}'),
              ] else if (draft.estimateStatus == EstimateStatus.stale || draft.estimating) ...[
                const Divider(),
                Text(
                  'جاري التحقق من التسعير الرسمي...',
                  style: aeroText(size: 12.5, weight: FontWeight.w700, color: tc.textSecondary),
                ),
              ] else ...[
                const Divider(),
                KeyValueRow('مجموع الخدمات الأولي (غير معتمد)', formatMoney(draft.unverifiedLocalSubtotal)),
                const SizedBox(height: 4),
                Text(
                  'تعذر جلب التسعير الرسمي (الرسوم/الخصومات/المدة). أعد المحاولة لتأكيد السعر قبل الإرسال.',
                  style: aeroText(size: 12, color: tc.warning),
                ),
                TextButton(
                  onPressed: draft.estimating ? null : () => draft.refreshEstimate(immediate: true),
                  child: const Text('إعادة التحقق من السعر الرسمي'),
                ),
              ],
              const KeyValueRow('طريقة الدفع', 'نقداً للممرض عند إكمال الزيارة'),
            ],
          ),
        ),
        TamCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('رمز خصم (اختياري)', style: aeroText(size: 13.5, weight: FontWeight.w700)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: promoCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        hintText: 'أدخل الرمز الترويجي',
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => draft.applyPromo(promoCtrl.text),
                    child: const Text('تطبيق'),
                  ),
                ],
              ),
              if (draft.promoFeedback != null) ...[
                const SizedBox(height: 6),
                Text(draft.promoFeedback!, style: aeroText(size: 12, color: tc.primary)),
              ],
            ],
          ),
        ),
        const NoticeBox('تقر بأن الطلب غير طارئ طبياً وأن القيمة النهائية تُحسب حسب مدة الزيارة الفعلية.'),
      ],
    );
  }
}
