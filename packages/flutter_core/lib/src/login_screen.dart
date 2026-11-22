import 'package:flutter/material.dart';
import 'analytics.dart';
import 'api.dart';
import 'change_password_screen.dart';
import 'errors.dart';
import 'nurse_apply_screen.dart';
import 'register_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Two-step phone + OTP login shared by the patient and nurse apps.
class LoginScreen extends StatefulWidget {
  final TamreedyApi api;
  final String expectedRole; // PATIENT or NURSE
  final VoidCallback onLoggedIn;
  const LoginScreen({
    super.key,
    required this.api,
    required this.expectedRole,
    required this.onLoggedIn,
  });
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool get _pw => kAuthMode == 'password';
  bool _codeSent = false, _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function() job, String fail) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await job();
    } catch (e) {
      // wrong role keeps the specific message; everything else says what really happened
      _error = (e is Exception && e.toString().contains('role')) ? fail : explainError(e, fallback: fail);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => TamScaffold(
    title: 'تسجيل الدخول',
    subtitle: _pw
        ? 'أدخل رقم هاتفك وكلمة المرور'
        : _codeSent
        ? 'أدخل الرمز المرسل إلى هاتفك'
        : 'أدخل رقم هاتفك بصيغة دولية، مثل ‎+963911111111',
    children: [
      if (_pw) ...[
        TamCard(
          child: TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            style: tamText(size: 18, weight: FontWeight.w700),
            decoration: InputDecoration(
              hintText: '+963…',
              hintStyle: tamText(color: TamreedyColors.subtext),
            ),
          ),
        ),
        TamCard(
          child: TextField(
            controller: _password,
            obscureText: true,
            textDirection: TextDirection.ltr,
            style: tamText(size: 18, weight: FontWeight.w700),
            decoration: InputDecoration(
              hintText: 'كلمة المرور',
              hintStyle: tamText(color: TamreedyColors.subtext),
            ),
          ),
        ),
      ] else
        TamCard(
          child: TextField(
            controller: _codeSent ? _code : _phone,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            style: tamText(size: 18, weight: FontWeight.w700),
            decoration: InputDecoration(
              hintText: _codeSent ? '000000' : '+963…',
              hintStyle: tamText(color: TamreedyColors.subtext),
            ),
          ),
        ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            _error!,
            style: tamText(size: 12, color: TamreedyColors.danger),
          ),
        ),
      if (_pw)
        PrimaryButton(
          'دخول',
          onPressed: _busy
              ? null
              : () => _run(
                  () async {
                    final role = await widget.api.login(
                      _phone.text.trim(),
                      _password.text,
                    );
                    if (role != widget.expectedRole) {
                      await widget.api.logout();
                      throw Exception('role');
                    }
                    Analytics.log('login', {
                      'method': kAuthMode,
                      'role': role.toLowerCase(),
                    });
                    if (widget.api.mustChangePassword) {
                      if (!mounted) return;
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ChangePasswordScreen(
                            api: widget.api,
                            onDone: () {
                              Navigator.of(context).popUntil((r) => r.isFirst);
                              widget.onLoggedIn();
                            },
                            onLogout: () async {
                              await widget.api.logout();
                              if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
                            },
                          ),
                        ),
                      );
                      return;
                    }
                    widget.onLoggedIn();
                  },
                  'بيانات الدخول غير صحيحة، أو الحساب مقفل/غير مناسب لهذا التطبيق',
                ),
        )
      else
        PrimaryButton(
          _codeSent ? 'تأكيد الرمز' : 'إرسال الرمز',
          onPressed: _busy
              ? null
              : () => _run(
                  () async {
                    if (!_codeSent) {
                      await widget.api.requestOtp(_phone.text.trim());
                      _codeSent = true;
                    } else {
                      final role = await widget.api.verifyOtp(
                        _phone.text.trim(),
                        _code.text.trim(),
                      );
                      if (role != widget.expectedRole) {
                        await widget.api.logout();
                        throw Exception('role');
                      }
                      widget.onLoggedIn();
                    }
                  },
                  _codeSent
                      ? 'الرمز غير صحيح أو منتهٍ، أو الحساب غير مناسب لهذا التطبيق'
                      : 'تعذر إرسال الرمز؛ حاول لاحقًا',
                ),
        ),
      if (_pw)
        Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => widget.expectedRole == 'NURSE'
                    ? NurseApplyScreen(api: widget.api)
                    : RegisterScreen(api: widget.api, onDone: widget.onLoggedIn),
              ),
            ),
            child: Text(
              widget.expectedRole == 'NURSE'
                  ? 'ممرض جديد؟ قدّم طلب انضمام'
                  : 'ليس لديك حساب؟ إنشاء حساب جديد',
              style: tamText(
                size: 14,
                weight: FontWeight.w700,
                color: TamreedyColors.teal,
              ),
            ),
          ),
        ),
      if (!_pw)
        const NoticeBox(
          'لا نشارك رمز التحقق مع أي شخص. يُرسل الرمز عبر مزود رسائل معتمد.',
        ),
    ],
  );
}

/// Shows [child] in demo mode or once a session exists; otherwise the login.
class AuthGate extends StatefulWidget {
  final TamreedyApi api;
  final String role;
  final WidgetBuilder child;
  const AuthGate({
    super.key,
    required this.api,
    required this.role,
    required this.child,
  });
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool? _in = kDemoMode ? true : null;
  bool _mustChange = false;
  @override
  void initState() {
    super.initState();
    if (!kDemoMode) {
      widget.api.hasSession().then((has) async {
        if (!has) {
          if (mounted) setState(() => _in = false);
          return;
        }
        try {
          final me = await widget.api.getMap('/v1/auth/me');
          final role = me['role'] as String?;
          if (role != widget.role) {
            await widget.api.logout();
            if (mounted) setState(() => _in = false);
            return;
          }
          final must = me['mustChangePassword'] == true;
          if (mounted) {
            setState(() {
              _in = true;
              _mustChange = must;
            });
          }
        } catch (_) {
          await widget.api.logout();
          if (mounted) {
            setState(() {
              _in = false;
              _mustChange = false;
            });
          }
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_in == null)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_in! && _mustChange) {
      return ChangePasswordScreen(
        api: widget.api,
        onDone: () => setState(() => _mustChange = false),
        onLogout: () async {
          await widget.api.logout();
          if (mounted) setState(() => _in = false);
        },
      );
    }
    if (_in!) return widget.child(context);
    return LoginScreen(
      api: widget.api,
      expectedRole: widget.role,
      onLoggedIn: () => setState(() => _in = true),
    );
  }
}
