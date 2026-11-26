import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../alarm.dart';
import '../core/nurse_session_coordinator.dart';
import '../features/profile/nurse_onboarding_gate.dart';
import 'nurse_router.dart';
import 'nurse_shell.dart';

class TamreedyNurseApp extends StatefulWidget {
  final NurseSessionCoordinator? sessionOverride;

  const TamreedyNurseApp({super.key, this.sessionOverride});

  @override
  State<TamreedyNurseApp> createState() => _TamreedyNurseAppState();
}

class _TamreedyNurseAppState extends State<TamreedyNurseApp> {
  late final NurseSessionCoordinator _session;
  late final bool _ownsSession;

  @override
  void initState() {
    super.initState();
    _ownsSession = widget.sessionOverride == null;
    _session = widget.sessionOverride ?? NurseSessionCoordinator();
    _session.onRouteTarget = (target) {
      NurseRouter.handleNotificationTarget(_session, target);
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
          title: 'تمريضي — بوابة الكوادر التمريضية',
          debugShowCheckedModeBanner: false,
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: tamreedyLightTheme(),
          darkTheme: tamreedyDarkTheme(),
          themeMode: mode,
          navigatorKey: NurseRouter.navigatorKey,
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
            role: 'NURSE',
            child: (_) => NurseApprovalGate(
              api: _session.api,
              onLogout: () async {
                await _session.signOut();
                if (mounted) setState(() {});
              },
              child: (_) => OnSessionStart(
                onStart: _session.initAuthenticatedSession,
                child: RealtimeHost(
                  api: _session.api,
                  eventBus: _session.eventBus,
                  coordinator: _session.notifications,
                  onForegroundPush: (data) => OfferAlarm.handle(data),
                  onResync: _session.resyncAll,
                  child: NurseShell(session: _session),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
