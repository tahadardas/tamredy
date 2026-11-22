import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../alarm.dart';
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
        const SectionTitle('التوفر والموقع الجغرافي'),
        TamCard(
          child: ListRow(
            icon: Icons.location_on_outlined,
            title: c.available ? 'موقعك محدث ومتزامن' : 'موقعك غير متزامن',
            subtitle: c.available
                ? 'يتم تحديث إحداثياتك بانتظام لاستقبال الطلبات القريبة'
                : 'فعّل التوفر ليتمكن النظام من إسناد الطلبات المناسبة لك',
            trailing: StatusChip(
              c.available ? 'متاح' : 'غير متاح',
              warning: !c.available,
            ),
            divider: false,
          ),
        ),
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: active ? const Color(0xFF86EFAC) : const Color(0xFFE2E8F0),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: active ? const Color(0xFF22C55E).withValues(alpha: 0.15) : const Color(0xFF94A3B8).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              active ? Icons.check_circle_outline : Icons.power_settings_new_rounded,
              color: active ? const Color(0xFF16A34A) : const Color(0xFF64748B),
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  active ? 'أنت متاح لاستقبال الطلبات ●' : 'أنت غير متاح حالياً',
                  style: tamText(
                    size: 16,
                    weight: FontWeight.w800,
                    color: active ? const Color(0xFF14532D) : const Color(0xFF334155),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  active
                      ? 'تصلك الطلبات المتوافقة مع تخصصك والقريبة من موقعك'
                      : 'فعّل المفتاح للبدء في استقبال إشعارات الطلبات القريبة',
                  style: tamText(
                    size: 12,
                    color: active ? const Color(0xFF166534) : const Color(0xFF64748B),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: active,
            onChanged: disabled ? null : c.setAvailable,
            activeThumbColor: Colors.white,
            activeTrackColor: const Color(0xFF22C55E),
          ),
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
              'تجربة نغمة الإنذار',
              onPressed: () async {
                await OfferAlarm.requestPermissions().catchError((_) {});
                await OfferAlarm.show(
                  const AlarmData(
                    'test',
                    'تجربة الإنذار',
                    'هكذا يصلك الطلب الجديد',
                    10,
                  ),
                );
              },
            ),
          ],
        ),
      ),
      const SectionTitle('مهارات معتمدة'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: const [
          StatusChip('ضمادات'),
          StatusChip('علامات حيوية'),
          StatusChip('حقن وعلاجات'),
        ],
      ),
    ],
  );
}
