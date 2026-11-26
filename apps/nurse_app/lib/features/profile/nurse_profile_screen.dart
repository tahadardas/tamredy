import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../../alarm.dart';
import '../../app/nurse_router.dart';
import '../../core/nurse_session_coordinator.dart';
import '../../guardian.dart';
import '../safety/guardian_sheet.dart';
import 'nurse_notifications_screen.dart';

class NurseProfileScreen extends StatelessWidget {
  final NurseSessionCoordinator session;

  const NurseProfileScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;

    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: TamBreakpoints.maxContentWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TamCard(
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 26,
                              backgroundColor: tc.primaryTint,
                              child: Icon(Icons.medical_services_rounded, color: tc.primary),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    session.nurseFullName.isEmpty ? 'الممرض المعتمد' : session.nurseFullName,
                                    style: aeroText(size: 16, weight: FontWeight.w800, color: tc.textPrimary),
                                  ),
                                  Text(
                                    'الترخيص: ${session.profileVerified ? "معتمد" : "قيد المراجعة"} • ⭐ ${session.ratingAvg.toStringAsFixed(1)}',
                                    style: aeroText(size: 12.5, color: tc.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (session.approvedSkills.isNotEmpty) ...[
                        const SectionTitle('الخدمات والمهارات المعتمدة'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final s in session.approvedSkills) StatusChip(s),
                          ],
                        ),
                      ],
                      const SectionTitle('السلامة والتنبيهات'),
                      TamCard(
                        child: Column(
                          children: [
                            ListRow(
                              icon: Icons.notifications_none_rounded,
                              title: 'سجل الإشعارات',
                              subtitle: 'العروض وتحديثات الزيارات والمدفوعات',
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => NurseNotificationsScreen(session: session),
                                ),
                              ),
                            ),
                            ListRow(
                              icon: Icons.volume_up_outlined,
                              title: 'اختبار نغمة التنبيه الفوري',
                              subtitle: 'تجربة صوت الإشعار قبل استقبال الطلبات',
                              onTap: () => OfferAlarm.show(
                                const AlarmData(
                                  'test-alarm',
                                  'اختبار تنبيه الطلبات',
                                  'هكذا سيظهر الصوت والتنبيه عند وصول عرض جديد.',
                                  6,
                                ),
                              ),
                            ),
                            if (guardianEnabled)
                              ListRow(
                                icon: Icons.shield_outlined,
                                title: 'إعدادات الأمان Guardian والعمل الليلي',
                                subtitle: 'جهات الاتصال الموثوقة والمرافقة المهنية',
                                divider: false,
                                onTap: () => openGuardianSheet(context, session),
                              ),
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
                      const SectionTitle('الأمان والحساب'),
                      TamCard(
                        child: Column(
                          children: [
                            ListRow(
                              icon: Icons.lock_outline_rounded,
                              title: 'تغيير كلمة المرور',
                              subtitle: 'تحديث بيانات الدخول بأمان',
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => ChangePasswordScreen(
                                    api: session.api,
                                    onDone: () => Navigator.of(context).maybePop(),
                                    onLogout: () async {
                                      await session.signOut();
                                      NurseRouter.switchTab(0);
                                    },
                                  ),
                                ),
                              ),
                            ),
                            ListRow(
                              icon: Icons.logout_rounded,
                              title: 'تسجيل الخروج',
                              subtitle: 'إيقاف التوفر وفصل الجهاز عن الحساب',
                              divider: false,
                              onTap: () async {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('تسجيل الخروج'),
                                    content: const Text('هل تريد تسجيل الخروج من تطبيق الممرض؟'),
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
                                  NurseRouter.switchTab(0);
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
          );
        },
      ),
    );
  }
}
