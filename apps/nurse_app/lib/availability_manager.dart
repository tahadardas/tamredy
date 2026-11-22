import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:tamreedy_core/tamreedy_core.dart';

enum NurseReadinessState {
  offline,
  connecting,
  locationRequired,
  locationStale,
  verificationRequired,
  skillsRequired,
  settlementBlocked,
  ready,
  busy,
  connectionLost,
}

extension NurseReadinessStateX on NurseReadinessState {
  String get label {
    switch (this) {
      case NurseReadinessState.ready:
        return 'متاح وجاهز لاستقبال الطلبات';
      case NurseReadinessState.locationStale:
      case NurseReadinessState.locationRequired:
        return 'يرجى تحديد الموقع الجغرافي';
      case NurseReadinessState.verificationRequired:
        return 'الترخيص بحاجة إلى اعتماد';
      case NurseReadinessState.skillsRequired:
        return 'لم يتم اعتماد الخدمات التي تستطيع تنفيذها';
      case NurseReadinessState.connectionLost:
        return 'الاتصال بالخادم غير مستقر';
      case NurseReadinessState.settlementBlocked:
        return 'استقبال الطلبات موقوف بسبب التسويات';
      case NurseReadinessState.busy:
        return 'في زيارة ميدانية حالياً';
      case NurseReadinessState.connecting:
        return 'جاري التحقق والاتصال بالخادم...';
      case NurseReadinessState.offline:
        return 'غير متاح لاستقبال الطلبات';
    }
  }

  String get description {
    switch (this) {
      case NurseReadinessState.ready:
        return 'أنت الآن مؤهل وموقعك مسجل بنجاح. ستصلك الطلبات القريبة فور إنشائها مع إنذار صوتي.';
      case NurseReadinessState.locationStale:
      case NurseReadinessState.locationRequired:
        return 'يحتاج النظام لتحديد موقعك الجغرافي مرة واحدة على الأقل لحساب مسافة الوصول وتوزيع الحالات القريبة إليك.';
      case NurseReadinessState.verificationRequired:
        return 'حسابك أو وثيقة مزاولة المهنة بانتظار موافقة الإدارة للتحقق من الأهلية والترخيص.';
      case NurseReadinessState.skillsRequired:
        return 'يجب اعتماد خدمة تمريضية واحدة على الأقل من قبل الإدارة لتتمكن من تلقي عروضها.';
      case NurseReadinessState.connectionLost:
        return 'تعذر إرسال نبض الاتصال بالخادم. جاري إعادة المحاولة تلقائياً عند استقرار الشبكة.';
      case NurseReadinessState.settlementBlocked:
        return 'تم بلوغ سقف المستحقات النقدية غير الموردة. يرجى توريد العهدة النقدية لاستئناف العمل.';
      case NurseReadinessState.busy:
        return 'أنت مرتبط بزيارة نشطة. سيتم استئناف استقبال الطلبات فور إنهاء الزيارة الحالية.';
      case NurseReadinessState.connecting:
        return 'جاري مزامنة الموقع والنبض مع الخادم المركزي والتأكد من الجاهزية...';
      case NurseReadinessState.offline:
        return 'فعّل زر التوفر بالأعلى لبدء إرسال موقعك بانتظام واستقبال العروض الميدانية.';
    }
  }

  Color get color {
    switch (this) {
      case NurseReadinessState.ready:
        return const Color(0xFF059669);
      case NurseReadinessState.busy:
        return const Color(0xFF2563EB);
      case NurseReadinessState.connecting:
        return const Color(0xFFF59E0B);
      case NurseReadinessState.locationStale:
      case NurseReadinessState.locationRequired:
      case NurseReadinessState.skillsRequired:
      case NurseReadinessState.connectionLost:
        return const Color(0xFFD97706);
      case NurseReadinessState.verificationRequired:
      case NurseReadinessState.settlementBlocked:
        return const Color(0xFFDC2626);
      case NurseReadinessState.offline:
        return const Color(0xFF6B7280);
    }
  }

  IconData get icon {
    switch (this) {
      case NurseReadinessState.ready:
        return Icons.check_circle_rounded;
      case NurseReadinessState.busy:
        return Icons.directions_run_rounded;
      case NurseReadinessState.connecting:
        return Icons.sync_rounded;
      case NurseReadinessState.locationStale:
      case NurseReadinessState.locationRequired:
        return Icons.location_off_rounded;
      case NurseReadinessState.verificationRequired:
        return Icons.verified_user_outlined;
      case NurseReadinessState.skillsRequired:
        return Icons.medical_services_outlined;
      case NurseReadinessState.connectionLost:
        return Icons.wifi_off_rounded;
      case NurseReadinessState.settlementBlocked:
        return Icons.account_balance_wallet_outlined;
      case NurseReadinessState.offline:
        return Icons.power_settings_new_rounded;
    }
  }
}

/// Dedicated, single-authority manager for nurse availability, telemetry, heartbeat, GPS, and server readiness sync.
class AvailabilityManager extends ChangeNotifier {
  final TamreedyApi api;
  final Future<void> Function(List<dynamic> offers) onOffersReceived;

  bool _intentAvailable = false;
  NurseReadinessState _state = NurseReadinessState.offline;
  DateTime? _lastHeartbeat;
  DateTime? _lastLocationUpdate;
  Position? _currentPosition;
  double? _lastAccuracy;
  List<String> _unmetRequirements = [];
  bool _hasActiveAssignment = false;

  Timer? _loopTimer;
  bool _heartbeatBusy = false;
  bool _locationBusy = false;
  bool _readinessBusy = false;
  bool _offersBusy = false;
  int _consecutiveFailures = 0;

  bool get intentAvailable => _intentAvailable;
  NurseReadinessState get state => _state;
  DateTime? get lastHeartbeat => _lastHeartbeat;
  DateTime? get lastLocationUpdate => _lastLocationUpdate;
  Position? get currentPosition => _currentPosition;
  double? get lastAccuracy => _lastAccuracy;
  List<String> get unmetRequirements => _unmetRequirements;
  bool get hasActiveAssignment => _hasActiveAssignment;
  bool get isReady => _state == NurseReadinessState.ready;

  AvailabilityManager({
    required this.api,
    required this.onOffersReceived,
  });

  /// Updates whether nurse is currently assigned to an active visit.
  void setActiveAssignment(bool active) {
    if (_hasActiveAssignment == active) return;
    _hasActiveAssignment = active;
    _reevaluateState();
    notifyListeners();
  }

  /// Sets desired availability intent (on/off toggle).
  Future<void> setAvailability(bool available) async {
    _intentAvailable = available;
    if (!available) {
      _state = NurseReadinessState.offline;
      _stopLoop();
      notifyListeners();
      if (!kDemoMode) {
        try {
          await api.put('/v1/nurse/me/availability', {'availability': 'OFFLINE'});
        } catch (_) {}
      }
      return;
    }

    _state = NurseReadinessState.connecting;
    notifyListeners();

    if (kDemoMode) {
      _state = NurseReadinessState.ready;
      notifyListeners();
      return;
    }

    try {
      await api.put('/v1/nurse/me/availability', {'availability': 'AVAILABLE'});
      _startLoop();
      await syncNow();
    } on DioException {
      _intentAvailable = false;
      _state = NurseReadinessState.offline;
      notifyListeners();
      rethrow;
    } catch (_) {
      _intentAvailable = false;
      _state = NurseReadinessState.offline;
      notifyListeners();
      rethrow;
    }
  }

  /// Immediately triggers full re-sync (on resume, login, network return, WebSocket reconnect).
  Future<void> syncNow() async {
    if (kDemoMode || !_intentAvailable || _hasActiveAssignment) return;
    await Future.wait([
      _sendLocation(),
      _sendHeartbeat(),
    ]);
    await _checkServerReadiness();
    if (_state == NurseReadinessState.ready) {
      await fetchOffersNow();
    }
  }

  /// Query server for open active offers.
  Future<void> fetchOffersNow() async {
    if (kDemoMode || _offersBusy || !_intentAvailable || _hasActiveAssignment) return;
    _offersBusy = true;
    try {
      final list = await api.getList('/v1/nurse/me/offers');
      if (list.isNotEmpty) {
        await onOffersReceived(list);
      }
    } catch (_) {
    } finally {
      _offersBusy = false;
    }
  }

  void _startLoop() {
    _loopTimer?.cancel();
    // Unified cycle timer runs every 5 seconds to manage heartbeat (20s), location (30s), and fallback polling (10s)
    _loopTimer = Timer.periodic(const Duration(seconds: 5), (_) => _onCycleTick());
  }

  void _stopLoop() {
    _loopTimer?.cancel();
    _loopTimer = null;
  }

  Future<void> _onCycleTick() async {
    if (!_intentAvailable || _hasActiveAssignment) return;

    final now = DateTime.now();

    // 1. Heartbeat check: send every 20 seconds
    if (_lastHeartbeat == null || now.difference(_lastHeartbeat!).inSeconds >= 20) {
      await _sendHeartbeat();
    }

    // 2. Location check: update GPS if last update was > 35 seconds ago
    if (_lastLocationUpdate == null || now.difference(_lastLocationUpdate!).inSeconds >= 35) {
      await _sendLocation();
    }

    // 3. Periodic readiness verification
    if (now.second % 15 == 0) {
      await _checkServerReadiness();
    }

    // 4. Fallback offer fetch (every 10s if ready)
    if (_state == NurseReadinessState.ready) {
      await fetchOffersNow();
    }

    _reevaluateState();
  }

  Future<void> _sendHeartbeat() async {
    if (_heartbeatBusy || !_intentAvailable) return;
    _heartbeatBusy = true;
    try {
      await api.post('/v1/nurse/me/heartbeat');
      _lastHeartbeat = DateTime.now();
      _consecutiveFailures = 0;
    } catch (e) {
      _consecutiveFailures++;
      if (_consecutiveFailures >= 3 && _intentAvailable) {
        _state = NurseReadinessState.connectionLost;
        notifyListeners();
      }
    } finally {
      _heartbeatBusy = false;
    }
  }

  Future<void> _sendLocation() async {
    if (_locationBusy || !_intentAvailable) return;
    _locationBusy = true;
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        if (_currentPosition == null && _lastLocationUpdate == null) {
          _state = NurseReadinessState.locationRequired;
          notifyListeners();
        }
        return;
      }

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        if (_currentPosition == null && _lastLocationUpdate == null) {
          _state = NurseReadinessState.locationRequired;
          notifyListeners();
        }
        return;
      }

      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 10),
          ),
        );
      } catch (_) {
        // Fallback to last known position if current GPS fix times out or fails indoors
        pos = await Geolocator.getLastKnownPosition();
      }

      if (pos == null) {
        if (_currentPosition == null && _lastLocationUpdate == null) {
          _state = NurseReadinessState.locationRequired;
          notifyListeners();
        }
        return;
      }

      _currentPosition = pos;
      _lastAccuracy = pos.accuracy;

      await api.put('/v1/nurse/me/location', {
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'accuracyMeters': pos.accuracy,
      });

      _lastLocationUpdate = DateTime.now();
      _reevaluateState();
      notifyListeners();
    } catch (e) {
      // If position lookup failed, reevaluate without dropping readiness if location exists
      _reevaluateState();
    } finally {
      _locationBusy = false;
    }
  }

  Future<void> _checkServerReadiness() async {
    if (_readinessBusy || !_intentAvailable) return;
    _readinessBusy = true;
    try {
      final r = await api.getMap('/v1/nurse/me/readiness');
      final s = '${r['status']}';
      _unmetRequirements = (r['unmetRequirements'] as List? ?? []).map((e) => e.toString()).toList();

      switch (s) {
        case 'READY':
          _state = NurseReadinessState.ready;
          break;
        case 'BUSY':
          _state = NurseReadinessState.busy;
          break;
        case 'LOCATION_REQUIRED':
          _state = NurseReadinessState.locationRequired;
          break;
        case 'LOCATION_STALE':
          _state = NurseReadinessState.ready;
          break;
        case 'VERIFICATION_REQUIRED':
          _state = NurseReadinessState.verificationRequired;
          break;
        case 'SKILLS_REQUIRED':
          _state = NurseReadinessState.skillsRequired;
          break;
        case 'SETTLEMENT_BLOCKED':
          _state = NurseReadinessState.settlementBlocked;
          break;
        case 'CONNECTION_LOST':
          _state = NurseReadinessState.connectionLost;
          break;
        case 'OFFLINE':
          if (_intentAvailable) {
            _state = NurseReadinessState.connecting;
          } else {
            _state = NurseReadinessState.offline;
          }
          break;
        default:
          _reevaluateState();
      }
      notifyListeners();
    } catch (_) {
      // Network hiccup
      if (_consecutiveFailures >= 3) {
        _state = NurseReadinessState.connectionLost;
        notifyListeners();
      }
    } finally {
      _readinessBusy = false;
    }
  }

  void _reevaluateState() {
    if (!_intentAvailable) {
      _state = NurseReadinessState.offline;
      return;
    }

    if (_hasActiveAssignment) {
      _state = NurseReadinessState.busy;
      return;
    }

    if (_currentPosition == null && _lastLocationUpdate == null) {
      _state = NurseReadinessState.locationRequired;
      return;
    }

    final now = DateTime.now();
    final hbAge = _lastHeartbeat != null ? now.difference(_lastHeartbeat!).inSeconds : 999;

    // Heartbeat cutoff relaxed to 120 seconds. Location presence is sufficient.
    if (hbAge > 120) {
      _state = NurseReadinessState.connectionLost;
    } else {
      _state = NurseReadinessState.ready;
    }
  }

  @override
  void dispose() {
    _stopLoop();
    super.dispose();
  }
}
