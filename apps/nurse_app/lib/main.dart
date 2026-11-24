import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import 'alarm.dart';
import 'controller.dart';
import 'guardian.dart';
import 'screens/guardian.dart';
import 'screens/home.dart';
import 'screens/onboarding.dart';
import 'screens/visit.dart';
import 'screens/earnings.dart';
import 'screens/marketplace.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Analytics.init(
    appRole: 'nurse',
  ); // no-op unless ANALYTICS_ENABLED + Firebase configured
  // New-request alarm: works while the app is open, in the background and closed (FCM data message -> loud insistent alert).
  if (kFcmEnabled && !kIsWeb && await FirebaseBoot.ensure()) {
    FirebaseMessaging.onBackgroundMessage(offerBackgroundHandler);
    FirebaseMessaging.onMessage.listen((m) {
      OfferAlarm.handle(m.data);
    });
  }
  runApp(TamreedyNurseApp());
}

class TamreedyNurseApp extends StatelessWidget {
  final NurseController controller;
  TamreedyNurseApp({super.key, NurseController? controller})
    : controller = controller ?? NurseController();

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
      role: 'NURSE',
      child: (_) => NurseApprovalGate(
        api: controller.api,
        onLogout: () async {
          if (guardianEnabled) controller.guardian.location.stop();
          await controller.api.logout();
          if (guardianEnabled) controller.guardian.dispose();
          runApp(TamreedyNurseApp());
        },
        child: (_) => OnSessionStart(
          onStart: () async {
            if (guardianEnabled) {
              await controller.guardian.restoreSos();
              controller.guardian.location.sync();
            }
            await controller.resync();
          },
          child: RealtimeHost(
            api: controller.api,
            onResync: () async {
              if (guardianEnabled) controller.guardian.location.sync();
              await controller.resync();
            },
            onEvent: controller.onLive,
            onEventData: controller.onLiveData,
            child: NurseShell(c: controller),
          ),
        ),
      ),
    ),
  );
}

const nurseNav = [
  NavItem(Icons.home_outlined, 'الرئيسية'),
  NavItem(Icons.description_outlined, 'الطلبات'),
  NavItem(Icons.account_balance_wallet_outlined, 'أرباحي'),
  NavItem(Icons.person_outline, 'حسابي'),
];

TamBottomNav nurseNavBar(BuildContext context, NurseController c, int index) =>
    TamBottomNav(
      items: nurseNav,
      index: index,
      onTap: (i) {
        c.setTab(i);
        Navigator.of(context).popUntil((r) => r.isFirst);
      },
    );

class NurseShell extends StatefulWidget {
  final NurseController c;
  const NurseShell({super.key, required this.c});

  @override
  State<NurseShell> createState() => _NurseShellState();
}

class _NurseShellState extends State<NurseShell> {
  NurseController get c => widget.c;

  @override
  void dispose() {
    if (guardianEnabled) c.guardian.location.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = _buildTabs();
    if (!guardianEnabled) return content;
    return ColoredBox(
      color: AeroColors.lightCanvas,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: ListenableBuilder(
                listenable: c.guardian.location,
                builder: (context, _) => TextButton.icon(
                  onPressed: () => openGuardian(context, c),
                  icon: const Icon(Icons.health_and_safety_outlined, color: Colors.red),
                  label: Text(c.guardian.location.capturing
                      ? 'السلامة والاستغاثة • تسجيل الموقع جارٍ'
                      : 'السلامة والاستغاثة'),
                ),
              ),
            ),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }

  Widget _buildTabs() => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final nav = TamBottomNav(items: nurseNav, index: c.tab, onTap: c.setTab);
      switch (c.tab) {
        case 1:
          return c.stage == NurseStage.idle
              ? NurseMarketplaceScreen(c: c, nav: nav)
              : VisitFlowScreen(c: c, nav: nav);
        case 2:
          return EarningsScreen(c: c, nav: nav);
        case 3:
          return ProfileScreen(c: c, nav: nav);
        default:
          return c.stage != NurseStage.idle && c.stage != NurseStage.offer
              ? VisitFlowScreen(c: c, nav: nav)
              : NurseHomeScreen(c: c, nav: nav);
      }
    },
  );
}
