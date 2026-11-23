import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../alarm.dart';
import '../availability_manager.dart';
import '../controller.dart';
import '../main.dart';
import 'visit.dart';

/// N01 — dashboard / availability.
class NurseHomeScreen extends StatelessWidget {
  final NurseController c;
  final TamBottomNav nav;
  const NurseHomeScreen({super.key, required this.c, required this.nav});

  @override
  Widget build(BuildContext context) {
    final hasActiveAssignment = c.stage != NurseStage.idle && c.stage != NurseStage.offer;
    final isBlocked = c.dues['blocked'] == true;

    return TamScaffold(
      title: 'لوحة الممرض',
      subtitle: 'إدارة التوفر والزيارات الميدانية',
      nav: nav,
      onRefresh: () => c.loadLive(),
      children: [
        if (isBlocked)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFECACA), width: 1.5),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'استقبال الطلبات موقوف مؤقتاً',
                        style: tamText(size: 15, weight: FontWeight.w800, color: const Color(0xFF991B1B)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'لقد تجاوزت سقف المستحقات النقدية غير الموردة للشركة. يرجى توريد المستحقات لاستئناف استلام الطلبات.',
                        style: tamText(size: 12.5, color: const Color(0xFF7F1D1D), height: 1.5),
                      ),
                      const SizedBox(height: 10),
                      InkWell(
                        onTap: () => c.setTab(2),
                        child: Row(
                          children: [
                            Text(
                              'الانتقال إلى كشف المستحقات والتسويات',
                              style: tamText(size: 13, weight: FontWeight.w800, color: const Color(0xFFDC2626)),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.arrow_back, size: 14, color: Color(0xFFDC2626)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (hasActiveAssignment)
          _ActiveAssignmentBanner(c: c),
        _AvailabilityCard(c: c, disabled: isBlocked || hasActiveAssignment),
        if (c.error != null)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFECACA)),
            ),
            child: Text(
              c.error!,
              style: tamText(size: 12.5, color: TamreedyColors.danger),
            ),
          ),
        Row(
          children: [
            Expanded(child: StatCard('طلبات اليوم', twoDigits(c.todayRequests))),
            const SizedBox(width: 12),
            Expanded(
              child: StatCard('زيارات مكتملة', twoDigits(c.completedVisits)),
            ),
          ],
        ),
        const SectionTitle('حالة الجاهزية والاستقبال الميداني'),
        _ReadinessCard(c: c),
        const SectionTitle('آخر الزيارات المنفذة'),
        TamCard(
          child: Column(
            children: [
              if (c.history.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('لا توجد زيارات سابقة مسجلة.'),
                )
              else
                for (var i = 0; i < c.history.length && i < 2; i++)
                  ListRow(
                    icon: Icons.check_circle_outline,
                    title: c.history[i].title,
                    subtitle: '${c.history[i].date} • انتهت بنجاح',
                    trailing: StatusChip(formatMoney(c.history[i].share)),
                    divider: i == 0 && c.history.length > 1,
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReadinessCard extends StatelessWidget {
  final NurseController c;
  const _ReadinessCard({required this.c});

  @override
  Widget build(BuildContext context) {
    final state = c.readinessState;
    final color = state.color;
    final lastLoc = c.availabilityManager.lastLocationUpdate;
    final lastHb = c.availabilityManager.lastHeartbeat;
    final acc = c.availabilityManager.lastAccuracy;
    final unmet = c.availabilityManager.unmetRequirements;

    String telemetryText = '';
    if (c.available) {
      final hbAge = lastHb != null ? DateTime.now().difference(lastHb).inSeconds : null;
      final locStr = (lastLoc != null || c.availabilityManager.currentPosition != null)
          ? 'الموقع: مسجل ونشط${acc != null ? " (دقة ${acc.round()}م)" : ""}'
          : 'الموقع: جاري التحديد...';
      final hbStr = hbAge != null ? 'النبض: متزامن ($hbAge ث)' : 'النبض: متصل';
      telemetryText = '$locStr • $hbStr';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(state.icon, color: color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            state.label,
                            style: tamText(size: 15, weight: FontWeight.w800, color: color),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            state == NurseReadinessState.ready ? 'جاهز 100%' : 'تنبيه',
                            style: tamText(size: 11, weight: FontWeight.w800, color: color),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      state.description,
                      style: tamText(size: 12.5, color: const Color(0xFF374151), height: 1.45),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (unmet.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final u in unmet)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, size: 14, color: color),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              u,
                              style: tamText(size: 11.5, weight: FontWeight.w600, color: color),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (telemetryText.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.sensors, size: 13, color: TamreedyColors.subtext),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    telemetryText,
                    style: tamText(size: 11, color: TamreedyColors.subtext),
                  ),
                ),
                InkWell(
                  onTap: () => c.availabilityManager.syncNow(),
                  child: Row(
                    children: [
                      const Icon(Icons.refresh, size: 13, color: Color(0xFF2563EB)),
                      const SizedBox(width: 3),
                      Text(
                        'مزامنة فورية',
                        style: tamText(size: 11, weight: FontWeight.w700, color: const Color(0xFF2563EB)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ActiveAssignmentBanner extends StatelessWidget {
  final NurseController c;
  const _ActiveAssignmentBanner({required this.c});

  @override
  Widget build(BuildContext context) {
    String statusLabel;
    Color statusColor;

    switch (c.stage) {
      case NurseStage.enRoute:
        statusLabel = 'في الطريق إلى المريض';
        statusColor = const Color(0xFF2563EB);
        break;
      case NurseStage.arrived:
        statusLabel = 'وصلت إلى الموقع';
        statusColor = const Color(0xFF059669);
        break;
      case NurseStage.inService:
        statusLabel = 'تقديم الرعاية التمريضية جارية';
        statusColor = const Color(0xFF7C3AED);
        break;
      case NurseStage.completed:
        statusLabel = 'اكتملت الزيارة — تحصيل الحساب';
        statusColor = const Color(0xFF0D9488);
        break;
      default:
        statusLabel = 'زيارة نشطة';
        statusColor = TamreedyColors.teal;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withValues(alpha: 0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: statusColor.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => VisitFlowScreen(c: c, nav: nurseNavBar(context, c, 0))),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.directions_walk_rounded, color: statusColor, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                c.serviceTitle,
                                style: tamText(size: 15, weight: FontWeight.w800, color: TamreedyColors.navy),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  'زيارة جارية',
                                  style: tamText(size: 11, weight: FontWeight.w700, color: statusColor),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            statusLabel,
                            style: tamText(size: 12, weight: FontWeight.w600, color: statusColor),
                          ),
                          if (c.patientAddress.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              c.patientAddress,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tamText(size: 11, color: TamreedyColors.subtext),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'متابعة شاشة الزيارة والملاحة',
                        style: tamText(size: 13, weight: FontWeight.w800, color: Colors.white),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.arrow_back_ios_new, size: 13, color: Colors.white),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AvailabilityCard extends StatelessWidget {
  final NurseController c;
  final bool disabled;
  const _AvailabilityCard({required this.c, this.disabled = false});

  @override
  Widget build(BuildContext context) {
    final active = c.available;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: TamreedyColors.deepNavy,
        borderRadius: BorderRadius.circular(TamreedyRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                active ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
                color: active ? const Color(0xFF83E8D0) : Colors.white70,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'استقبال الطلبات',
                  style: tamText(size: 14, weight: FontWeight.w700, color: Colors.white),
                ),
              ),
              Semantics(
                label: 'استقبال طلبات الزيارة',
                child: Switch(
                  value: active,
                  onChanged: disabled ? null : c.setAvailable,
                  activeThumbColor: TamreedyColors.deepNavy,
                  activeTrackColor: const Color(0xFF83E8D0),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            disabled
                ? 'التوفر مقيد حاليًا'
                : active
                    ? 'متاح للطلبات القريبة'
                    : 'غير متاح حاليًا',
            style: tamText(size: 21, weight: FontWeight.w800, color: Colors.white),
          ),
          if (!disabled) ...[
            const SizedBox(height: 4),
            Text(
              active
                  ? 'راجع حالة الجاهزية أدناه إذا لم تصلك العروض.'
                  : 'يمكنك تشغيل الاستقبال عندما تكون مستعدًا للزيارة.',
              style: tamText(size: 12, color: Colors.white70, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }
}

/// N09 — visit history.
class NurseHistoryScreen extends StatelessWidget {
  final NurseController c;
  final TamBottomNav nav;
  const NurseHistoryScreen({super.key, required this.c, required this.nav});

  @override
  Widget build(BuildContext context) => TamScaffold(
    title: 'سجل الزيارات',
    subtitle: 'أرشيف الأعمال السابقة',
    nav: nav,
    children: [
      TamCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'بحث في زياراتي السابقة',
                style: tamText(size: 13, color: TamreedyColors.subtext),
              ),
            ),
            const Icon(Icons.search, color: TamreedyColors.navy),
          ],
        ),
      ),
      const SectionTitle('زيارات مكتملة'),
      TamCard(
        child: Column(
          children: [
            for (var i = 0; i < c.history.length; i++)
              ListRow(
                icon: Icons.check,
                title: c.history[i].title,
                subtitle: c.history[i].date,
                trailing: StatusChip(formatMoney(c.history[i].share)),
                divider: i != c.history.length - 1,
              ),
          ],
        ),
      ),
      const SectionTitle('إحصاءات'),
      const TamCard(
        padding: EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        child: Column(
          children: [
            KeyValueRow('متوسط التقييم', '5 / 4.9'),
            KeyValueRow('نسبة إكمال الزيارات', '96%'),
          ],
        ),
      ),
    ],
  );
}

/// N07 — professional profile.
class ProfileScreen extends StatelessWidget {
  final NurseController c;
  final TamBottomNav nav;
  const ProfileScreen({super.key, required this.c, required this.nav});

  @override
  Widget build(BuildContext context) => TamScaffold(
    title: 'ملفي المهني',
    subtitle: 'هويتي وترخيصي ومهاراتي',
    nav: nav,
    children: [
      TamCard(
        padding: const EdgeInsets.all(26),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            children: [
              const Icon(
                Icons.person_outline,
                size: 44,
                color: TamreedyColors.teal,
              ),
              const SizedBox(height: 18),
              Text(
                'ملف الممرض المعتمد',
                style: tamText(
                  size: 22,
                  weight: FontWeight.w800,
                  color: TamreedyColors.navy,
                ),
              ),
              const SizedBox(height: 18),
              const StatusChip('تم التحقق من الهوية والمؤهلات'),
            ],
          ),
        ),
      ),
      const SectionTitle('الوثائق'),
      TamCard(
        child: Column(
          children: const [
            ListRow(
              icon: Icons.description_outlined,
              title: 'ترخيص مزاولة المهنة',
              subtitle: 'ساري حتى التاريخ المعتمد',
              trailing: StatusChip('معتمد'),
            ),
            ListRow(
              icon: Icons.check,
              title: 'المؤهلات',
              subtitle: 'مطابقة لاختصاص الخدمة',
              trailing: StatusChip('معتمد'),
            ),
            ListRow(
              icon: Icons.phone_outlined,
              title: 'بيانات الاتصال',
              subtitle: 'رقم هاتف موثق',
              trailing: Icon(Icons.arrow_back, color: TamreedyColors.subtext),
              divider: false,
            ),
          ],
        ),
      ),
      const SectionTitle('إنذار الطلبات'),
      TamCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'عند وصول طلب قريب منك يرنّ هاتفك بنغمة تمريضي المميزة لمدة العرض، حتى لو كان التطبيق مغلقًا أو الشاشة مقفلة.',
              style: tamText(
                size: 12,
                color: TamreedyColors.subtext,
                height: 1.7,
              ),
            ),
            const SizedBox(height: 12),
            SoftButton(
              'تجربة نغمة الإنذار والتنبيه',
              onPressed: () async {
                HapticFeedback.heavyImpact();
                await OfferAlarm.requestPermissions().catchError((_) {});
                await OfferAlarm.show(
                  const AlarmData(
                    'test',
                    '🔔 تجربة إنذار طلب جديد',
                    'طلب في دمشق — حقن وريدي وعلاجات (حصتك 20,000 ل.س)',
                    20,
                  ),
                );
                if (context.mounted) {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (ctx) => Container(
                      padding: const EdgeInsets.all(24),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7),
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFFF59E0B), width: 2),
                            ),
                            child: const Icon(Icons.notifications_active, color: Color(0xFFD97706), size: 36),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'تجربة إنذار الطلبات الواردة',
                            style: tamText(size: 18, weight: FontWeight.w800, color: TamreedyColors.navy),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'تم تشغيل صوت الإنذار والاهتزاز، وإرسال إشعار كامل الأهمية إلى شريط الإشعارات.',
                            textAlign: TextAlign.center,
                            style: tamText(size: 13, color: TamreedyColors.subtext, height: 1.5),
                          ),
                          const SizedBox(height: 18),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: TamreedyColors.canvas,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: TamreedyColors.border),
                            ),
                            child: Column(
                              children: [
                                KeyValueRow('المنطقة التجريبية', 'دمشق — المزة فيلات'),
                                KeyValueRow('نوع الخدمة', 'حقن وعلاجات وريدية'),
                                KeyValueRow('حصة الممرض', '20,000 ل.س'),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          PrimaryButton(
                            'إيقاف صوت الإنذار',
                            onPressed: () {
                              OfferAlarm.cancelAll();
                              Navigator.of(ctx).pop();
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
      const SectionTitle('مهاراتي السريرية المعتمدة'),
      if (c.skills.isEmpty)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF3C7).withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(AeroRadii.secondaryCard),
            border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.35)),
            boxShadow: AeroShadows.card,
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.info_outline, color: Color(0xFFD97706), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'لم يتم اعتماد أي مهارات سريرية لك بعد. يرجى مراجعة الإدارة لاعتماد خدماتك لتتمكن من استقبال الطلبات في منطقتك.',
                  style: tamText(size: 12.5, color: const Color(0xFF92400E), height: 1.5),
                ),
              ),
            ],
          ),
        )
      else
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final s in c.skills)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AeroColors.aeroTint.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(AeroRadii.dock),
                  border: Border.all(color: AeroColors.accentTeal.withValues(alpha: 0.3)),
                  boxShadow: AeroShadows.card,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: const BoxDecoration(
                        color: AeroColors.accentTeal,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check, size: 13, color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      s,
                      style: tamText(size: 12.5, weight: FontWeight.w700, color: AeroColors.primaryNavy),
                    ),
                  ],
                ),
              ),
          ],
        ),
    ],
  );
}
