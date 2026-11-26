import 'dart:async';
import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../alarm.dart';
import '../features/availability/availability_store.dart';
import '../features/calendar/calendar_store.dart';
import '../features/finance/nurse_finance_store.dart';
import '../features/marketplace/marketplace_store.dart';
import '../features/offers/offer_store.dart';
import '../features/visit/visit_store.dart';
import '../guardian.dart';

class NurseSessionCoordinator extends ChangeNotifier {
  late final TamreedyApi api;
  late final RealtimeEventBus eventBus;
  late final NotificationCoordinator notifications;
  late final CallManager callManager;
  late final GuardianController guardian;

  late final AvailabilityStore availability;
  late final OfferStore offers;
  late final MarketplaceStore marketplace;
  late final CalendarStore calendar;
  late final NurseFinanceStore finance;
  late final VisitStore visit;

  final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.light);
  final ValueNotifier<double> textScaleFactor = ValueNotifier(1.0);
  final ValueNotifier<int> unreadNotifications = ValueNotifier(0);

  bool profileVerified = kDemoMode;
  String nurseFullName = kDemoMode ? 'ممرض تجريبي' : '';
  String nurseNumber = '';
  double ratingAvg = 5.0;
  List<String> approvedSkills = const [];

  StreamSubscription<RealtimeEvent>? _evSub;
  StreamSubscription<NotificationRouteTarget>? _routeSub;
  void Function(NotificationRouteTarget target)? onRouteTarget;
  bool _initialized = false;

  NurseSessionCoordinator() {
    api = TamreedyApi(appType: 'NURSE_APP');
    eventBus = RealtimeEventBus();
    notifications = NotificationCoordinator(
      expectedRole: 'NURSE',
      expectedApp: 'NURSE_APP',
    );
    callManager = CallManager(api: api, eventBus: eventBus);
    guardian = GuardianController(api);

    availability = AvailabilityStore(
      api: api,
      onOffersReceived: (raw) async => offers.ingestRawOffers(raw),
    );
    visit = VisitStore(
      api: api,
      eventBus: eventBus,
      onActiveAssignmentChanged: availability.setActiveAssignment,
    );
    offers = OfferStore(
      api: api,
      eventBus: eventBus,
      onOfferAccepted: (reqId, assignId) {
        visit.activateFromAcceptedOffer(reqId, assignId);
        finance.refresh();
      },
    );
    marketplace = MarketplaceStore(api: api, eventBus: eventBus);
    calendar = CalendarStore(api: api);
    finance = NurseFinanceStore(api: api);

    OfferAlarm.coordinator = notifications;

    _evSub = eventBus.stream.listen((ev) {
      if (ev.type != 'tracking.updated') {
        unreadNotifications.value = unreadNotifications.value + 1;
      }
      if (ev.type.startsWith('safety.') && guardianEnabled) {
        if (ev.type == 'safety.event_changed') {
          guardian.refreshSos();
        } else {
          guardian.refreshSession();
        }
      } else if (ev.type == 'payment.paid' || ev.type == 'payment.partially_paid' || ev.type == 'payment.tip') {
        finance.refresh();
      } else if (ev.type == 'call.incoming') {
        final callId = ev.payload['callId']?.toString() ?? ev.payload['call_id']?.toString();
        final reqId = ev.payload['requestId']?.toString() ?? ev.payload['request_id']?.toString();
        if (callId != null && callId.isNotEmpty) {
          callManager.presentIncoming(
            callId: callId,
            requestId: reqId ?? '',
            peerName: ev.payload['callerName']?.toString() ?? 'المريض',
            peerRole: 'المريض / المستفيد',
          );
        }
      }
    });

    _routeSub = notifications.onRouteTarget.listen((target) {
      onRouteTarget?.call(target);
    });
  }

  Future<void> restorePreferences() async {
    try {
      final modeStr = await api.readLocal('nurse_theme_mode');
      if (modeStr == 'dark') {
        themeMode.value = ThemeMode.dark;
      } else if (modeStr == 'system') {
        themeMode.value = ThemeMode.system;
      } else {
        themeMode.value = ThemeMode.light;
      }
      final scaleStr = await api.readLocal('nurse_text_scale');
      final parsed = double.tryParse(scaleStr ?? '');
      if (parsed != null && parsed >= 0.9 && parsed <= 1.6) {
        textScaleFactor.value = parsed;
      }
    } catch (_) {}
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode.value = mode;
    final val = switch (mode) {
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
      ThemeMode.light => 'light',
    };
    await api.writeLocal('nurse_theme_mode', val);
  }

  Future<void> setTextScale(double scale) async {
    final clamped = scale.clamp(0.95, 1.45);
    textScaleFactor.value = clamped;
    await api.writeLocal('nurse_text_scale', clamped.toStringAsFixed(2));
  }

  Future<void> initAuthenticatedSession() async {
    if (_initialized) return;
    _initialized = true;
    notifications.setAuthenticatedUserId(await api.currentUserId());
    await OfferAlarm.requestPermissions();

    if (guardianEnabled) {
      await guardian.restoreSos();
      guardian.location.sync();
    }

    await Future.wait([
      loadProfile(),
      visit.restoreActiveAssignment(),
      finance.refresh(),
      marketplace.refreshAll(),
      calendar.load(),
      refreshUnreadNotifications(),
    ]);

    if (!visit.hasActiveWork) {
      await offers.fetchOpenOffers();
      await availability.restoreSavedIntent();
    }

    await callManager.checkActiveCalls(
      defaultPeerName: visit.patientName ?? 'المريض',
      defaultPeerRole: 'المريض / المستفيد',
    );

    final pending = notifications.takePendingColdStartTarget();
    if (pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onRouteTarget?.call(pending);
      });
    }
  }

  Future<void> resyncAll() async {
    await Future.wait([
      visit.restoreActiveAssignment(),
      offers.fetchOpenOffers(),
      finance.refresh(),
      refreshUnreadNotifications(),
      if (availability.intentAvailable && !visit.hasActiveWork) availability.syncNow(),
      callManager.checkActiveCalls(
        defaultPeerName: visit.patientName ?? 'المريض',
        defaultPeerRole: 'المريض / المستفيد',
      ),
    ]);
  }

  Future<void> loadProfile() async {
    if (kDemoMode) {
      profileVerified = true;
      nurseFullName = 'سارة أحمد';
      nurseNumber = 'RN-2041';
      ratingAvg = 4.9;
      approvedSkills = const ['الحقن والوريد', 'العناية بالجروح', 'العلامات الحيوية'];
      notifyListeners();
      return;
    }
    try {
      final p = await api.getMap('/v1/nurse/me/profile');
      profileVerified = p['verified'] == true;
      nurseFullName = p['full_name']?.toString() ?? p['name']?.toString() ?? nurseFullName;
      nurseNumber = p['nurse_no']?.toString() ?? p['nurseNo']?.toString() ?? nurseNumber;
      ratingAvg = (num.tryParse('${p['rating_avg'] ?? 5.0}') ?? 5.0).toDouble();
      if (p['skills'] is List) {
        approvedSkills = (p['skills'] as List)
            .whereType<Map>()
            .map((s) => '${s['title_ar'] ?? ''}'.trim())
            .where((s) => s.isNotEmpty)
            .toList();
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> refreshUnreadNotifications() async {
    if (kDemoMode) return;
    try {
      final res = await api.getMap('/v1/notifications?unreadOnly=true&limit=1');
      final unread = res['unreadCount'] ?? res['unread_count'];
      if (unread != null) {
        unreadNotifications.value = (num.tryParse('$unread') ?? 0).toInt();
      }
    } catch (_) {}
  }

  Future<void> signOut() async {
    _initialized = false;
    profileVerified = kDemoMode;
    nurseFullName = kDemoMode ? 'ممرض تجريبي' : '';
    nurseNumber = '';
    ratingAvg = 5.0;
    approvedSkills = const [];
    unreadNotifications.value = 0;
    if (guardianEnabled) guardian.location.stop();
    await availability.resetForSessionChange();
    await callManager.resetForSessionChange();
    offers.resetForSessionChange();
    marketplace.resetForSessionChange();
    calendar.resetForSessionChange();
    finance.resetForSessionChange();
    visit.resetForSessionChange();
    notifications.clearHistory();
    await api.logout();
    notifyListeners();
  }

  @override
  void dispose() {
    _evSub?.cancel();
    _routeSub?.cancel();
    callManager.dispose();
    availability.dispose();
    offers.dispose();
    marketplace.dispose();
    calendar.dispose();
    finance.dispose();
    visit.dispose();
    if (guardianEnabled) guardian.dispose();
    themeMode.dispose();
    textScaleFactor.dispose();
    unreadNotifications.dispose();
    super.dispose();
  }
}
