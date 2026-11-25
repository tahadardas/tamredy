import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import 'controller.dart';
import 'patient_alarm.dart';
import 'screens/home.dart';
import 'screens/history.dart';
import 'screens/wallet.dart';
import 'screens/track.dart';
import 'screens/referral.dart';

final ValueNotifier<ThemeMode> patientThemeMode = ValueNotifier(ThemeMode.light);
final GlobalKey<NavigatorState> patientNavigatorKey = GlobalKey<NavigatorState>();
String? _visiblePatientCallId;

Future<void> _openPatientCall(TamreedyApi api, Map<String, dynamic>? event) async {
  final active = await api.getList('/v1/calls/active/mine');
  if (active.isEmpty) return;
  final preferred = event?['callId']?.toString();
  final raw = active.cast<dynamic>().map((e) => Map<String, dynamic>.from(e as Map)).firstWhere(
    (call) => preferred == null || call['id']?.toString() == preferred,
    orElse: () => Map<String, dynamic>.from(active.first as Map),
  );
  final callId = raw['id']?.toString();
  if (callId == null || callId == _visiblePatientCallId) return;
  final navigator = patientNavigatorKey.currentState;
  if (navigator == null) return;
  _visiblePatientCallId = callId;
  await navigator.push(MaterialPageRoute(builder: (_) => TamInAppCallScreen(
    api: api,
    requestId: raw['request_id']?.toString() ?? event?['requestId']?.toString() ?? '',
    peerName: 'الممرض المعتمد',
    peerRole: 'مكالمة تمريضي آمنة',
    incomingCallId: callId,
  )));
  _visiblePatientCallId = null;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Analytics.init(
    appRole: 'patient',
  ); // no-op unless ANALYTICS_ENABLED + Firebase configured
  if (kFcmEnabled && !kIsWeb && await FirebaseBoot.ensure()) {
    FirebaseMessaging.onBackgroundMessage(patientBackgroundHandler);
    FirebaseMessaging.onMessage.listen((m) {
      PatientAlarm.handlePush(m.data);
    });
  }
  runApp(TamreedyPatientApp());
}

class TamreedyPatientApp extends StatelessWidget {
  final PatientController controller;
  TamreedyPatientApp({super.key, PatientController? controller})
    : controller = controller ?? PatientController();

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
    valueListenable: patientThemeMode,
    builder: (context, mode, _) => MaterialApp(
      navigatorKey: patientNavigatorKey,
      debugShowCheckedModeBanner: false,
      theme: tamreedyLightTheme(),
      darkTheme: tamreedyDarkTheme(),
      themeMode: mode,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: AuthGate(
        api: controller.api,
        role: 'PATIENT',
        child: (_) => OnSessionStart(
          onStart: () async {
            PatientAlarm.onTap = () {
              controller.setTab(1);
              controller.resync();
            };
            await PatientAlarm.init();
            await PatientAlarm.requestPermissions();
            await controller.loadAll();
            WidgetsBinding.instance.addPostFrameCallback((_) => _openPatientCall(controller.api, null));
          },
          child: RealtimeHost(
            api: controller.api,
            onResync: controller.resync,
            onEvent: controller.onLive,
            onEventData: (type, payload) {
              controller.onLiveData(type, payload);
              if (type == 'call.incoming') _openPatientCall(controller.api, payload);
            },
            child: PatientShell(c: controller),
          ),
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
          return _PatientProfileScreen(c: c, nav: nav);
        default:
          return HomeScreen(c: c, nav: nav);
      }
    },
  );
}

class _PatientProfileScreen extends StatelessWidget {
  final PatientController c;
  final TamBottomNav nav;
  const _PatientProfileScreen({required this.c, required this.nav});

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    return TamScaffold(
      title: 'حسابي',
      subtitle: 'بياناتك والمستفيدون والإعدادات',
      nav: nav,
      children: [
        TamCard(
          child: Column(
            children: [
              ListRow(
                icon: Icons.person_outline_rounded,
                title: c.beneficiary.isEmpty ? 'حساب المريض' : c.beneficiary,
                subtitle: 'المستفيد الافتراضي',
              ),
              ListRow(
                icon: Icons.logout_rounded,
                title: 'تسجيل الخروج',
                subtitle: 'الخروج والتبديل لحساب آخر',
                tone: Tone.danger,
                divider: false,
                onTap: () async {
                  final ok = await TamDialog.confirm(
                    context,
                    title: 'تسجيل الخروج',
                    message: 'هل تريد تسجيل الخروج من حسابك الحالي؟',
                    confirmLabel: 'خروج',
                    destructive: true,
                  );
                  if (ok == true) {
                    await c.api.logout();
                    runApp(TamreedyPatientApp());
                  }
                },
              ),
            ],
          ),
        ),
        const SectionTitle('المظهر'),
        TamCard(
          child: ValueListenableBuilder<ThemeMode>(
            valueListenable: patientThemeMode,
            builder: (context, mode, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'سمة العرض',
                  style: aeroText(
                    size: 14,
                    weight: FontWeight.w700,
                    color: tc.textPrimary,
                  ),
                ),
                const SizedBox(height: TamSpacing.sm),
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text('فاتح'),
                      icon: Icon(Icons.light_mode_outlined),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text('داكن'),
                      icon: Icon(Icons.dark_mode_outlined),
                    ),
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text('النظام'),
                      icon: Icon(Icons.brightness_auto_outlined),
                    ),
                  ],
                  selected: {mode},
                  onSelectionChanged: (s) => patientThemeMode.value = s.first,
                ),
              ],
            ),
          ),
        ),
        if (!kDemoMode) ...[
          const SectionTitle('السلامة والطوارئ'),
          TamCard(
            child: Column(
              children: [
                ListRow(
                  icon: Icons.contact_phone_outlined,
                  title: 'جهات الاتصال الموثوقة',
                  subtitle: 'إدارة جهات الاتصال في حالات الطوارئ',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => TrustedContactsScreen(api: c.api),
                    ),
                  ),
                ),
                ListRow(
                  icon: Icons.emergency_outlined,
                  title: 'دليل الطوارئ',
                  subtitle: 'أرقام الإسعاف والطوارئ المحلية',
                  tone: Tone.danger,
                  divider: false,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => EmergencyDirectoryScreen(api: c.api),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
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
                activeThumbColor: tc.primary,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
