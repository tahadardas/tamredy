import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import 'controller.dart';
import 'screens/home.dart';
import 'screens/history.dart';
import 'screens/wallet.dart';
import 'screens/track.dart';
import 'screens/referral.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Analytics.init(
    appRole: 'patient',
  ); // no-op unless ANALYTICS_ENABLED + Firebase configured
  runApp(TamreedyPatientApp());
}

class TamreedyPatientApp extends StatelessWidget {
  final PatientController controller;
  TamreedyPatientApp({super.key, PatientController? controller})
    : controller = controller ?? PatientController();

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: tamreedyTheme(),
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    builder: (context, child) =>
        Directionality(textDirection: TextDirection.rtl, child: child!),
    home: AuthGate(
      api: controller.api,
      role: 'PATIENT',
      child: (_) => OnSessionStart(
        onStart: controller.loadAll,
        child: RealtimeHost(
          api: controller.api,
          onResync: controller.resync,
          onEvent: controller.onLive,
          child: PatientShell(c: controller),
        ),
      ),
    ),
  );
}

const patientNav = [
  NavItem(Icons.home_outlined, 'الرئيسية'),
  NavItem(Icons.calendar_today_outlined, 'طلباتي'),
  NavItem(Icons.account_balance_wallet_outlined, 'محفظتي'),
  NavItem(Icons.person_outline, 'حسابي'),
];

/// Bottom nav shared by pushed screens: selects a tab and returns to the root.
TamBottomNav patientNavBar(
  BuildContext context,
  PatientController c,
  int index,
) => TamBottomNav(
  items: patientNav,
  index: index,
  onTap: (i) {
    c.setTab(i);
    Navigator.of(context).popUntil((r) => r.isFirst);
  },
);

class PatientShell extends StatelessWidget {
  final PatientController c;
  const PatientShell({super.key, required this.c});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final nav = TamBottomNav(
        items: patientNav,
        index: c.tab,
        onTap: c.setTab,
      );
      switch (c.tab) {
        case 1:
          return c.stage == VisitStage.none
              ? HistoryScreen(c: c, nav: nav)
              : TrackScreen(c: c, nav: nav);
        case 2:
          return WalletScreen(c: c, nav: nav);
        case 3:
          return TamScaffold(
            title: 'حسابي',
            subtitle: 'بياناتك والمستفيدون',
            nav: nav,
            children: [
              TamCard(
                child: Column(
                  children: [
                    ListRow(
                      icon: Icons.person_outline,
                      title: c.beneficiary,
                      subtitle: 'المستفيد الافتراضي',
                    ),
                    ListRow(
                      icon: Icons.logout,
                      title: 'تسجيل الخروج',
                      subtitle: 'الخروج والتبديل لحساب آخر',
                      divider: false,
                      onTap: () async {
                        await c.api.logout();
                        runApp(TamreedyPatientApp());
                      },
                    ),
                  ],
                ),
              ),
              ReferralCard(c: c),
              TamCard(
                child: Row(
                  children: [
                    const Expanded(
                      child: ListRow(
                        icon: Icons.campaign_outlined,
                        title: 'العروض والإشعارات التسويقية',
                        subtitle:
                            'أخبرني بالخصومات والعروض (يمكنك الإيقاف في أي وقت)',
                        divider: false,
                      ),
                    ),
                    Switch(
                      value: c.marketingOptIn,
                      onChanged: c.setConsent,
                      activeThumbColor: TamreedyColors.teal,
                    ),
                  ],
                ),
              ),
            ],
          );
        default:
          return HomeScreen(c: c, nav: nav);
      }
    },
  );
}
