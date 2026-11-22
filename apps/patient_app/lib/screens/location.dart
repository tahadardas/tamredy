import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../controller.dart';
import '../main.dart';

/// Used only if the server list cannot be loaded, so the patient is never stuck.
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
  const LocationScreen({super.key, required this.c});
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

  @override
  void initState() {
    super.initState();
    c.error = null; // an unrelated earlier error must not show here
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    var list = <_Area>[];
    try {
      final d = await c.api.getMap('/v1/catalog/regions');
      for (final g in d['governorates'] as List) {
        for (final a in (g['areas'] as List)) {
          list.add(_Area(g['name'] as String, a['name'] as String, (a['lat'] as num?)?.toDouble(), (a['lng'] as num?)?.toDouble()));
        }
      }
    } catch (_) {
      list = [for (final f in _fallback) _Area(f['g']! as String, f['n']! as String, f['lat']! as double, f['lng']! as double)];
    }
    if (!mounted) return;
    setState(() {
      _areas = list;
      _govs = {for (final a in list) a.gov}.toList();
      _loading = false;
    });
  }

  void _pickArea(_Area a) {
    final hasCoordinates = a.lat != null && a.lng != null;
    final point = hasCoordinates ? LatLng(a.lat!, a.lng!) : kDamascus;
    c.selectVisitLocation(
      point,
      hasCoordinates ? '${a.name}، ${a.gov}' : 'حدّد موقع الزيارة على الخريطة',
    );
    setState(() {
      _mapStart = point;
      _needsMapSelection = !hasCoordinates;
      _onMap = true;
    });
  }

  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    c.error = null;
    await c.useCurrentLocation();
    if (!mounted) return;
    setState(() => _locating = false);
    if (c.position != null && c.error == null) {
      setState(() {
        _mapStart = c.position;
        _needsMapSelection = false;
        _onMap = true;
      });
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
        if (!_loading && shown.isEmpty)
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
                Expanded(child: Text(c.address, style: tamText(size: 19, weight: FontWeight.w800, color: TamreedyColors.navy))),
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
          c.setPicked(point, address);
        },
      ),
      const SizedBox(height: 10),
      TamCard(
        child: TextField(
          onChanged: (v) => c.extraAddress = v,
          style: tamText(size: 16),
          decoration: InputDecoration(
            labelText: 'رقم البناء أو الطابق أو أقرب معلم (اختياري)',
            labelStyle: tamText(size: 13),
            border: InputBorder.none,
          ),
        ),
      ),
      if (c.error != null)
        Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(c.error!, style: tamText(size: 14, color: TamreedyColors.danger))),
      _bigButton('هذا بيتي — أرسل الطلب', Icons.check_circle_outline, c.busy || _needsMapSelection
          ? null
          : () async {
              final nav = Navigator.of(context);
              final ok = await c.submit();
              if (ok && mounted) {
                c.setTab(1);
                nav.popUntil((r) => r.isFirst);
              }
            }),
    ],
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) => TamScaffold(
      title: _onMap ? 'ثبّت مكان بيتك' : 'أين تريد الزيارة؟',
      subtitle: _onMap ? 'خطوة أخيرة قبل إرسال الطلب' : 'اختر موقعك الحالي أو منطقتك',
      showBack: true,
      nav: patientNavBar(context, c, 0),
      children: [_onMap ? _mapStep() : _chooseStep()],
    ),
  );
}
