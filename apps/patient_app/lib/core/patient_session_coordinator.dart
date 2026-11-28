import 'dart:async';
import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../features/booking/booking_draft_store.dart';
import '../features/catalog/catalog_store.dart';
import '../features/communication/conversations_store.dart';
import '../features/finance/finance_store.dart';
import '../features/requests/requests_store.dart';
import '../patient_alarm.dart';
import '../app/patient_router.dart';

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
  int _sessionGeneration = 0;
  bool _signingOut = false;
  SessionInitState _initState = SessionInitState.idle;
  String? _initError;
  ServerCapabilities capabilities = const ServerCapabilities(
    scheduledVisitsEnabled: kDemoMode,
  );
  bool marketingOptIn = false;

  SessionInitState get initState => _initState;
  String? get initError => _initError;

  void Function(NotificationRouteTarget target)? onRouteTarget;

  PatientSessionCoordinator() {
    api = TamreedyApi(appType: 'PATIENT_APP');
    api.authSessionSignal.addListener(_onAuthSessionSignal);
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

    // BUG-042: Targeted Invalidation Matrix — filter out high-frequency telemetry / WebRTC signals.
    _notifSub = eventBus.stream.listen((ev) {
      const highFreqNonNotif = {
        'tracking.updated',
        'call.signal',
        'location.ack',
        'location.rejected',
        'pong',
      };
      if (!highFreqNonNotif.contains(ev.type)) {
        unreadNotifications.value = unreadNotifications.value + 1;
      }
      final callId =
          ev.payload['callId']?.toString() ?? ev.payload['call_id']?.toString();
      final reqId =
          ev.payload['requestId']?.toString() ??
          ev.payload['request_id']?.toString();
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

  /// BUG-046: Staged startup (Critical -> Deferred -> On-Demand) with explicit SessionInitState & retry support.
  Future<void> initAuthenticatedSession() async {
    if (_signingOut || _initialized || _initState == SessionInitState.loading) {
      return;
    }
    final generation = _sessionGeneration;
    _initState = SessionInitState.loading;
    _initError = null;
    notifyListeners();

    try {
      final userId = await api.currentUserId();
      if (generation != _sessionGeneration) return;
      if (userId == null || userId.isEmpty) {
        throw StateError('Authenticated user required');
      }
      notifications.setAuthenticatedUserId(userId);
      await bookingDraft.restoreDraft();
      if (generation != _sessionGeneration) return;
      unawaited(PatientAlarm.requestPermissions());

      // Critical path: server capabilities, catalog, active/recent requests, and active calls only
      final criticalErrors = <Object>[];
      await Future.wait([
        loadCapabilities().catchError((Object error) {
          criticalErrors.add(error);
        }),
        catalog.load().catchError((Object e) {
          criticalErrors.add(e);
        }),
        requests.refreshAll().catchError((Object e) {
          criticalErrors.add(e);
        }),
      ]);

      if (generation != _sessionGeneration) return;
      await callManager.checkActiveCalls(
        defaultPeerName:
            requests.primaryActiveRequest?.nurseName ?? 'الممرض المعتمد',
        defaultPeerRole: 'ممرض مرخص',
      );

      if (generation != _sessionGeneration) return;
      _initialized = true;
      _initState = criticalErrors.isEmpty
          ? SessionInitState.ready
          : SessionInitState.partial;
      if (criticalErrors.isNotEmpty) {
        _initError = explainError(
          criticalErrors.first,
          fallback: 'تم التحميل الجزئي؛ اسحب للتحديث',
        );
      }
      notifyListeners();

      // Deferred path: background hydration without blocking initial UI interactivity
      unawaited(
        Future.wait<void>([
          bookingDraft.loadBeneficiaries().catchError((_) {}),
          bookingDraft.loadSavedPlaces().catchError((_) {}),
          bookingDraft.loadRegions().catchError((_) {}),
          conversations.loadConversations().catchError((_) {}),
          finance.loadReferral().catchError((_) {}),
          refreshUnreadNotifications().catchError((_) {}),
          loadMarketingConsent().catchError((_) {}),
        ]),
      );

      final pending = notifications.takePendingColdStartTarget();
      if (pending != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (generation == _sessionGeneration) onRouteTarget?.call(pending);
        });
      }
    } catch (e) {
      if (generation != _sessionGeneration) return;
      _initState = SessionInitState.failed;
      _initError = explainError(e, fallback: 'تعذر تهيئة الجلسة');
      notifyListeners();
    }
  }

  Future<void> retryInit() async {
    _initialized = false;
    await initAuthenticatedSession();
  }

  Future<void> loadCapabilities() async {
    final generation = _sessionGeneration;
    if (kDemoMode) {
      capabilities = const ServerCapabilities(scheduledVisitsEnabled: true);
      bookingDraft.updateCapabilities(capabilities);
      return;
    }
    try {
      final raw = await api.getMap('/v1/capabilities');
      if (generation != _sessionGeneration) return;
      capabilities = ServerCapabilities.fromJson(raw);
      bookingDraft.updateCapabilities(capabilities);
      notifyListeners();
    } catch (error) {
      if (generation != _sessionGeneration) return;
      capabilities = const ServerCapabilities(
        ordersAccepting: false,
        openMarketplaceEnabled: false,
        pausedMessage:
            'تعذر التحقق من إعدادات استقبال الطلبات. حدّث الحالة لإعادة المحاولة.',
      );
      bookingDraft.updateCapabilities(capabilities);
      _initError = explainError(error, fallback: 'تعذر تحميل إعدادات التشغيل');
      notifyListeners();
      rethrow;
    }
  }

  Future<void> resyncAll() async {
    await Future.wait([
      loadCapabilities(),
      requests.refreshAll(silent: true),
      conversations.loadConversations(silent: true),
      refreshUnreadNotifications(),
      callManager.checkActiveCalls(
        defaultPeerName:
            requests.primaryActiveRequest?.nurseName ?? 'الممرض المعتمد',
        defaultPeerRole: 'ممرض مرخص',
      ),
    ]);
  }

  Future<void> refreshUnreadNotifications() async {
    final generation = _sessionGeneration;
    if (kDemoMode) return;
    try {
      final res = await api.getMap('/v1/notifications?unreadOnly=true&limit=1');
      if (generation != _sessionGeneration) return;
      final unread = res['unreadCount'] ?? res['unread_count'];
      if (unread != null) {
        unreadNotifications.value = (num.tryParse('$unread') ?? 0).toInt();
      } else if (res['items'] is List) {
        unreadNotifications.value = (res['items'] as List).length;
      }
    } catch (_) {}
  }

  Future<void> loadMarketingConsent() async {
    final generation = _sessionGeneration;
    if (kDemoMode) return;
    try {
      final res = await api.getMap('/v1/me/marketing-consent');
      if (generation != _sessionGeneration) return;
      marketingOptIn = res['optIn'] == true;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setMarketingConsent(bool optIn) async {
    final generation = _sessionGeneration;
    final prev = marketingOptIn;
    marketingOptIn = optIn;
    notifyListeners();
    if (kDemoMode) return;
    try {
      await api.put('/v1/me/marketing-consent', {'optIn': optIn});
    } catch (_) {
      if (generation != _sessionGeneration) return;
      marketingOptIn = prev;
      notifyListeners();
    }
  }

  void _onAuthSessionSignal() {
    if (_signingOut || api.authSessionSignal.value == null) return;
    _clearAccountState();
    unawaited(
      callManager.resetForSessionChange().catchError((Object error) {
        _initError = explainError(
          error,
          fallback: 'تعذر إغلاق المكالمة السابقة',
        );
        notifyListeners();
      }),
    );
    notifyListeners();
  }

  void _clearAccountState() {
    _sessionGeneration++;
    _initialized = false;
    _initState = SessionInitState.idle;
    _initError = null;
    unreadNotifications.value = 0;
    marketingOptIn = false;
    notifications.setAuthenticatedUserId(null);
    notifications.clearHistory();
    bookingDraft.resetForSessionChange();
    requests.resetForSessionChange();
    conversations.resetForSessionChange();
    finance.resetForSessionChange();
    capabilities = const ServerCapabilities(
      ordersAccepting: false,
      openMarketplaceEnabled: false,
    );
    PatientRouter.currentTab.value = 0;
    PatientRouter.nav?.popUntil((route) => route.isFirst);
  }

  Future<void> signOut() async {
    if (_signingOut) return;
    _signingOut = true;
    api.beginSessionChange();
    _clearAccountState();
    try {
      await callManager.resetForSessionChange();
      await api.logout();
    } finally {
      _signingOut = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    api.authSessionSignal.removeListener(_onAuthSessionSignal);
    _sessionGeneration++;
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
