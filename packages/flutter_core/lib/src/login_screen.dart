import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'analytics.dart';
import 'api.dart';
import 'change_password_screen.dart';
import 'design/auth/syrian_phone_normalizer.dart';
import 'design/widgets/aero_syrian_phone_field.dart';
import 'design/widgets/aero_button.dart';
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
  bool _showPassword = false;

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
  void dispose() {
    _phone.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _showRecovery() async {
    const supportContact = String.fromEnvironment('RECOVERY_SUPPORT_CONTACT');
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('استعادة كلمة المرور'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'تواصل مع دعم تمريضي عبر القناة الرسمية للتحقق من هويتك. '
              'بعد التحقق، يصدر الدعم كلمة مرور مؤقتة صالحة لمدة 30 دقيقة. '
              'سجّل الدخول بها واختر كلمة مرور جديدة.',
            ),
            if (supportContact.isNotEmpty) ...[
              const SizedBox(height: 12),
              const SelectableText(supportContact),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => TamScaffold(
    title: 'تسجيل الدخول',
    subtitle: _pw
        ? 'أدخل رقم هاتفك (09XXXXXXXX) وكلمة المرور'
        : _codeSent
        ? 'أدخل الرمز المرسل إلى هاتفك'
        : 'أدخل رقم هاتفك السوري (مثال: 0987080330)',
    children: [
      if (_pw) ...[
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AeroSyrianPhoneField(
            controller: _phone,
          ),
        ),
        TamCard(
          child: TextField(
            controller: _password,
            obscureText: !_showPassword,
            autofillHints: const [AutofillHints.password],
            textDirection: TextDirection.ltr,
            style: tamText(size: 18, weight: FontWeight.w700),
            decoration: InputDecoration(
              labelText: 'كلمة المرور',
              suffixIcon: IconButton(
                tooltip: _showPassword ? 'إخفاء كلمة المرور' : 'إظهار كلمة المرور',
                onPressed: () => setState(() => _showPassword = !_showPassword),
                icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
              ),
              hintStyle: tamText(color: TamreedyColors.subtext),
            ),
          ),
        ),
      ] else if (!_codeSent)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AeroSyrianPhoneField(
            controller: _phone,
          ),
        )
      else
        TamCard(
          child: TextField(
            controller: _code,
            keyboardType: TextInputType.number,
            textDirection: TextDirection.ltr,
            style: tamText(size: 18, weight: FontWeight.w700),
            decoration: InputDecoration(
              hintText: '000000',
              hintStyle: tamText(color: TamreedyColors.subtext),
            ),
          ),
        ),
      if (_pw)
        TextButton(
          onPressed: _busy ? null : _showRecovery,
          child: const Text('نسيت كلمة المرور؟'),
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
        AeroButton.teal(
          'تسجيل الدخول',
          width: double.infinity,
          isLoading: _busy,
          onPressed: _busy
              ? null
              : () => _run(
                  () async {
                    final phoneErr = SyrianPhoneNormalizer.validateSyrianMobile(_phone.text.trim());
                    if (phoneErr != null) {
                      throw Exception(phoneErr);
                    }
                    final normalizedPhone = SyrianPhoneNormalizer.normalizeSyrianMobile(_phone.text.trim())!;
                    final role = await widget.api.login(
                      normalizedPhone,
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
                    final phoneErr = SyrianPhoneNormalizer.validateSyrianMobile(_phone.text.trim());
                    if (phoneErr != null && !_codeSent) {
                      throw Exception(phoneErr);
                    }
                    final normalizedPhone = SyrianPhoneNormalizer.normalizeSyrianMobile(_phone.text.trim()) ?? _phone.text.trim();
                    if (!_codeSent) {
                      await widget.api.requestOtp(normalizedPhone);
                      _codeSent = true;
                    } else {
                      final role = await widget.api.verifyOtp(
                        normalizedPhone,
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
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: AeroButton.secondary(
            widget.expectedRole == 'NURSE' ? 'تقديم طلب انضمام' : 'إنشاء حساب جديد',
            width: double.infinity,
            onPressed: _busy ? null : () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => widget.expectedRole == 'NURSE'
                    ? NurseApplyScreen(api: widget.api)
                    : RegisterScreen(api: widget.api, onDone: widget.onLoggedIn),
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

/// Explicit session lifecycle states to guarantee persistent trusted device sessions
enum AuthGateStatus {
  initializing,
  authenticated,
  offlineWithSavedSession,
  reauthenticationRequired,
  signedOut,
  accountSuspended,
}

/// Resilient AuthGate: Keeps trusted devices signed in across months and network drops.
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
  AuthGateStatus _status = kDemoMode ? AuthGateStatus.authenticated : AuthGateStatus.initializing;
  bool _mustChange = false;

  @override
  void initState() {
    super.initState();
    if (!kDemoMode) {
      _verifySession();
    }
  }

  Future<void> _verifySession() async {
    final has = await widget.api.hasSession();
    if (!has) {
      if (mounted) setState(() => _status = AuthGateStatus.signedOut);
      return;
    }

    final cachedRole = await widget.api.getCachedRole();
    if (cachedRole != null && cachedRole != widget.role) {
      // Role mismatch (e.g. nurse trying to open patient app)
      await widget.api.logout();
      if (mounted) setState(() => _status = AuthGateStatus.signedOut);
      return;
    }

    try {
      final me = await widget.api.getMap('/v1/auth/me');
      final role = me['role'] as String?;
      if (role != null && role != widget.role) {
        await widget.api.logout();
        if (mounted) setState(() => _status = AuthGateStatus.signedOut);
        return;
      }
      final must = me['mustChangePassword'] == true;
      if (mounted) {
        setState(() {
          _status = AuthGateStatus.authenticated;
          _mustChange = must;
        });
      }
    } catch (e) {
      // Analyze the failure precisely:
      // Never wipe trusted device credentials due to transient network failures!
      if (e is DioException) {
        final code = e.response?.statusCode;
        final data = e.response?.data;
        final err = data is Map ? (data['code'] ?? data['message']) : null;

        if (code == 403 && (err == 'ACCOUNT_INACTIVE' || err == 'ACCOUNT_LOCKED')) {
          if (mounted) setState(() => _status = AuthGateStatus.accountSuspended);
          return;
        }

        if (code == 401 && (err == 'SESSION_REVOKED' || err == 'REFRESH_REVOKED' || err == 'REFRESH_INVALID' || err == 'REFRESH_EXPIRED')) {
          await widget.api.logout();
          if (mounted) setState(() => _status = AuthGateStatus.reauthenticationRequired);
          return;
        }

        // Network timeouts, offline DNS, connection drops, 5xx server errors
        if (mounted) {
          setState(() => _status = AuthGateStatus.offlineWithSavedSession);
        }
        return;
      }

      if (mounted) {
        setState(() => _status = AuthGateStatus.offlineWithSavedSession);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_status) {
      case AuthGateStatus.initializing:
        return const Scaffold(
          backgroundColor: Color(0xFFF5FAFD),
          body: Center(
            child: CircularProgressIndicator(color: TamreedyColors.teal),
          ),
        );

      case AuthGateStatus.accountSuspended:
        return Scaffold(
          backgroundColor: const Color(0xFFF5FAFD),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: TamreedyColors.danger.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.block_rounded, size: 48, color: TamreedyColors.danger),
                  ),
                  const SizedBox(height: 20),
                  Text('تم تعليق الحساب', style: tamText(size: 20, weight: FontWeight.w800, color: TamreedyColors.text)),
                  const SizedBox(height: 10),
                  Text(
                    'تم إيقاف هذا الحساب أو تعليقه من قبل إدارة تمريضي لأسباب تنظيمية. يرجى مراجعة الدعم الفني.',
                    textAlign: TextAlign.center,
                    style: tamText(size: 14, color: TamreedyColors.subtext, height: 1.5),
                  ),
                  const SizedBox(height: 28),
                  PrimaryButton(
                    'تسجيل الخروج',
                    onPressed: () async {
                      await widget.api.logout();
                      if (mounted) setState(() => _status = AuthGateStatus.signedOut);
                    },
                  ),
                ],
              ),
            ),
          ),
        );

      case AuthGateStatus.reauthenticationRequired:
      case AuthGateStatus.signedOut:
        return LoginScreen(
          api: widget.api,
          expectedRole: widget.role,
          onLoggedIn: () => setState(() => _status = AuthGateStatus.authenticated),
        );

      case AuthGateStatus.authenticated:
        if (_mustChange) {
          return ChangePasswordScreen(
            api: widget.api,
            onDone: () => setState(() => _mustChange = false),
            onLogout: () async {
              await widget.api.logout();
              if (mounted) setState(() => _status = AuthGateStatus.signedOut);
            },
          );
        }
        return widget.child(context);

      case AuthGateStatus.offlineWithSavedSession:
        return Stack(
          children: [
            widget.child(context),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF163B52).withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 3)),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.wifi_off_rounded, size: 16, color: Color(0xFFDFF4F2)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'أنت في وضع عدم الاتصال — جلستك محفوظة وسيتم المزامنة تلقائياً',
                          style: tamText(size: 12, weight: FontWeight.w600, color: Colors.white),
                        ),
                      ),
                      InkWell(
                        onTap: _verifySession,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          child: Icon(Icons.refresh_rounded, size: 16, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
    }
  }
}
