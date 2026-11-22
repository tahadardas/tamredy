import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../alarm.dart';
import '../controller.dart';

/// N01 — dashboard / availability.
class NurseHomeScreen extends StatelessWidget {
  final NurseController c;
  final TamBottomNav nav;
  const NurseHomeScreen({super.key, required this.c, required this.nav});

  @override
  Widget build(BuildContext context) => TamScaffold(
    title: 'لوحة الممرض',
    subtitle: 'الاستعداد لاستقبال الطلبات',
    nav: nav,
    children: [
      HeroCard(
        title: c.available ? 'أنت متاح الآن ●' : 'أنت غير متاح',
        body: 'تصلك فقط الطلبات المناسبة لاختصاصك والقريبة من موقعك.',
        trailing: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Switch(
            value: c.available,
            onChanged: c.setAvailable,
            activeThumbColor: Colors.white,
            activeTrackColor: TamreedyColors.tealAlt,
          ),
        ),
      ),
      if (c.error != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            c.error!,
            style: tamText(size: 12, color: TamreedyColors.danger),
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
      const SectionTitle('آخر نشاط'),
      TamCard(
        child: Column(
          children: [
            for (var i = 0; i < 2; i++)
              ListRow(
                icon: Icons.check,
                title: i == 0 ? 'زيارة رعاية منزلية' : 'زيارة متابعة',
                subtitle: i == 0
                    ? 'اليوم • انتهت بنجاح'
                    : 'الأمس • انتهت بنجاح',
                trailing: const StatusChip('مكتملة'),
                divider: i == 0,
              ),
          ],
        ),
      ),
      const SectionTitle('التوفر والموقع'),
      TamCard(
        child: ListRow(
          icon: Icons.location_on_outlined,
          title: 'موقعك محدث',
          subtitle: c.available
              ? 'آخر تحديث قبل لحظات'
              : 'فعّل التوفر لمشاركة الموقع',
          trailing: StatusChip(
            c.available ? 'متاح' : 'غير متاح',
            warning: !c.available,
          ),
          divider: false,
        ),
      ),
    ],
  );
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
