import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';

class NightPreference extends StatefulWidget {
  final TamreedyApi api;
  const NightPreference({super.key, required this.api});

  @override
  State<NightPreference> createState() => _NightPreferenceState();
}

class _NightPreferenceState extends State<NightPreference> {
  static const _path = '/v1/nurse/safety/night-preference';
  bool? _enabled;
  bool _optedIn = false;
  bool _busy = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load([bool? optIn]) async {
    if (_busy) return;
    setState(() { _busy = true; _failed = false; });
    try {
      final result = optIn == null ? await widget.api.getMap(_path) :
        await widget.api.put(_path, {'optedIn': optIn});
      if (mounted) setState(() {
        _enabled = result['enabled'] == true;
        _optedIn = result['optedIn'] == true;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_enabled == true)
        SwitchListTile(
          title: const Text('أوافق على استقبال عروض العمل الليلي'),
          subtitle: const Text('تُطبق ضوابط الأهلية والتغطية المعتمدة للزيارة.'),
          value: _optedIn,
          onChanged: _busy ? null : (value) => _load(value),
        ),
      if (_failed) TextButton(onPressed: _load, child: const Text('تعذر تحديث تفضيل العمل الليلي، أعد المحاولة')),
    ],
  );
}
