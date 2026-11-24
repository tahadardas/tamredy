import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';

class VisitCompanions extends StatefulWidget {
  final TamreedyApi api;
  const VisitCompanions({super.key, required this.api});

  @override
  State<VisitCompanions> createState() => _VisitCompanionsState();
}

class _VisitCompanionsState extends State<VisitCompanions> {
  static const _path = '/v1/nurse/safety/companions';
  List<Map<String, dynamic>> _pending = [];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load([Map<String, dynamic>? confirmation]) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      if (confirmation != null) {
        final id = confirmation['request_id'];
        await widget.api.post('$_path/$id/confirm', {'nurseId': confirmation['nurse_id']});
      }
      final result = await widget.api.getList(_path);
      if (mounted) setState(() => _pending = result.cast<Map<String, dynamic>>());
    } catch (e) {
      if (mounted) setState(() => _error = explainError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_pending.isNotEmpty) const SectionTitle('طلبات المرافقة المهنية'),
      for (final row in _pending)
        ListTile(
          title: Text('${row['service_title']}'),
          subtitle: const Text('أكّد فقط إذا كنت مستعدًا لمرافقة الزيارة.'),
          trailing: TextButton(
            onPressed: _busy ? null : () => _load(row),
            child: const Text('تأكيد المرافقة'),
          ),
        ),
      if (_error case final String message)
        TextButton(onPressed: _load, child: Text(message)),
    ],
  );
}
