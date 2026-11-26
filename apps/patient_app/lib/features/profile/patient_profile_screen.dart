import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../../app/patient_router.dart';
import '../../core/patient_session_coordinator.dart';
import '../finance/wallet_screen.dart';
import 'beneficiaries_screen.dart';
import 'care_plans_screen.dart';
import 'commitment_screen.dart';
import 'favorite_nurses_screen.dart';
import 'health_record_screen.dart';
import 'notifications_screen.dart';
import 'referral_screen.dart';
import 'saved_places_screen.dart';

class PatientProfileScreen extends StatefulWidget {
  final PatientSessionCoordinator session;

  const PatientProfileScreen({super.key, required this.session});

  @override
  State<PatientProfileScreen> createState() => _PatientProfileScreenState();
}

class _PatientProfileScreenState extends State<PatientProfileScreen> {
  final _promoCtrl = TextEditingController();
  String? _promoResult;

  @override
  void dispose() {
    _promoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    final session = widget.session;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: TamBreakpoints.maxContentWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'حسابي وإعداداتي',
                    style: aeroText(size: 19, weight: FontWeight.w800, color: tc.textPrimary),
                  ),
                  const SizedBox(height: 12),
                  const SectionTitle('الرعاية الصحية والمستفيدون'),
                  TamCard(
                    child: Column(
                      children: [
                        ListRow(
                          icon: Icons.family_restroom_outlined,
                          title: 'المستفيدون وأفراد العائلة',
                          subtitle: 'إدارة ملفات المرضى المعتمدين',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => BeneficiariesScreen(session: session),
                            ),
                          ),
                        ),
                        ListRow(
                          icon: Icons.bookmark_outline_rounded,
                          title: 'الأماكن المحفوظة',
                          subtitle: 'المنزل والعمل والمواقع المتكررة',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => SavedPlacesScreen(api: session.api),
                            ),
                          ),
                        ),
                        ListRow(
                          icon: Icons.folder_shared_outlined,
                          title: 'السجل الصحي والتقارير',
                          subtitle: 'الحساسية والفصيلة والقياسات الحيوية',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => HealthRecordScreen(api: session.api),
                            ),
                          ),
                        ),
                        ListRow(
                          icon: Icons.favorite_outline_rounded,
                          title: 'الممرضون المفضلون',
                          subtitle: 'كوادر تمريضية تفضل التعامل معها',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => FavoriteNursesScreen(api: session.api),
                            ),
                          ),
                        ),
                        ListRow(
                          icon: Icons.calendar_month_outlined,
                          title: 'خطط الرعاية المستمرة',
                          subtitle: 'متابعة الزيارات الدورية المجدولة',
                          divider: false,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => CarePlansScreen(api: session.api),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SectionTitle('المالية والعروض'),
                  TamCard(
                    child: Column(
                      children: [
                        ListRow(
                          icon: Icons.receipt_long_outlined,
                          title: 'طلباتي وفواتيري',
                          subtitle: 'سجل الزيارات والفواتير المستحقة',
                          onTap: () => PatientRouter.switchTab(1),
                        ),
                        ListRow(
                          icon: Icons.account_balance_wallet_outlined,
                          title: 'المحفظة وطرق الدفع',
                          subtitle: 'معلومات الدفع النقدي المعتمدة',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => PatientWalletScreen(session: session),
                            ),
                          ),
                        ),
                        ListRow(
                          icon: Icons.card_giftcard_outlined,
                          title: 'ادعُ صديقاً واكسب خصماً',
                          subtitle: 'شارك رمز دعوتك الترويجي',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ReferralScreen(session: session),
                            ),
                          ),
                        ),
                        ListRow(
                          icon: Icons.verified_outlined,
                          title: 'سجل الالتزام بالمواعيد',
                          subtitle: 'متابعة الإلغاءات والاعتراضات',
                          divider: false,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => CommitmentScreen(api: session.api),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SectionTitle('تفعيل رمز خصم'),
                  TamCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _promoCtrl,
                                textCapitalization: TextCapitalization.characters,
                                decoration: InputDecoration(
                                  hintText: 'أدخل رمز الخصم',
                                  isDense: true,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () async {
                                try {
                                  final msg = await session.finance.claimPromoCode(_promoCtrl.text);
                                  if (mounted) setState(() => _promoResult = msg);
                                } catch (e) {
                                  if (mounted) {
                                    setState(() => _promoResult = explainError(e, fallback: 'رمز غير صالح'));
                                  }
                                }
                              },
                              child: const Text('حفظ'),
                            ),
                          ],
                        ),
                        if (_promoResult != null) ...[
                          const SizedBox(height: 8),
                          Text(_promoResult!, style: aeroText(size: 12.5, color: tc.primary)),
                        ],
                      ],
                    ),
                  ),
                  const SectionTitle('المظهر وسهولة القراءة'),
                  TamCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('السمة', style: aeroText(size: 13.5, weight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        ValueListenableBuilder<ThemeMode>(
                          valueListenable: session.themeMode,
                          builder: (context, mode, _) => SegmentedButton<ThemeMode>(
                            segments: const [
                              ButtonSegment(value: ThemeMode.light, label: Text('فاتح')),
                              ButtonSegment(value: ThemeMode.dark, label: Text('داكن')),
                              ButtonSegment(value: ThemeMode.system, label: Text('النظام')),
                            ],
                            selected: {mode},
                            onSelectionChanged: (s) => session.setThemeMode(s.first),
                          ),
                        ),
                        const SizedBox(height: 12),
                        ValueListenableBuilder<double>(
                          valueListenable: session.textScaleFactor,
                          builder: (context, scale, _) => Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('حجم الخط (${(scale * 100).round()}%)',
                                  style: aeroText(size: 13, weight: FontWeight.w700)),
                              Slider(
                                min: 0.95,
                                max: 1.4,
                                divisions: 9,
                                value: scale,
                                onChanged: session.setTextScale,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SectionTitle('الأمان والإشعارات والحساب'),
                  TamCard(
                    child: Column(
                      children: [
                        ListRow(
                          icon: Icons.notifications_none_rounded,
                          title: 'سجل الإشعارات',
                          subtitle: 'جميع التنبيهات وتحديثات الطلبات',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => PatientNotificationsScreen(session: session),
                            ),
                          ),
                        ),
                        ListRow(
                          icon: Icons.contacts_outlined,
                          title: 'جهات الاتصال الموثوقة',
                          subtitle: 'مشاركة السلامة في حالات الطوارئ',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => TrustedContactsScreen(api: session.api),
                            ),
                          ),
                        ),
                        ListRow(
                          icon: Icons.local_hospital_outlined,
                          title: 'أرقام الطوارئ المعتمدة',
                          subtitle: 'الإسعاف والدعم والجهات الرسمية',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => EmergencyDirectoryScreen(api: session.api),
                            ),
                          ),
                        ),
                        ListRow(
                          icon: Icons.lock_outline_rounded,
                          title: 'تغيير كلمة المرور',
                          subtitle: 'تحديث بيانات أمان الحساب',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ChangePasswordScreen(
                                api: session.api,
                                onDone: () => Navigator.of(context).maybePop(),
                                onLogout: () async {
                                  await session.signOut();
                                  PatientRouter.switchTab(0);
                                },
                              ),
                            ),
                          ),
                        ),
                        ListenableBuilder(
                          listenable: session,
                          builder: (context, _) => SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: Text('إشعارات العروض والنصائح الصحية',
                                style: aeroText(size: 14, weight: FontWeight.w700)),
                            value: session.marketingOptIn,
                            onChanged: session.setMarketingConsent,
                          ),
                        ),
                        const Divider(),
                        ListRow(
                          icon: Icons.logout_rounded,
                          title: 'تسجيل الخروج',
                          subtitle: 'إلغاء ربط الجهاز بهذه الجلسة بأمان',
                          divider: false,
                          onTap: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('تسجيل الخروج'),
                                content: const Text('هل تريد تسجيل الخروج من هذا الجهاز؟'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(ctx).pop(false),
                                    child: const Text('إلغاء'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.of(ctx).pop(true),
                                    child: Text('تسجيل الخروج', style: TextStyle(color: tc.danger)),
                                  ),
                                ],
                              ),
                            );
                            if (ok == true) {
                              await session.signOut();
                              PatientRouter.switchTab(0);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
