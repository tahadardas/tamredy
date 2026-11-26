import 'dart:async';
import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../features/booking/booking_draft_store.dart';
import '../features/catalog/catalog_store.dart';
import '../features/communication/conversations_store.dart';
import '../features/finance/finance_store.dart';
import '../features/requests/requests_store.dart';
import '../patient_alarm.dart';

class PatientSessionCoordinator extends ChangeNotifier {
  late final TamreedyApi api;
  late final RealtimeEventBus eventBus;
  late final NotificationCoordinator notifications;
  late final CallManager callManager;
  late final CatalogStore catalog;
  late final BookingDraftStore bookingDraft;
  late final RequestsStore requests;
  late final ConversationsStore conversations;
  late final FinanceStore finance;

  final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.light);
  final ValueNotifier<double> textScaleFactor = ValueNotifier(1.0);
  final ValueNotifier<int> unreadNotifications = ValueNotifier(0);

  StreamSubscription<RealtimeEvent>? _notifSub;
  StreamSubscription<NotificationRouteTarget>? _routeSub;
  bool _initialized = false;
  bool marketingOptIn = false;

  void Function(NotificationRouteTarget target)? onRouteTarget;

  PatientSessionCoordinator() {
    api = TamreedyApi(appType: 'PATIENT_APP');
    eventBus = RealtimeEventBus();
    notifications = NotificationCoordinator(
      expectedRole: 'PATIENT',
      expectedApp: 'PATIENT_APP',
    );
    callManager = CallManager(api: api, eventBus: eventBus);
    catalog = CatalogStore(api: api);
    bookingDraft = BookingDraftStore(api: api, catalog: catalog);
    requests = RequestsStore(api: api, eventBus: eventBus);
    conversations = ConversationsStore(api: api, eventBus: eventBus);
    finance = FinanceStore(api: api);

    PatientAlarm.coordinator = notifications;

    _notifSub = eventBus.stream.listen((ev) {
      if (ev.type != 'tracking.updated') {
        unreadNotifications.value = unreadNotifications.value + 1;
      }
      final callId = ev.payload['callId']?.toString() ?? ev.payload['call_id']?.toString();
      final reqId = ev.payload['requestId']?.toString() ?? ev.payload['request_id']?.toString();
      if (ev.type == 'call.incoming' && callId != null && callId.isNotEmpty) {
        callManager.presentIncoming(
          callId: callId,
          requestId: reqId ?? '',
          peerName: ev.payload['callerName']?.toString() ?? 'الممرض المعتمد',
          peerRole: 'ممرض مرخص',
        );
      }
    });

    _routeSub = notifications.onRouteTarget.listen((target) {
      onRouteTarget?.call(target);
    });
  }

  Future<void> restorePreferences() async {
    try {
      final modeStr = await api.readLocal('patient_theme_mode');
      if (modeStr == 'dark') {
        themeMode.value = ThemeMode.dark;
      } else if (modeStr == 'system') {
        themeMode.value = ThemeMode.system;
      } else {
        themeMode.value = ThemeMode.light;
      }
      final scaleStr = await api.readLocal('patient_text_scale');
      final parsedScale = double.tryParse(scaleStr ?? '');
      if (parsedScale != null && parsedScale >= 0.9 && parsedScale <= 1.6) {
        textScaleFactor.value = parsedScale;
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
    await api.writeLocal('patient_theme_mode', val);
  }

  Future<void> setTextScale(double scale) async {
    final clamped = scale.clamp(0.95, 1.45);
    textScaleFactor.value = clamped;
    await api.writeLocal('patient_text_scale', clamped.toStringAsFixed(2));
  }

  Future<void> initAuthenticatedSession() async {
    if (_initialized) return;
    _initialized = true;
    await bookingDraft.restoreDraft();
    await PatientAlarm.requestPermissions();

    await Future.wait([
      catalog.load(),
      requests.refreshAll(),
      bookingDraft.loadBeneficiaries(),
      bookingDraft.loadSavedPlaces(),
      bookingDraft.loadRegions(),
      conversations.loadConversations(),
      finance.loadReferral(),
      refreshUnreadNotifications(),
      loadMarketingConsent(),
    ]);

    await callManager.checkActiveCalls(
      defaultPeerName: requests.primaryActiveRequest?.nurseName ?? 'الممرض المعتمد',
      defaultPeerRole: 'ممرض مرخص',
    );

    final pending = notifications.takePendingColdStartTarget();
    if (pending != null) {
      Future<void>.delayed(const Duration(milliseconds: 250), () {
        onRouteTarget?.call(pending);
      });
    }
  }

  Future<void> resyncAll() async {
    await Future.wait([
      requests.refreshAll(silent: true),
      conversations.loadConversations(silent: true),
      refreshUnreadNotifications(),
      callManager.checkActiveCalls(
        defaultPeerName: requests.primaryActiveRequest?.nurseName ?? 'الممرض المعتمد',
        defaultPeerRole: 'ممرض مرخص',
      ),
    ]);
  }

  Future<void> refreshUnreadNotifications() async {
    if (kDemoMode) return;
    try {
      final res = await api.getMap('/v1/notifications?unreadOnly=true&limit=1');
      final unread = res['unreadCount'] ?? res['unread_count'];
      if (unread != null) {
        unreadNotifications.value = (num.tryParse('$unread') ?? 0).toInt();
      } else if (res['items'] is List) {
        unreadNotifications.value = (res['items'] as List).length;
      }
    } catch (_) {}
  }

  Future<void> loadMarketingConsent() async {
    if (kDemoMode) return;
    try {
      final res = await api.getMap('/v1/me/marketing-consent');
      marketingOptIn = res['optIn'] == true;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setMarketingConsent(bool optIn) async {
    final prev = marketingOptIn;
    marketingOptIn = optIn;
    notifyListeners();
    if (kDemoMode) return;
    try {
      await api.put('/v1/me/marketing-consent', {'optIn': optIn});
    } catch (_) {
      marketingOptIn = prev;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    _initialized = false;
    await api.logout();
    await bookingDraft.clearDraft();
    unreadNotifications.value = 0;
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    _routeSub?.cancel();
    callManager.dispose();
    catalog.dispose();
    bookingDraft.dispose();
    requests.dispose();
    conversations.dispose();
    finance.dispose();
    themeMode.dispose();
    textScaleFactor.dispose();
    unreadNotifications.dispose();
    super.dispose();
  }
}
