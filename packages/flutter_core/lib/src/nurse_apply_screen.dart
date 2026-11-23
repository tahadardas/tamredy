import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'analytics.dart';
import 'api.dart';
import 'design/auth/syrian_phone_normalizer.dart';
import 'design/widgets/aero_syrian_phone_field.dart';
import 'errors.dart';
import 'theme.dart';
import 'widgets.dart';

class _Picked {
  final Uint8List bytes;
  final String name;
  const _Picked(this.bytes, this.name);
  bool get isImage => !name.toLowerCase().endsWith('.pdf');
}

/// Nurse join application in three steps: 1) data, 2) ID photo, 3) licence or practice certificate + responsibility pledge.
/// No account is created: the application waits for staff review and an interview.
class NurseApplyScreen extends StatefulWidget {
  final TamreedyApi api;
  const NurseApplyScreen({super.key, required this.api});
  @override
  State<NurseApplyScreen> createState() => _NurseApplyScreenState();
}

class _NurseApplyScreenState extends State<NurseApplyScreen> {
  static const _pledge =
      'أقرّ بأن جميع المعلومات التي أدخلتها صحيحة وأتحمّل مسؤوليتها القانونية كاملة، '
      'وأن الصور والمستندات التي رفعتها صحيحة وغير مزوّرة وأنا المسؤول عنها مسؤولية تامة.';

  int _step = 0;
  bool _busy = false, _done = false, _agree = false, _regionsFailed = false;
  String? _error;

  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _specialty = TextEditingController();
  final _nationalId = TextEditingController();
  final _licenseRef = TextEditingController();
  List<Map<String, dynamic>> _govs = [];
  String? _govId, _areaId;
  _Picked? _idPhoto, _document;
  String _docKind = 'LICENSE';
  DateTime? _expires;

  @override
  void initState() {
    super.initState();
    _loadRegions();
  }

  Future<void> _loadRegions() async {
    try {
      final d = await widget.api.getMap('/v1/catalog/regions');
      if (!mounted) return;
      setState(() {
        _govs = List<Map<String, dynamic>>.from(
          (d['governorates'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );
        _regionsFailed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _regionsFailed = true);
    }
  }

  List<Map<String, dynamic>> get _areas => List<Map<String, dynamic>>.from(
    ((_govs.firstWhere((g) => g['id'] == _govId, orElse: () => {'areas': <dynamic>[]})['areas']) as List)
        .map((e) => Map<String, dynamic>.from(e as Map)),
  );

  Future<_Picked?> _pick() async {
    final f = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
    );
    if (f == null) return null;
    if ((await f.length() ?? 0) > 8 * 1024 * 1024) {
      setState(() => _error = 'الملف أكبر من 8 ميغابايت، اختر ملفًا أصغر');
      return null;
    }
    return _Picked(await f.readAsBytes(), f.name);
  }

  String? _validate(int step) {
    if (step == 0) {
      if (_name.text.trim().length < 2) return 'اكتب اسمك الكامل';
      final phoneErr = SyrianPhoneNormalizer.validateSyrianMobile(_phone.text.trim());
      if (phoneErr != null) return phoneErr;
      if (_govId == null || _areaId == null) return 'اختر المحافظة والمنطقة التي تعمل فيها';
    }
    if (step == 1 && _idPhoto == null) return 'ارفع صورة هويتك';
    if (step == 2) {
      if (_licenseRef.text.trim().isEmpty) return 'اكتب رقم الوثيقة';
      if (_expires == null) return 'اختر تاريخ انتهاء الوثيقة';
      if (_document == null) return 'ارفع صورة الوثيقة';
      if (!_agree) return 'يجب الموافقة على الإقرار للمتابعة';
    }
    return null;
  }

  void _next() {
    final bad = _validate(_step);
    if (bad != null) return setState(() => _error = bad);
    setState(() {
      _error = null;
      _step++;
    });
  }

  Future<void> _submit() async {
    final bad = _validate(2);
    if (bad != null) return setState(() => _error = bad);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final normalizedPhone = SyrianPhoneNormalizer.normalizeSyrianMobile(_phone.text.trim())!;
      await widget.api.applyAsNurse(
        phone: normalizedPhone,
        name: _name.text.trim(),
        governorateId: _govId!,
        areaId: _areaId!,
        specialty: _specialty.text.trim(),
        nationalId: _nationalId.text.trim(),
        docKind: _docKind,
        licenseRef: _licenseRef.text.trim(),
        expiresAt: _expires!.toIso8601String().substring(0, 10),
        idBytes: _idPhoto!.bytes,
        idName: _idPhoto!.name,
        docBytes: _document!.bytes,
        docName: _document!.name,
      );
      Analytics.log('nurse_application_submitted', {'doc': _docKind});
      if (mounted) setState(() => _done = true);
      return;
    } catch (e) {
      _error = explainError(e, fallback: 'تعذر إرسال الطلب، تحقق من البيانات والاتصال');
    }
    if (mounted) setState(() => _busy = false);
  }

  // ---------- pieces ----------
  Widget _field(TextEditingController c, String hint, {bool ltr = false, TextInputType? type}) => TamCard(
    child: TextField(
      controller: c,
      keyboardType: type,
      textDirection: ltr ? TextDirection.ltr : null,
      style: tamText(size: 16, weight: FontWeight.w700),
      decoration: InputDecoration(hintText: hint, hintStyle: tamText(color: TamreedyColors.subtext)),
    ),
  );

  Widget _drop(String hint, String? value, List<Map<String, dynamic>> items, ValueChanged<String?> onChanged) => TamCard(
    child: DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      hint: Text(hint, style: tamText(color: TamreedyColors.subtext)),
      decoration: const InputDecoration(border: InputBorder.none),
      items: [
        for (final i in items)
          DropdownMenuItem(
            value: i['id'] as String,
            child: Text(i['name'] as String, style: tamText(size: 16, weight: FontWeight.w700)),
          ),
      ],
      onChanged: onChanged,
    ),
  );

  Widget _preview(_Picked? p) => p == null
      ? const SizedBox.shrink()
      : TamCard(
          child: Column(
            children: [
              if (p.isImage)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(p.bytes, height: 150, fit: BoxFit.cover),
                )
              else
                const Icon(Icons.picture_as_pdf, size: 56, color: TamreedyColors.teal),
              const SizedBox(height: 8),
              Text(p.name, style: tamText(size: 12, color: TamreedyColors.subtext), textDirection: TextDirection.ltr),
            ],
          ),
        );

  Widget _errorLine() => _error == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(_error!, style: tamText(size: 14, color: TamreedyColors.danger)),
        );

  Widget _stepper() => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      children: [
        for (var i = 0; i < 3; i++) ...[
          Expanded(
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: i <= _step ? TamreedyColors.teal : TamreedyColors.border,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          if (i < 2) const SizedBox(width: 6),
        ],
      ],
    ),
  );

  List<Widget> _stepOne() => [
    _field(_name, 'الاسم الكامل'),
    Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AeroSyrianPhoneField(controller: _phone),
    ),
    _drop('المحافظة التي تعمل فيها', _govId, _govs, (v) => setState(() {
      _govId = v;
      _areaId = null;
    })),
    if (_govId != null)
      KeyedSubtree(
        key: ValueKey(_govId),
        child: _drop('المنطقة', _areaId, _areas, (v) => setState(() => _areaId = v)),
      ),
    if (_regionsFailed) TextButton(onPressed: _loadRegions, child: const Text('تعذر تحميل المناطق، أعد المحاولة')),
    _field(_specialty, 'الاختصاص (اختياري)'),
    _field(_nationalId, 'الرقم الوطني (اختياري)', ltr: true, type: TextInputType.number),
    _errorLine(),
    PrimaryButton('التالي: صورة الهوية', onPressed: _next),
  ];

  List<Widget> _stepTwo() => [
    Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text('ارفع صورة واضحة لهويتك الشخصية (الوجه الأمامي)، تظهر فيها كل البيانات.', style: tamText(size: 15)),
    ),
    _preview(_idPhoto),
    SoftButton(
      _idPhoto == null ? 'اختيار صورة الهوية' : 'تغيير الصورة',
      onPressed: () async {
        final p = await _pick();
        if (p != null) setState(() {
          _idPhoto = p;
          _error = null;
        });
      },
    ),
    _errorLine(),
    PrimaryButton('التالي: الرخصة أو الشهادة', onPressed: _next),
    SoftButton('رجوع', onPressed: () => setState(() => _step = 0)),
  ];

  List<Widget> _stepThree() => [
    Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text('ارفع رخصة مزاولة المهنة أو شهادة مزاولة المهنة.', style: tamText(size: 15)),
    ),
    Wrap(
      spacing: 10,
      children: [
        ChoiceChip(
          label: Text('رخصة مزاولة', style: tamText(size: 15, weight: FontWeight.w700)),
          selected: _docKind == 'LICENSE',
          onSelected: (_) => setState(() => _docKind = 'LICENSE'),
        ),
        ChoiceChip(
          label: Text('شهادة مزاولة المهنة', style: tamText(size: 15, weight: FontWeight.w700)),
          selected: _docKind == 'PRACTICE_CERT',
          onSelected: (_) => setState(() => _docKind = 'PRACTICE_CERT'),
        ),
      ],
    ),
    const SizedBox(height: 10),
    _field(_licenseRef, 'رقم الوثيقة', ltr: true),
    TamCard(
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: DateTime.now().add(const Duration(days: 365)),
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 365 * 20)),
        );
        if (d != null) setState(() => _expires = d);
      },
      child: Text(
        _expires == null ? 'تاريخ انتهاء الوثيقة' : _expires!.toIso8601String().substring(0, 10),
        style: tamText(size: 16, weight: FontWeight.w700, color: _expires == null ? TamreedyColors.subtext : TamreedyColors.navy),
      ),
    ),
    _preview(_document),
    SoftButton(
      _document == null ? 'اختيار صورة الوثيقة' : 'تغيير الصورة',
      onPressed: () async {
        final p = await _pick();
        if (p != null) setState(() {
          _document = p;
          _error = null;
        });
      },
    ),
    Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6E0),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF2D58B)),
      ),
      child: Text(_pledge, style: tamText(size: 14, weight: FontWeight.w700)),
    ),
    CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      value: _agree,
      onChanged: (v) => setState(() {
        _agree = v ?? false;
        _error = null;
      }),
      title: Text('أوافق على الإقرار أعلاه وأتحمّل مسؤوليته', style: tamText(size: 14, weight: FontWeight.w700)),
      controlAffinity: ListTileControlAffinity.leading,
    ),
    _errorLine(),
    PrimaryButton(_busy ? 'جارٍ إرسال الطلب...' : 'إرسال الطلب', onPressed: _busy ? null : _submit),
    SoftButton('رجوع', onPressed: _busy ? null : () => setState(() => _step = 1)),
  ];

  Widget _doneView() => TamScaffold(
    title: 'تم تسجيل طلبك',
    subtitle: 'شكرًا لانضمامك إلى تمريضي',
    children: [
      HeroCard(
        title: 'طلبك بانتظار موعد المقابلة',
        body: 'سنراجع هويتك ووثيقتك ونتواصل معك على الرقم ${_phone.text.trim()} لتحديد موعد المقابلة. '
            'بعد اعتماد طلبك يُنشأ حسابك وتُزوَّد ببيانات الدخول.',
      ),
      const NoticeBox('لا يمكنك تسجيل الدخول حاليًا؛ الحساب يُنشأ بعد الاعتماد.'),
      PrimaryButton('حسنًا', onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (_done) return _doneView();
    const titles = ['معلوماتك', 'صورة الهوية', 'الرخصة أو الشهادة'];
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) setState(() => _step--);
      },
      child: TamScaffold(
        title: 'تسجيل ممرض جديد',
        subtitle: 'الخطوة ${_step + 1} من 3: ${titles[_step]}',
        showBack: true,
        children: [
          _stepper(),
          ...[_stepOne, _stepTwo, _stepThree][_step](),
        ],
      ),
    );
  }
}
