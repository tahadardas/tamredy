import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';

const _path = '/v1/patient/saved-places';
const _types = {
  'HOME': 'المنزل',
  'WORK': 'العمل',
  'PARENTS': 'منزل الوالدين',
  'CUSTOM': 'مكان آخر',
};

class SavedPlace {
  final Map<String, dynamic> data;
  const SavedPlace(this.data);

  String get id => data['id'] as String;
  String get label => data['label'] as String;
  String get address => data['formatted_address'] as String;
  double get accuracy => (data['accuracy'] as num).toDouble();
  LatLng get point => LatLng(
    (data['latitude'] as num).toDouble(),
    (data['longitude'] as num).toDouble(),
  );
  String get details => [
    if (data['building'] case final String value when value.trim().isNotEmpty)
      'البناء $value',
    if (data['floor'] case final String value when value.trim().isNotEmpty)
      'الطابق $value',
    if (data['landmark'] case final String value when value.trim().isNotEmpty)
      value,
    if (data['notes'] case final String value when value.trim().isNotEmpty)
      value,
  ].join(' • ');
}

class SavedPlaces extends StatefulWidget {
  final TamreedyApi api;
  final ValueChanged<SavedPlace> onSelected;
  const SavedPlaces({super.key, required this.api, required this.onSelected});

  @override
  State<SavedPlaces> createState() => _SavedPlacesState();
}

class _SavedPlacesState extends State<SavedPlaces> {
  List<SavedPlace> _places = [];
  bool _busy = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reload() async {
    final rows = await widget.api.getList(_path);
    if (mounted) {
      setState(
        () => _places = [
          for (final row in rows)
            SavedPlace(Map<String, dynamic>.from(row as Map)),
        ],
      );
    }
  }

  Future<void> _load() => _run(_reload);

  Future<void> _delete(SavedPlace place) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('حذف ${place.label}؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('رجوع'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    await _run(() async {
      await widget.api.dio.delete('$_path/${place.id}');
      await _reload();
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_busy) const LinearProgressIndicator(),
      if (_failed)
        TextButton(
          onPressed: _load,
          child: const Text('تعذر تحميل الأماكن المحفوظة، أعد المحاولة'),
        ),
      if (_places.isNotEmpty) const SectionTitle('الأماكن المحفوظة'),
      for (final place in _places)
        ListTile(
          title: Text(place.label),
          subtitle: Text(place.address),
          leading: Icon(
            place.data['is_default'] == true
                ? Icons.star
                : Icons.place_outlined,
          ),
          onTap: _busy
              ? null
              : () => _run(() async {
                  final selected = await widget.api.post(
                    '$_path/${place.id}/use',
                    {},
                  );
                  if (mounted) widget.onSelected(SavedPlace(selected));
                }),
          trailing: PopupMenuButton<String>(
            enabled: !_busy,
            onSelected: (action) async {
              if (action == 'delete') {
                await _delete(place);
              } else {
                final saved = await editSavedPlace(context, widget.api, place);
                if (saved && mounted) await _load();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('تعديل')),
              PopupMenuItem(value: 'delete', child: Text('حذف')),
            ],
          ),
        ),
    ],
  );
}

Future<bool> editSavedPlace(
  BuildContext context,
  TamreedyApi api,
  SavedPlace place,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => _PlaceEditor(api: api, place: place),
    ) ??
    false;

class _PlaceEditor extends StatefulWidget {
  final TamreedyApi api;
  final SavedPlace place;
  const _PlaceEditor({required this.api, required this.place});

  @override
  State<_PlaceEditor> createState() => _PlaceEditorState();
}

class _PlaceEditorState extends State<_PlaceEditor> {
  final _form = GlobalKey<FormState>();
  late final _label = TextEditingController(text: widget.place.label);
  late final _address = TextEditingController(text: widget.place.address);
  late final _fields = {
    for (final field in ['building', 'floor', 'landmark', 'notes'])
      field: TextEditingController(text: widget.place.data[field] as String?),
  };
  late String _type = widget.place.data['place_type'] as String? ?? 'CUSTOM';
  late bool _default = widget.place.data['is_default'] == true;
  bool _busy = false;
  bool _failed = false;

  @override
  void dispose() {
    _label.dispose();
    _address.dispose();
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    final place = widget.place;
    final payload = <String, dynamic>{
      'label': _label.text.trim(),
      'placeType': _type,
      'latitude': place.point.latitude,
      'longitude': place.point.longitude,
      'accuracy': place.accuracy,
      'formattedAddress': _address.text.trim(),
      'isDefault': _default,
      for (final entry in _fields.entries)
        if (entry.value.text.trim().isNotEmpty)
          entry.key: entry.value.text.trim(),
    };
    try {
      final id = place.data['id'];
      if (id == null) {
        await widget.api.post(_path, payload);
      } else {
        await widget.api.dio.put('$_path/$id', data: payload);
      }
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('حفظ المكان'),
    scrollable: true,
    content: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _label,
            maxLength: 80,
            decoration: const InputDecoration(labelText: 'اسم المكان'),
            validator: (value) =>
                value!.trim().isEmpty ? 'أدخل اسم المكان' : null,
          ),
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'نوع المكان'),
            items: [
              for (final type in _types.entries)
                DropdownMenuItem(value: type.key, child: Text(type.value)),
            ],
            onChanged: _busy ? null : (value) => setState(() => _type = value!),
          ),
          TextFormField(
            controller: _address,
            maxLength: 300,
            decoration: const InputDecoration(labelText: 'العنوان'),
            validator: (value) => value!.trim().isEmpty ? 'أدخل العنوان' : null,
          ),
          for (final (key, title, limit) in [
            ('building', 'البناء', 80),
            ('floor', 'الطابق', 40),
            ('landmark', 'أقرب معلم', 150),
            ('notes', 'ملاحظات الوصول', 300),
          ])
            TextFormField(
              controller: _fields[key],
              maxLength: limit,
              decoration: InputDecoration(labelText: title),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('الموقع الافتراضي'),
            value: _default,
            onChanged: _busy
                ? null
                : (value) => setState(() => _default = value),
          ),
          if (_failed) const Text('تعذر حفظ المكان. أعد المحاولة.'),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('إلغاء'),
      ),
      FilledButton(onPressed: _busy ? null : _save, child: const Text('حفظ')),
    ],
  );
}
