import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'widgets.dart';

class EmergencyDirectoryScreen extends StatefulWidget {
  final TamreedyApi api;
  const EmergencyDirectoryScreen({super.key, required this.api});

  @override
  State<EmergencyDirectoryScreen> createState() =>
      _EmergencyDirectoryScreenState();
}

class _EmergencyDirectoryScreenState extends State<EmergencyDirectoryScreen> {
  final _storage = const FlutterSecureStorage();
  List<Map<String, dynamic>> _entries = [];
  bool _offline = false;
  bool _loading = false;
  DateTime? _cachedAt;

  String get _key =>
      'verifiedEmergencyDirectory.v1.${Uri.parse(TamreedyApi.baseUrl).origin}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final rows = _verified(await widget.api.getList('/v1/safety/directory'));
      if (!mounted) return;
      setState(() {
        _entries = rows;
        _offline = false;
        _cachedAt = null;
      });
      try {
        await _storage.write(
          key: _key,
          value: jsonEncode({
            'items': rows,
            'cachedAt': DateTime.now().toUtc().toIso8601String(),
          }),
        );
      } catch (_) {
        // The live directory remains available if the cache cannot be written.
      }
    } catch (_) {
      List<Map<String, dynamic>> cached = [];
      DateTime? cachedAt;
      try {
        final raw = await _storage.read(key: _key);
        if (raw != null) {
          final data = jsonDecode(raw) as Map<String, dynamic>;
          cachedAt = DateTime.tryParse('${data['cachedAt']}');
          if (cachedAt != null &&
              DateTime.now().difference(cachedAt) < const Duration(days: 7)) {
            cached = _verified(data['items'] as List);
          }
        }
      } catch (_) {
        // An unreadable cache must never display numbers as verified.
      }
      if (mounted)
        setState(() {
          _entries = cached;
          _offline = true;
          _cachedAt = cachedAt;
        });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _verified(List<dynamic> rows) {
    final now = DateTime.now();
    return [
      for (final row in rows.whereType<Map<String, dynamic>>().take(200))
        if (RegExp(r'^[+]?[0-9]{2,15}$').hasMatch('${row['dial_number']}') &&
            DateTime.tryParse('${row['verified_at']}') != null &&
            (DateTime.tryParse('${row['valid_until']}')?.isAfter(now) ?? false))
          row,
    ];
  }

  Future<void> _dial(Map<String, dynamic> row) async {
    if (_verified([row]).isEmpty) {
      await _load();
      return;
    }
    try {
      if (await launchUrl(
        Uri(scheme: 'tel', path: row['dial_number'] as String),
        mode: LaunchMode.externalApplication,
      ))
        return;
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تعذر فتح تطبيق الهاتف.')));
    }
  }

  @override
  Widget build(BuildContext context) => TamScaffold(
    title: 'دليل الطوارئ',
    subtitle: 'الأرقام التي تحقق منها مشرف السلامة',
    showBack: true,
    onRefresh: _load,
    children: [
      if (_loading) const LinearProgressIndicator(),
      if (_offline)
        NoticeBox(
          _entries.isNotEmpty && _cachedAt != null
              ? 'تعذر الاتصال. تُعرض نسخة محفوظة بتاريخ ${MaterialLocalizations.of(context).formatMediumDate(_cachedAt!.toLocal())}.'
              : 'تعذر تحميل دليل الطوارئ.',
        ),
      if (!_loading && _entries.isEmpty)
        const NoticeBox('لا توجد أرقام معتمدة متاحة حاليًا في الدليل.'),
      if (_offline)
        TextButton(
          onPressed: _loading ? null : _load,
          child: const Text('إعادة المحاولة'),
        ),
      for (final row in _verified(_entries))
        TamCard(
          child: ListTile(
            title: Text('${row['name']}'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${row['dial_number']}', textDirection: TextDirection.ltr),
                if (row['governorate'] != null)
                  Text(
                    [
                      row['governorate'],
                      row['area'],
                    ].whereType<String>().join('، '),
                  ),
                if (row['hours'] case final String hours when hours.isNotEmpty)
                  Text(hours),
              ],
            ),
            trailing: IconButton(
              onPressed: () => _dial(row),
              tooltip: 'فتح الرقم في تطبيق الهاتف',
              icon: const Icon(Icons.phone_outlined),
            ),
          ),
        ),
    ],
  );
}
