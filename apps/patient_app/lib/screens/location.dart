import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../controller.dart';
import '../main.dart';
import 'saved_places.dart';

/// Sample areas used by the local demo.
const _fallback = [
  {'g': 'دمشق', 'n': 'المزة', 'lat': 33.5000, 'lng': 36.2500},
  {'g': 'دمشق', 'n': 'المالكي', 'lat': 33.5200, 'lng': 36.2800},
  {'g': 'دمشق', 'n': 'كفرسوسة', 'lat': 33.4930, 'lng': 36.2760},
  {'g': 'دمشق', 'n': 'القصاع', 'lat': 33.5240, 'lng': 36.3180},
  {'g': 'دمشق', 'n': 'الميدان', 'lat': 33.4900, 'lng': 36.2950},
  {'g': 'ريف دمشق', 'n': 'جرمانا', 'lat': 33.4750, 'lng': 36.3500},
];

/// P03 — choose where the visit happens. Designed for elderly users:
/// one big "my location" button, or type a few letters of the area name and tap it; then drag the map
/// until the pin is on the building. Large text, one decision per step.
class LocationScreen extends StatefulWidget {
  final PatientController c;
  final bool addressOnly;
  const LocationScreen({super.key, required this.c, this.addressOnly = false});
  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _Area {
  final String gov, name;
  final double? lat, lng;
  const _Area(this.gov, this.name, this.lat, this.lng);
}

class _LocationScreenState extends State<LocationScreen> {
  PatientController get c => widget.c;
  List<_Area> _areas = [];
  List<String> _govs = [];
  String _gov = '', _query = '';
  bool _loading = true, _onMap = false, _locating = false;
  LatLng? _mapStart;
  bool _needsMapSelection = false;
  late LatLng? _point;
  late String _address;
  late double _accuracy;
  late String _details;
  bool _regionsUnavailable = false;
  DateTime? _appointment;

  @override
  void initState() {
    super.initState();
    c.error = null; // an unrelated earlier error must not show here
    _point = c.position;
    _address = c.address;
    _accuracy = c.accuracy;
    _details = c.extraAddress;
    _mapStart = _point;
    _onMap = _point != null;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    var list = <_Area>[];
    var unavailable = false;
    if (kDemoMode) {
      list = [
        for (final f in _fallback)
          _Area(f['g']! as String, f['n']! as String, f['lat']! as double, f['lng']! as double),
      ];
    } else {
      try {
        final d = await c.api.getMap('/v1/catalog/regions');
        for (final g in d['governorates'] as List) {
          for (final a in (g['areas'] as List)) {
            list.add(_Area(g['name'] as String, a['name'] as String, (a['lat'] as num?)?.toDouble(), (a['lng'] as num?)?.toDouble()));
          }
        }
      } catch (_) {
        unavailable = true;
      }
    }
    if (!mounted) return;
    setState(() {
      _regionsUnavailable = unavailable;
      _areas = list;
      _govs = {for (final a in list) a.gov}.toList();
      _loading = false;
    });
  }

  void _pickArea(_Area a) {
    final hasCoordinates = a.lat != null && a.lng != null;
    final point = hasCoordinates ? LatLng(a.lat!, a.lng!) : kDamascus;
    setState(() {
      _point = point;
      _address = hasCoordinates ? '${a.name}، ${a.gov}' : 'حدّد موقع الزيارة على الخريطة';
      _accuracy = 0;
      _details = '';
      _mapStart = point;
      _needsMapSelection = !hasCoordinates;
      _onMap = true;
    });
  }

  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    c.error = null;
    await c.useCurrentLocation(onLocated: (point, label, accuracy) {
      if (!mounted) return;
      setState(() {
        _point = point;
        _address = label;
        _accuracy = accuracy;
        _details = '';
        _mapStart = point;
        _needsMapSelection = false;
        _onMap = true;
      });
    });
    if (mounted) setState(() => _locating = false);
  }

  void _useSavedPlace(SavedPlace place) {
    setState(() {
      _point = place.point;
      _mapStart = place.point;
      _address = place.address;
      _accuracy = place.accuracy;
      _details = place.details;
      _needsMapSelection = false;
      _onMap = true;
    });
  }

  Future<void> _savePlace() async {
    final point = _point;
    if (point == null) return;
    final saved = await editSavedPlace(context, c.api, SavedPlace({
      'label': '',
      'formatted_address': _address,
      'latitude': point.latitude,
      'longitude': point.longitude,
      'accuracy': _accuracy,
      'notes': _details,
    }));
    if (saved && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ المكان')));
    }
  }

  Widget _bigButton(String label, IconData icon, VoidCallback? onTap) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Material(
      color: TamreedyColors.teal,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 30),
              const SizedBox(width: 12),
              Flexible(child: Text(label, style: tamText(size: 20, weight: FontWeight.w800, color: Colors.white))),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _chooseStep() {
    final q = _query.trim();
    final shown = _areas.where((a) => (_gov.isEmpty || a.gov == _gov) && (q.isEmpty || a.name.contains(q))).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _bigButton(
          _locating ? 'جارٍ تحديد موقعك...' : 'استخدم موقعي الحالي',
          Icons.my_location,
          _locating ? null : _useMyLocation,
        ),
        if (c.error != null)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: TamreedyColors.dangerTint,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: TamreedyColors.danger.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.error_outline, color: TamreedyColors.danger, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        c.error!,
                        style: tamText(size: 14, color: TamreedyColors.danger, weight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                if (c.error!.contains('إعدادات')) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => c.openSettings(),
                    icon: const Icon(Icons.settings, size: 18, color: TamreedyColors.teal),
                    label: Text(
                      'فتح إعدادات التطبيق لتفعيل الإذن',
                      style: tamText(size: 14, color: TamreedyColors.teal, weight: FontWeight.w700),
                    ),
                  ),
                ],
              ],
            ),
          ),
        if (!kDemoMode) SavedPlaces(api: c.api, onSelected: _useSavedPlace),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text('أو اختر منطقتك', style: tamText(size: 20, weight: FontWeight.w800, color: TamreedyColors.navy)),
        ),
        TamCard(
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            style: tamText(size: 20, weight: FontWeight.w700),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search, size: 28),
              hintText: 'اكتب اسم منطقتك، مثل: المزة',
              hintStyle: tamText(size: 17, color: TamreedyColors.subtext),
              border: InputBorder.none,
            ),
          ),
        ),
        if (_govs.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Wrap(
              spacing: 10,
              children: [
                for (final g in ['', ..._govs])
                  ChoiceChip(
                    label: Text(g.isEmpty ? 'الكل' : g, style: tamText(size: 17, weight: FontWeight.w700)),
                    selected: _gov == g,
                    onSelected: (_) => setState(() => _gov = g),
                  ),
              ],
            ),
          ),
        if (_loading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
        if (!_loading && _regionsUnavailable) ...[
          const NoticeBox('تعذر تحميل المناطق. يمكنك تحديد العنوان مباشرة على الخريطة.'),
          TextButton(onPressed: _load, child: const Text('إعادة تحميل المناطق')),
        ],
        TextButton(
          onPressed: () => _pickArea(const _Area('', '', null, null)),
          child: const Text('تحديد عنوان على الخريطة'),
        ),
        if (!_loading && !_regionsUnavailable && shown.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('لا توجد منطقة بهذا الاسم. جرّب كتابة جزء من الاسم أو استخدم موقعك الحالي.', style: tamText(size: 17)),
          ),
        for (final a in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _pickArea(a),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                  decoration: BoxDecoration(border: Border.all(color: TamreedyColors.border), borderRadius: BorderRadius.circular(16)),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on, color: TamreedyColors.teal, size: 28),
                      const SizedBox(width: 12),
                      Expanded(child: Text(a.name, style: tamText(size: 21, weight: FontWeight.w800, color: TamreedyColors.navy))),
                      Text(a.gov, style: tamText(size: 15, color: TamreedyColors.subtext)),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Everything (map, note, confirm button) fits on one screen: a tall map would swallow the scroll gesture
  /// and an older user could never reach the send button.
  Future<void> _confirmAddress() async {
    final point = _point;
    if (point == null || _needsMapSelection || c.busy) return;
    final navigator = Navigator.of(context);
    c.selectVisitLocation(point, _address, accuracyMeters: _accuracy, addressDetails: _details);
    if (widget.addressOnly) {
      navigator.pop();
      return;
    }
    final service = c.service;
    if (service == null) return;
    if (!kDemoMode && c.selectedBeneficiaryId == null) await c.loadBeneficiary();
    if (!mounted || c.busy) return;
    Map<String, dynamic> scheduling = {};
    if (!kDemoMode) {
      try {
        scheduling = await c.api.getMap('/v1/requests/scheduling');
      } catch (_) {
        // Immediate booking remains available when capability lookup fails.
      }
    }
    if (!mounted) return;
    DateTime? appointment = _appointment;
    final estimate = c.est ?? estimatePrice(service.rule);
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => StatefulBuilder(builder: (context, update) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionTitle('مراجعة طلب الزيارة'),
              if (scheduling['enabled'] == true) ...[
                KeyValueRow('موعد الزيارة', appointment == null ? 'الآن' :
                  '${MaterialLocalizations.of(context).formatMediumDate(appointment!)} • ${TimeOfDay.fromDateTime(appointment!).format(context)}'),
                OutlinedButton(
                  onPressed: () async {
                    final now = DateTime.now();
                    final day = await showDatePicker(context: context, firstDate: now, lastDate: now.add(const Duration(days: 30)));
                    if (day == null || !context.mounted) return;
                    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))));
                    if (time == null || !context.mounted) return;
                    final chosen = DateTime(day.year, day.month, day.day, time.hour, time.minute);
                    if (chosen.isBefore(DateTime.now().add(const Duration(minutes: 30))) ||
                        chosen.isAfter(DateTime.now().add(const Duration(days: 30)))) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اختر موعدًا بعد 30 دقيقة وحتى 30 يومًا.')));
                      return;
                    }
                    update(() => appointment = chosen);
                  },
                  child: const Text('تحديد موعد'),
                ),
                if (appointment != null)
                  TextButton(onPressed: () => update(() => appointment = null), child: const Text('طلب الزيارة الآن')),
              ],
              KeyValueRow('الخدمة', service.title),
              KeyValueRow('المستفيد', c.beneficiary.isEmpty ? 'غير محدد' : c.beneficiary),
              KeyValueRow('عنوان الزيارة', c.visitAddress),
              KeyValueRow('السعر الأساسي', formatMoney(service.rule.basePrice)),
              KeyValueRow('الإجمالي التقديري', formatMoney(estimate.expected)),
              KeyValueRow('مدة الزيارة التقديرية', '${service.expectedMinutes} دقيقة'),
              if ((num.tryParse('${c.quoteInfo['surchargePercent']}') ?? 0) > 0)
                KeyValueRow('رسم الوقت', '+${c.quoteInfo['surchargePercent']}%'),
              if ((num.tryParse('${c.quoteInfo['taxPercent']}') ?? 0) > 0)
                KeyValueRow('الضريبة', '${c.quoteInfo['taxPercent']}%'),
              if (c.promoCode.isNotEmpty) KeyValueRow('كود الخصم', c.promoCode),
              KeyValueRow('طريقة الدفع', !kDemoMode || c.payMethod == 'cash' ? 'نقدًا للممرض' : 'المحفظة التجريبية'),
              if (service.requiresPrescription) const NoticeBox('تتطلب الخدمة وصفة طبية.'),
              const NoticeBox('يُحسب المبلغ النهائي وفق مدة الزيارة والرسوم المطبقة.'),
              PrimaryButton('تأكيد وإرسال الطلب', onPressed: () => Navigator.pop(context, true)),
            ],
          ),
        ),
      ),
    ));
    if (confirmed != true || !mounted) return;
    _appointment = appointment;
    if (await c.submit(appointment: appointment) && mounted) {
      c.setTab(1);
      navigator.popUntil((route) => route.isFirst);
    }
  }

  Widget _mapStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TamCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.location_on, color: TamreedyColors.teal, size: 28),
                const SizedBox(width: 8),
                Expanded(child: Text(_address, style: tamText(size: 19, weight: FontWeight.w800, color: TamreedyColors.navy))),
                TextButton(
                  onPressed: () => setState(() => _onMap = false),
                  child: Text('تغيير', style: tamText(size: 16, weight: FontWeight.w800, color: TamreedyColors.teal)),
                ),
              ],
            ),
            Text('حرّك الخريطة حتى يصبح الدبوس فوق بيتك تمامًا', style: tamText(size: 15, weight: FontWeight.w700)),
          ],
        ),
      ),
      TamLocationPicker(
        initial: _mapStart!,
        height: 250,
        onChanged: (point, address) {
          if (c.busy || (_needsMapSelection && point == _mapStart)) return;
          _needsMapSelection = false;
          setState(() {
            if (_point != point) {
              _point = point;
              _address = 'الموقع المحدد على الخريطة';
              _accuracy = 0;
            }
            if (address.isNotEmpty) _address = address;
          });
        },
      ),
      const SizedBox(height: 10),
      TamCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              key: ValueKey(_details),
              initialValue: _details,
              textInputAction: TextInputAction.done,
              onChanged: (v) => _details = v,
              style: tamText(
                size: 16,
                color: context.tamColors.textPrimary,
              ),
              decoration: InputDecoration(
                labelText: 'رقم البناء أو الطابق أو أقرب معلم (اختياري)',
                labelStyle: tamText(size: 13, color: context.tamColors.textSecondary),
                border: InputBorder.none,
              ),
            ),
            const SizedBox(height: TamSpacing.sm),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tag in const ['طابق أرضي', 'طابق 1', 'طابق 2', 'يوجد مصعد', 'قرب صيدلية'])
                  ActionChip(
                    label: Text(tag, style: aeroText(size: 11.5, color: context.tamColors.textPrimary)),
                    onPressed: () {
                      setState(() {
                        _details = _details.trim().isEmpty ? tag : '${_details.trim()} • $tag';
                      });
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
      if (c.error != null)
        Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(c.error!, style: tamText(size: 14, color: TamreedyColors.danger))),
      if (!kDemoMode)
        OutlinedButton.icon(
          onPressed: c.busy || _needsMapSelection || _point == null ? null : _savePlace,
          icon: const Icon(Icons.bookmark_add_outlined),
          label: const Text('حفظ ضمن أماكني'),
        ),
      _bigButton(
        widget.addressOnly ? 'تأكيد عنوان الزيارة' : 'مراجعة الطلب',
        Icons.check_circle_outline,
        c.busy || _needsMapSelection || _point == null ? null : _confirmAddress,
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) => TamScaffold(
      title: _onMap ? 'ثبّت مكان بيتك' : 'أين تريد الزيارة؟',
      subtitle: _onMap ? 'تأكد من موضع دبوس الزيارة' : 'اختر موقعك الحالي أو منطقتك',
      showBack: true,
      nav: widget.addressOnly ? null : patientNavBar(context, c, 0),
      children: [
        if (!widget.addressOnly) ...[
          const TamStepper(
            steps: ['الخدمة والمتطلبات', 'تحديد الموقع', 'مراجعة وتأكيد'],
            currentStep: 1,
          ),
          const SizedBox(height: TamSpacing.lg),
        ],
        _onMap ? _mapStep() : _chooseStep(),
      ],
    ),
  );
}
