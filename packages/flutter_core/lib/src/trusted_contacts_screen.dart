import 'package:flutter/material.dart';

import 'api.dart';
import 'design/auth/syrian_phone_normalizer.dart';
import 'widgets.dart';

const _route = '/v1/me/trusted-contacts';

String _canonicalPhone(String value) {
  final cleaned = SyrianPhoneNormalizer.sanitize(value);
  return SyrianPhoneNormalizer.normalizeSyrianMobile(cleaned) ??
      (cleaned.startsWith('00') ? '+${cleaned.substring(2)}' : cleaned);
}

class TrustedContactsScreen extends StatefulWidget {
  final TamreedyApi api;
  const TrustedContactsScreen({super.key, required this.api});

  @override
  State<TrustedContactsScreen> createState() => _TrustedContactsScreenState();
}

class _TrustedContactsScreenState extends State<TrustedContactsScreen> {
  List<Map<String, dynamic>> _contacts = [];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      final contacts = (await widget.api.getList(
        _route,
      )).map((row) => Map<String, dynamic>.from(row as Map)).toList();
      if (mounted) setState(() => _contacts = contacts);
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'تعذر تحديث جهات الاتصال. تحقق من اتصالك ومن عدم تكرار الرقم أو الأولوية.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reload() => _run(() async {});

  Future<void> _edit([Map<String, dynamic>? row]) async {
    final priority = [1, 2, 3]
        .where(
          (value) => !_contacts.any((contact) => contact['priority'] == value),
        )
        .firstOrNull;
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _ContactEditor(contact: row, initialPriority: priority),
    );
    if (!mounted || payload == null) return;
    await _run(() async {
      if (row == null) {
        await widget.api.post(_route, payload);
      } else {
        await widget.api.put('$_route/${row['id']}', payload);
      }
    });
  }

  Future<void> _remove(Map<String, dynamic> row) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('حذف ${row['name']}؟'),
        content: const Text('يُلغي الحذف الإذن المسجل لهذه الجهة.'),
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
    if (!mounted || confirm != true) return;
    await _run(() async {
      await widget.api.dio.delete('$_route/${row['id']}');
    });
  }

  @override
  Widget build(BuildContext context) => TamScaffold(
    title: 'جهات الاتصال الموثوقة',
    subtitle: 'أضف حتى ثلاث جهات يمكن التواصل معها عند الحاجة',
    showBack: true,
    onRefresh: _reload,
    children: [
      const NoticeBox(
        'حفظ رقم الجهة لا يمنح الإذن بمشاركة الموقع. يتطلب التفعيل تحقق فريق السلامة وتوثيق موافقة الجهة.',
      ),
      if (_busy) const LinearProgressIndicator(),
      if (_error case final String message) ...[
        NoticeBox(message),
        TextButton(onPressed: _reload, child: const Text('إعادة المحاولة')),
      ],
      for (final row in _contacts)
        TamCard(
          child: ListTile(
            title: Text('${row['priority']}. ${row['name']}'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row['phone_e164'] as String,
                  textDirection: TextDirection.ltr,
                ),
                Text(switch (row['consent_state']) {
                  'ACCEPTED' =>
                    row['location_allowed'] == true
                        ? 'موافقة تشمل الموقع'
                        : 'موافقة على التواصل',
                  'DECLINED' => 'رفضت الجهة',
                  'REVOKED' => 'الموافقة ملغاة',
                  _ => 'بانتظار التحقق والموافقة',
                }),
              ],
            ),
            trailing: PopupMenuButton<String>(
              enabled: !_busy,
              onSelected: (action) =>
                  action == 'edit' ? _edit(row) : _remove(row),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('تعديل')),
                PopupMenuItem(value: 'delete', child: Text('حذف')),
              ],
            ),
          ),
        ),
      PrimaryButton(
        'إضافة جهة اتصال',
        onPressed: _busy || _contacts.length >= 3 ? null : () => _edit(),
      ),
    ],
  );
}

class _ContactEditor extends StatefulWidget {
  final Map<String, dynamic>? contact;
  final int? initialPriority;
  const _ContactEditor({required this.contact, required this.initialPriority});

  @override
  State<_ContactEditor> createState() => _ContactEditorState();
}

class _ContactEditorState extends State<_ContactEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(
    text: widget.contact?['name'] as String?,
  );
  late final _phone = TextEditingController(
    text: widget.contact?['phone_e164'] as String?,
  );
  late final _relationship = TextEditingController(
    text: widget.contact?['relationship'] as String?,
  );
  late int _priority =
      widget.contact?['priority'] as int? ?? widget.initialPriority ?? 1;
  late String _communication =
      widget.contact?['communication'] as String? ?? 'CALL';
  late bool _location = widget.contact?['request_location'] == true;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _relationship.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('جهة اتصال موثوقة'),
    scrollable: true,
    content: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _name,
            maxLength: 80,
            decoration: const InputDecoration(labelText: 'الاسم'),
            validator: (value) => value!.trim().isEmpty ? 'أدخل الاسم' : null,
          ),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(
              labelText: 'الهاتف بالصيغة الدولية',
            ),
            validator: (value) =>
                RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(_canonicalPhone(value!))
                ? null
                : 'استخدم + ثم رمز البلد والرقم',
          ),
          TextFormField(
            controller: _relationship,
            maxLength: 60,
            decoration: const InputDecoration(labelText: 'العلاقة'),
            validator: (value) => value!.trim().isEmpty ? 'أدخل العلاقة' : null,
          ),
          DropdownButtonFormField<int>(
            initialValue: _priority,
            decoration: const InputDecoration(labelText: 'أولوية التواصل'),
            items: [
              for (final value in [1, 2, 3])
                DropdownMenuItem(value: value, child: Text('$value')),
            ],
            onChanged: (value) => setState(() => _priority = value!),
          ),
          DropdownButtonFormField<String>(
            initialValue: _communication,
            decoration: const InputDecoration(labelText: 'وسيلة التواصل'),
            items: const [
              DropdownMenuItem(value: 'CALL', child: Text('اتصال هاتفي')),
              DropdownMenuItem(value: 'SMS', child: Text('رسالة نصية')),
            ],
            onChanged: (value) => setState(() => _communication = value!),
          ),
          SwitchListTile(
            title: const Text('طلب إذن بمشاركة آخر موقع عند الطوارئ'),
            value: _location,
            onChanged: (value) => setState(() => _location = value),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('إلغاء'),
      ),
      FilledButton(
        onPressed: () {
          if (!_form.currentState!.validate()) return;
          Navigator.pop(context, {
            'name': _name.text.trim(),
            'phone': _canonicalPhone(_phone.text),
            'relationship': _relationship.text.trim(),
            'priority': _priority,
            'communication': _communication,
            'requestLocation': _location,
          });
        },
        child: const Text('حفظ'),
      ),
    ],
  );
}
