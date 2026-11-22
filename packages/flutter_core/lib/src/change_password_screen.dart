import 'package:flutter/material.dart';
import 'api.dart';
import 'errors.dart';
import 'theme.dart';
import 'widgets.dart';

/// Shown at first login with the initial password (the server blocks everything else until it is replaced).
class ChangePasswordScreen extends StatefulWidget {
  final TamreedyApi api;
  final VoidCallback onDone;
  final VoidCallback onLogout;
  const ChangePasswordScreen({
    super.key,
    required this.api,
    required this.onDone,
    required this.onLogout,
  });
  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _again = TextEditingController();
  bool _busy = false, _show = false;
  String? _error;

  Widget _field(TextEditingController c, String hint) => TamCard(
    child: TextField(
      controller: c,
      obscureText: !_show,
      textDirection: TextDirection.ltr,
      style: tamText(size: 18, weight: FontWeight.w700),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: tamText(color: TamreedyColors.subtext),
      ),
    ),
  );

  Future<void> _save() async {
    if (_next.text.length < 8) {
      return setState(() => _error = 'كلمة المرور الجديدة 8 أحرف أو أرقام على الأقل');
    }
    if (_next.text != _again.text) {
      return setState(() => _error = 'التأكيد لا يطابق كلمة المرور الجديدة');
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.changePassword(_current.text, _next.text);
      if (!mounted) return;
      widget.onDone();
      return;
    } catch (e) {
      _error = explainError(e, fallback: 'تعذر تغيير كلمة المرور، حاول مرة أخرى');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => TamScaffold(
    title: 'اختر كلمة مرور جديدة',
    subtitle: 'هذا أول دخول لك. لحماية حسابك يجب تغيير كلمة المرور المؤقتة',
    children: [
      _field(_current, 'كلمة المرور الحالية (المؤقتة)'),
      _field(_next, 'كلمة المرور الجديدة (8 فأكثر)'),
      _field(_again, 'أعد كتابة الجديدة'),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        value: _show,
        onChanged: (v) => setState(() => _show = v ?? false),
        title: Text('إظهار كلمة المرور', style: tamText(size: 13)),
        controlAffinity: ListTileControlAffinity.leading,
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(_error!, style: tamText(size: 13, color: TamreedyColors.danger)),
        ),
      PrimaryButton('حفظ ومتابعة', onPressed: _busy ? null : _save),
      SoftButton('تسجيل الخروج', onPressed: widget.onLogout),
    ],
  );
}
