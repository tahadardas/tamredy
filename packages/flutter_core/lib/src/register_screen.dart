import 'package:flutter/material.dart';
import 'analytics.dart';
import 'api.dart';
import 'errors.dart';
import 'theme.dart';
import 'widgets.dart';

/// Patient self-registration. (Nurses apply through NurseApplyScreen: no account until staff approve.)
class RegisterScreen extends StatefulWidget {
  final TamreedyApi api;
  final VoidCallback onDone;
  const RegisterScreen({super.key, required this.api, required this.onDone});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _again = TextEditingController();
  bool _busy = false, _agree = false, _show = false;
  String? _error;

  static final _phoneRe = RegExp(r'^\+[1-9]\d{7,14}$');

  Widget _field(TextEditingController c, String hint, {bool ltr = false, bool secret = false, TextInputType? type}) => TamCard(
    child: TextField(
      controller: c,
      obscureText: secret && !_show,
      keyboardType: type,
      textDirection: ltr ? TextDirection.ltr : null,
      style: tamText(size: 18, weight: FontWeight.w700),
      decoration: InputDecoration(hintText: hint, hintStyle: tamText(color: TamreedyColors.subtext)),
    ),
  );

  String? _validate() {
    if (_name.text.trim().length < 2) return 'اكتب اسمك الكامل';
    if (!_phoneRe.hasMatch(_phone.text.trim())) return 'رقم الهاتف بصيغة دولية، مثل ‎+963911111111';
    if (_password.text.length < 8) return 'كلمة المرور 8 أحرف على الأقل';
    if (_password.text != _again.text) return 'تأكيد كلمة المرور لا يطابقها';
    if (!_agree) return 'يجب الموافقة على الشروط للمتابعة';
    return null;
  }

  Future<void> _submit() async {
    final bad = _validate();
    if (bad != null) return setState(() => _error = bad);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.register(_phone.text.trim(), _name.text.trim(), _password.text);
      Analytics.log('sign_up', {'role': 'patient'});
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
      widget.onDone();
      return;
    } catch (e) {
      _error = explainError(e, fallback: 'تعذر إنشاء الحساب، تحقق من البيانات والاتصال');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => TamScaffold(
    title: 'إنشاء حساب',
    subtitle: 'أنشئ حسابك لطلب الخدمات التمريضية المنزلية',
    showBack: true,
    children: [
      _field(_name, 'الاسم الكامل'),
      _field(_phone, '+963…', ltr: true, type: TextInputType.phone),
      _field(_password, 'كلمة المرور (8 أحرف فأكثر)', ltr: true, secret: true),
      _field(_again, 'تأكيد كلمة المرور', ltr: true, secret: true),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        value: _show,
        onChanged: (v) => setState(() => _show = v ?? false),
        title: Text('إظهار كلمة المرور', style: tamText(size: 13)),
        controlAffinity: ListTileControlAffinity.leading,
      ),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        value: _agree,
        onChanged: (v) => setState(() {
        _agree = v ?? false;
        _error = null;
      }),
        title: Text(
          'أوافق على شروط الاستخدام وسياسة الخصوصية، وأقرّ أن الخدمة غير مخصصة للحالات الطارئة',
          style: tamText(size: 13),
        ),
        controlAffinity: ListTileControlAffinity.leading,
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(_error!, style: tamText(size: 14, color: TamreedyColors.danger)),
        ),
      PrimaryButton('إنشاء الحساب', onPressed: _busy ? null : _submit),
    ],
  );
}
