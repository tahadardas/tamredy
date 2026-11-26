import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../booking/booking_draft_store.dart';

class SavedPlacesScreen extends StatefulWidget {
  final TamreedyApi api;
  const SavedPlacesScreen({super.key, required this.api});

  @override
  State<SavedPlacesScreen> createState() => _SavedPlacesScreenState();
}

class _SavedPlacesScreenState extends State<SavedPlacesScreen> {
  List<SavedPlaceModel> _places = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await widget.api.getList('/v1/patient/saved-places');
      _places = [
        for (final r in raw)
          if (r is Map) SavedPlaceModel.fromJson(Map<String, dynamic>.from(r)),
      ];
    } catch (e) {
      _error = explainError(e, fallback: 'تعذر تحميل الأماكن المحفوظة');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete(SavedPlaceModel place) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('حذف ${place.label}'),
        content: const Text('هل تريد حذف هذا العنوان المحفوظ؟'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('إلغاء')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('حذف', style: TextStyle(color: context.tamColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.delete('/v1/patient/saved-places/${place.id}');
      await _load();
    } catch (e) {
      if (mounted) TamToast.show(context, explainError(e), tone: TamToastTone.error);
    }
  }

  Future<void> _addPlace() async {
    final labelCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    final landmarkCtrl = TextEditingController();
    LatLng point = kDamascus;
    bool saving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.viewInsetsOf(ctx).bottom + 20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('حفظ موقع جديد', style: aeroText(size: 17, weight: FontWeight.w800)),
                const SizedBox(height: 10),
                TextField(
                  controller: labelCtrl,
                  decoration: const InputDecoration(labelText: 'التسمية (مثال: المنزل)'),
                ),
                const SizedBox(height: 8),
                TamLocationPicker(
                  initial: point,
                  height: 170,
                  onChanged: (p, addr) {
                    point = p;
                    if (addressCtrl.text.isEmpty && addr.isNotEmpty) {
                      addressCtrl.text = addr;
                    }
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: addressCtrl,
                  decoration: const InputDecoration(labelText: 'العنوان التفصيلي'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: landmarkCtrl,
                  decoration: const InputDecoration(labelText: 'أقرب معلم (اختياري)'),
                ),
                const SizedBox(height: 14),
                AeroButton(
                  saving ? 'جارٍ الحفظ...' : 'حفظ الموقع',
                  isLoading: saving,
                  onPressed: saving
                      ? null
                      : () async {
                          if (labelCtrl.text.trim().isEmpty || addressCtrl.text.trim().isEmpty) return;
                          setSheet(() => saving = true);
                          try {
                            await widget.api.post('/v1/patient/saved-places', {
                              'label': labelCtrl.text.trim(),
                              'placeType': 'CUSTOM',
                              'formattedAddress': addressCtrl.text.trim(),
                              'latitude': point.latitude,
                              'longitude': point.longitude,
                              'accuracy': 10,
                              if (landmarkCtrl.text.trim().isNotEmpty) 'landmark': landmarkCtrl.text.trim(),
                            });
                            if (ctx.mounted) Navigator.of(ctx).pop();
                            _load();
                          } catch (e) {
                            setSheet(() => saving = false);
                            if (ctx.mounted) TamToast.show(ctx, explainError(e), tone: TamToastTone.error);
                          }
                        },
                ),
              ],
            ),
          ),
        ),
      ),
    );
    labelCtrl.dispose();
    addressCtrl.dispose();
    landmarkCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TamScaffold(
      title: 'الأماكن المحفوظة',
      subtitle: 'اختر العنوان بسرعة عند حجز الزيارة',
      showBack: true,
      actions: IconButton(
        tooltip: 'إضافة مكان',
        onPressed: _addPlace,
        icon: const Icon(Icons.add_location_alt_outlined),
      ),
      onRefresh: _load,
      children: [
        if (_loading)
          const TamSkeleton.card(height: 120)
        else if (_error != null)
          TamErrorState(title: 'تعذر تحميل العناوين', message: _error!, onRetry: _load)
        else if (_places.isEmpty) ...[
          const TamEmptyState(
            icon: Icons.place_outlined,
            title: 'لا توجد عناوين محفوظة بعد',
            message: 'أضف عنوان المنزل أو مكان العمل لتحديد موقع الزيارة بضغطة واحدة.',
          ),
          const SizedBox(height: 12),
          PrimaryButton('إضافة عنوان جديد', onPressed: _addPlace),
        ] else ...[
          for (final p in _places)
            TamCard(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  p.isDefault ? Icons.star_rounded : Icons.place_outlined,
                  color: context.tamColors.primary,
                ),
                title: Text(p.label, style: aeroText(size: 15, weight: FontWeight.w800)),
                subtitle: Text(
                  [p.formattedAddress, if (p.detailsSummary.isNotEmpty) p.detailsSummary].join('\n'),
                  style: aeroText(size: 12.5, color: context.tamColors.textSecondary),
                ),
                trailing: IconButton(
                  tooltip: 'حذف',
                  icon: Icon(Icons.delete_outline, color: context.tamColors.danger),
                  onPressed: () => _delete(p),
                ),
              ),
            ),
          PrimaryButton('إضافة عنوان جديد', onPressed: _addPlace),
        ],
      ],
    );
  }
}
