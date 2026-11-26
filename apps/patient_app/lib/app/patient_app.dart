import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../core/patient_session_coordinator.dart';
import '../patient_alarm.dart';
import 'patient_router.dart';
import 'patient_shell.dart';

class TamreedyPatientApp extends StatefulWidget {
  final PatientSessionCoordinator? sessionOverride;

  const TamreedyPatientApp({super.key, this.sessionOverride});

  @override
  State<TamreedyPatientApp> createState() => _TamreedyPatientAppState();
}

class _TamreedyPatientAppState extends State<TamreedyPatientApp> {
  late final PatientSessionCoordinator _session;
  late final bool _ownsSession;

  @override
  void initState() {
    super.initState();
    _ownsSession = widget.sessionOverride == null;
    _session = widget.sessionOverride ?? PatientSessionCoordinator();
    _session.onRouteTarget = (target) {
      PatientRouter.handleNotificationTarget(_session, target);
    };
    _session.restorePreferences();
  }

  @override
  void dispose() {
    if (_ownsSession) {
      _session.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _session.themeMode,
      builder: (context, mode, _) => ValueListenableBuilder<double>(
        valueListenable: _session.textScaleFactor,
        builder: (context, textScale, _) => MaterialApp(
          title: 'تمريضي — الرعاية التمريضية المنزلية',
          debugShowCheckedModeBanner: false,
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: tamreedyLightTheme(),
          darkTheme: tamreedyDarkTheme(),
          themeMode: mode,
          navigatorKey: PatientRouter.navigatorKey,
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            final effectiveScale = mq.textScaler.scale(1.0) * textScale;
            return Directionality(
              textDirection: TextDirection.rtl,
              child: MediaQuery(
                data: mq.copyWith(
                  textScaler: TextScaler.linear(effectiveScale.clamp(0.85, 2.0)),
                ),
                child: TamGlobalCallOverlay(
                  manager: _session.callManager,
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
            );
          },
          home: AuthGate(
            api: _session.api,
            role: 'PATIENT',
            child: (ctx) => OnSessionStart(
              onStart: _session.initAuthenticatedSession,
              child: RealtimeHost(
                api: _session.api,
                eventBus: _session.eventBus,
                coordinator: _session.notifications,
                onForegroundPush: (data) => PatientAlarm.handlePush(data),
                onResync: _session.resyncAll,
                child: PatientShell(session: _session),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
