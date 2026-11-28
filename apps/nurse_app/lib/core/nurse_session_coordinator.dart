import 'dart:async';
import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../alarm.dart';
import '../app/nurse_router.dart';
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
  double? ratingAvg;
  List<String> approvedSkills = const [];
  ServerCapabilities? capabilities;
  bool capabilitiesLoading = false;
  String? capabilitiesError;
  int _capabilitiesGeneration = 0;

  bool get canUseOpenMarketplace =>
      !capabilitiesLoading &&
      capabilitiesError == null &&
      capabilities?.openMarketplaceEnabled == true;

  StreamSubscription<RealtimeEvent>? _evSub;
  StreamSubscription<NotificationRouteTarget>? _routeSub;
  void Function(NotificationRouteTarget target)? onRouteTarget;
  bool _initialized = false;
  bool _signingOut = false;
  int _sessionGeneration = 0;
  int _initGeneration = 0;
  SessionInitState _initState = SessionInitState.idle;
  String? _initError;

  SessionInitState get initState => _initState;
  String? get initError => _initError;

  NurseSessionCoordinator({TamreedyApi? apiOverride}) {
    api = apiOverride ?? TamreedyApi(appType: 'NURSE_APP');
    api.authSessionSignal.addListener(_onAuthSessionSignal);
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
    marketplace = MarketplaceStore(
      api: api,
      eventBus: eventBus,
      canUseOpenMarketplace: () => canUseOpenMarketplace,
    );
    calendar = CalendarStore(api: api);
    finance = NurseFinanceStore(api: api);

    OfferAlarm.coordinator = notifications;

    // BUG-042: Targeted Invalidation Matrix — ignore high-frequency telemetry/WebRTC signals.
    _evSub = eventBus.stream.listen((ev) {
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
      if (ev.type.startsWith('safety.') && guardianEnabled) {
        if (ev.type == 'safety.event_changed') {
          guardian.refreshSos();
        } else {
          guardian.refreshSession();
        }
      } else if (ev.type == 'payment.paid' ||
          ev.type == 'payment.partially_paid' ||
          ev.type == 'payment.tip') {
        finance.refresh();
      } else if (ev.type == 'visit.complete') {
        finance.refresh();
      } else if (ev.type == 'call.incoming') {
        final callId =
            ev.payload['callId']?.toString() ??
            ev.payload['call_id']?.toString();
        final reqId =
            ev.payload['requestId']?.toString() ??
            ev.payload['request_id']?.toString();
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

  /// BUG-046: Staged startup (Critical -> Deferred -> On-Demand) with explicit SessionInitState & retry support.
  Future<void> initAuthenticatedSession() async {
    if (_signingOut || _initialized || _initState == SessionInitState.loading) {
      return;
    }
    final session = _sessionGeneration;
    final init = ++_initGeneration;
    bool current() => session == _sessionGeneration && init == _initGeneration;
    _initState = SessionInitState.loading;
    _initError = null;
    notifyListeners();

    try {
      final userId = await api.currentUserId();
      if (!current()) return;
      if (userId == null || userId.isEmpty) {
        throw StateError('AUTHENTICATED_USER_REQUIRED');
      }
      notifications.setAuthenticatedUserId(userId);
      unawaited(OfferAlarm.requestPermissions());

      if (guardianEnabled) {
        unawaited(guardian.restoreSos().catchError((_) {}));
        unawaited(guardian.location.sync().catchError((_) {}));
      }

      // Critical path: nurse profile + active visit + open offers / availability
      final criticalErrors = <Object>[];
      await Future.wait([
        loadCapabilities(),
        loadProfile().catchError((Object e) {
          criticalErrors.add(e);
        }),
        visit.restoreActiveAssignment().catchError((Object e) {
          criticalErrors.add(e);
        }),
      ]);

      if (!current()) return;
      if (!visit.hasActiveWork) {
        await Future.wait([
          offers.fetchOpenOffers().catchError((_) {}),
          availability.restoreSavedIntent().catchError((_) {}),
        ]);
      }

      if (!current()) return;
      await callManager.checkActiveCalls(
        defaultPeerName: visit.patientName ?? 'المريض',
        defaultPeerRole: 'المريض / المستفيد',
      );

      if (!current()) return;
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

      // Deferred path: financial summary, open marketplace board, calendar, unread badge
      unawaited(
        Future.wait<void>([
          finance.refresh().catchError((_) {}),
          marketplace.refreshAll().catchError((_) {}),
          calendar.load().catchError((_) {}),
          refreshUnreadNotifications().catchError((_) {}),
        ]),
      );

      final pending = notifications.takePendingColdStartTarget();
      if (pending != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (current()) onRouteTarget?.call(pending);
        });
      }
    } catch (e) {
      if (!current()) return;
      _initState = SessionInitState.failed;
      _initError = explainError(e, fallback: 'تعذر تهيئة جلسة الممرض');
      notifyListeners();
    }
  }

  Future<void> retryInit() async {
    _initialized = false;
    await initAuthenticatedSession();
  }

  Future<void> resyncAll() async {
    await Future.wait([
      loadCapabilities(),
      visit.restoreActiveAssignment(),
      offers.fetchOpenOffers(),
      finance.refresh(),
      refreshUnreadNotifications(),
      if (availability.intentAvailable && !visit.hasActiveWork)
        availability.syncNow(),
      callManager.checkActiveCalls(
        defaultPeerName: visit.patientName ?? 'المريض',
        defaultPeerRole: 'المريض / المستفيد',
      ),
    ]);
  }

  Future<void> loadCapabilities() async {
    final session = _sessionGeneration;
    final generation = ++_capabilitiesGeneration;
    capabilitiesLoading = true;
    capabilitiesError = null;
    notifyListeners();
    try {
      final raw = await api.getMap('/v1/capabilities');
      if (session != _sessionGeneration ||
          generation != _capabilitiesGeneration) {
        return;
      }
      capabilities = ServerCapabilities.fromJson(raw);
    } catch (error) {
      if (session != _sessionGeneration ||
          generation != _capabilitiesGeneration) {
        return;
      }
      capabilities = null;
      capabilitiesError = explainError(
        error,
        fallback: 'تعذر التحقق من إتاحة السوق المفتوح؛ أعد المحاولة',
      );
    } finally {
      if (session == _sessionGeneration &&
          generation == _capabilitiesGeneration) {
        capabilitiesLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadProfile() async {
    final session = _sessionGeneration;
    if (kDemoMode) {
      profileVerified = true;
      nurseFullName = 'سارة أحمد';
      nurseNumber = 'RN-2041';
      ratingAvg = 4.9;
      approvedSkills = const [
        'الحقن والوريد',
        'العناية بالجروح',
        'العلامات الحيوية',
      ];
      notifyListeners();
      return;
    }
    try {
      final p = await api.getMap('/v1/nurse/me/profile');
      if (session != _sessionGeneration) return;
      profileVerified = p['verified'] == true;
      nurseFullName =
          p['full_name']?.toString() ?? p['name']?.toString() ?? nurseFullName;
      nurseNumber =
          p['nurse_no']?.toString() ?? p['nurseNo']?.toString() ?? nurseNumber;
      ratingAvg = num.tryParse('${p['rating_avg'] ?? ''}')?.toDouble();
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
    final session = _sessionGeneration;
    if (kDemoMode) return;
    try {
      final res = await api.getMap('/v1/notifications?unreadOnly=true&limit=1');
      if (session != _sessionGeneration) return;
      final unread = res['unreadCount'] ?? res['unread_count'];
      if (unread != null) {
        unreadNotifications.value = (num.tryParse('$unread') ?? 0).toInt();
      }
    } catch (_) {}
  }

  void _onAuthSessionSignal() {
    if (_signingOut || api.authSessionSignal.value == null) return;
    unawaited(
      _clearAccountState().catchError((Object error) {
        _initError = explainError(
          error,
          fallback: 'تعذر إغلاق موارد الجلسة السابقة',
        );
        notifyListeners();
      }),
    );
  }

  Future<void> _clearAccountState() async {
    _sessionGeneration++;
    _initGeneration++;
    _capabilitiesGeneration++;
    capabilities = null;
    capabilitiesLoading = false;
    capabilitiesError = null;
    notifications.setAuthenticatedUserId(null);
    _initState = SessionInitState.idle;
    _initError = null;
    NurseRouter.resetForSessionChange();
    _initialized = false;
    profileVerified = kDemoMode;
    nurseFullName = kDemoMode ? 'ممرض تجريبي' : '';
    nurseNumber = '';
    ratingAvg = null;
    approvedSkills = const [];
    unreadNotifications.value = 0;
    guardian.resetForSessionChange();
    final availabilityReset = availability.resetForSessionChange();
    final callReset = callManager.resetForSessionChange();
    offers.resetForSessionChange();
    marketplace.resetForSessionChange();
    calendar.resetForSessionChange();
    finance.resetForSessionChange();
    visit.resetForSessionChange();
    notifications.clearHistory();
    await Future.wait([availabilityReset, callReset]);
    notifyListeners();
  }

  Future<void> signOut() async {
    if (_signingOut) return;
    // Explicit logout requires the approved safe checkout. Forced revocation
    // clears memory while retaining encrypted, owner-scoped SOS recovery.
    if (visit.hasActiveWork ||
        (guardianEnabled &&
            (guardian.sessionId != null ||
                guardian.sosUnconfirmed ||
                (guardian.event != null && !guardian.eventClosed)))) {
      throw StateError(
        'أكمل الزيارة أو مسار الخروج الآمن وحالة السلامة قبل تسجيل الخروج',
      );
    }
    _signingOut = true;
    api.beginSessionChange();
    try {
      await _clearAccountState();
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
    _initGeneration++;
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
