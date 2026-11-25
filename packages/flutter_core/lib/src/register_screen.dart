import 'package:flutter/material.dart';
import 'analytics.dart';
import 'api.dart';
import 'design/auth/syrian_phone_normalizer.dart';
import 'design/tokens/tam_tokens.dart';
import 'design/widgets/aero_button.dart';
import 'design/widgets/aero_syrian_phone_field.dart';
import 'design/widgets/tam_inputs.dart';
import 'errors.dart';
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

  final _nameFocus = FocusNode();
  final _passFocus = FocusNode();
  final _againFocus = FocusNode();

  bool _busy = false, _agree = false, _show = false;
  String? _error, _nameError, _passError, _againError;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _password.dispose();
    _again.dispose();
    _nameFocus.dispose();
    _passFocus.dispose();
    _againFocus.dispose();
    super.dispose();
  }

  String? _validate() {
    _nameError = null;
    _passError = null;
    _againError = null;

    if (_name.text.trim().length < 2) {
      _nameError = 'اكتب اسمك الكامل (حرفان على الأقل)';
    }
    final phoneErr = SyrianPhoneNormalizer.validateSyrianMobile(_phone.text.trim());
    if (_password.text.length < 8) {
      _passError = 'كلمة المرور 8 أحرف على الأقل';
    }
    if (_password.text != _again.text) {
      _againError = 'تأكيد كلمة المرور لا يطابقها';
    }

    if (_nameError != null) return _nameError;
    if (phoneErr != null) return phoneErr;
    if (_passError != null) return _passError;
    if (_againError != null) return _againError;
    if (!_agree) return 'يجب الموافقة على الشروط للمتابعة';
    return null;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final bad = _validate();
    if (bad != null) return setState(() => _error = bad);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final normalizedPhone = SyrianPhoneNormalizer.normalizeSyrianMobile(_phone.text.trim())!;
      await widget.api.register(normalizedPhone, _name.text.trim(), _password.text);
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
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    return TamScaffold(
      title: 'إنشاء حساب',
      subtitle: 'أنشئ حسابك لطلب الخدمات التمريضية المنزلية',
      showBack: true,
      children: [
        TamTextField(
          controller: _name,
          focusNode: _nameFocus,
          label: 'الاسم الكامل',
          hint: 'مثال: أحمد محمد',
          prefixIcon: Icons.person_outline_rounded,
          errorText: _nameError,
          autofillHints: const [AutofillHints.name],
          textInputAction: TextInputAction.next,
          onChanged: (_) {
            if (_nameError != null) setState(() => _nameError = null);
          },
          onSubmitted: (_) => _passFocus.requestFocus(),
        ),
        const SizedBox(height: TamSpacing.md),
        AeroSyrianPhoneField(controller: _phone),
        const SizedBox(height: TamSpacing.md),
        TamTextField(
          controller: _password,
          focusNode: _passFocus,
          label: 'كلمة المرور',
          hint: '8 أحرف فأكثر',
          prefixIcon: Icons.lock_outline_rounded,
          obscureText: !_show,
          textDirection: TextDirection.ltr,
          errorText: _passError,
          autofillHints: const [AutofillHints.newPassword],
          textInputAction: TextInputAction.next,
          suffix: IconButton(
            tooltip: _show ? 'إخفاء كلمة المرور' : 'إظهار كلمة المرور',
            icon: Icon(_show ? Icons.visibility_off : Icons.visibility, color: tc.textSecondary),
            onPressed: () => setState(() => _show = !_show),
          ),
          onChanged: (_) {
            if (_passError != null) setState(() => _passError = null);
          },
          onSubmitted: (_) => _againFocus.requestFocus(),
        ),
        const SizedBox(height: TamSpacing.md),
        TamTextField(
          controller: _again,
          focusNode: _againFocus,
          label: 'تأكيد كلمة المرور',
          hint: 'أعد كتابة كلمة المرور',
          prefixIcon: Icons.lock_reset_rounded,
          obscureText: !_show,
          textDirection: TextDirection.ltr,
          errorText: _againError,
          textInputAction: TextInputAction.done,
          onChanged: (_) {
            if (_againError != null) setState(() => _againError = null);
          },
          onSubmitted: (_) {
            if (!_busy) _submit();
          },
        ),
        const SizedBox(height: TamSpacing.sm),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          activeColor: tc.primary,
          value: _agree,
          onChanged: (v) => setState(() {
            _agree = v ?? false;
            _error = null;
          }),
          title: Text(
            'أوافق على شروط الاستخدام وسياسة الخصوصية، وأقرّ أن الخدمة غير مخصصة للحالات الطارئة',
            style: TextStyle(fontSize: 13, color: tc.textPrimary, height: 1.45),
          ),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              _error!,
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: tc.danger),
            ),
          ),
        const SizedBox(height: TamSpacing.xs),
        AeroButton.teal(
          'إنشاء الحساب',
          isLoading: _busy,
          onPressed: _busy ? null : _submit,
        ),
      ],
    );
  }
}
