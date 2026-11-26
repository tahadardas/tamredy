import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:tamreedy_core/tamreedy_core.dart';

/// Isolated live-tracking & ETA store for a single active request.
///
/// Receives `tracking.updated` socket events directly from [RealtimeEventBus]
/// without causing rebuilds in Home, Catalog, or Requests list screens.
class TrackingStore extends ChangeNotifier {
  final TamreedyApi api;
  final RealtimeEventBus eventBus;
  final String requestId;

  TrackingStore({
    required this.api,
    required this.eventBus,
    required this.requestId,
  }) {
    _sub = eventBus.whereType(const {
      'tracking.updated',
      'request.assigned',
      'request.clinical_review_changed',
      'visit.depart',
      'visit.arrive',
      'visit.start',
      'visit.complete',
      'visit.interrupted',
      'request.cancelled',
    }).listen(_onEvent);
    _connSub = eventBus.connectionStateStream.listen(_onConnectionChanged);
  }

  late final StreamSubscription<RealtimeEvent> _sub;
  StreamSubscription<bool>? _connSub;
  Timer? _fallbackPoll;
  CancelToken? _refreshCancelToken;

  bool loading = true;
  String? error;

  String status = '';
  int _entityVersion = 0;
  String bookingMode = 'INSTANT';
  String? clinicalApprovalStatus;
  LatLng? patientPos;
  LatLng? nursePos;
  RouteInfo? route;
  Map<String, dynamic>? nurseBadge;
  String? nurseName;
  String? addressText;
  String? serviceTitle;
  String? _locationSessionId;
  int _lastSequence = -1;
  DateTime? _lastLocationCapturedAt;
  int _pollCounter = 0;
  int _refreshGeneration = 0;
  Future<void>? _refreshInFlight;

  void start() {
    refresh();
    _schedulePollIfNeeded();
  }

  void _onConnectionChanged(bool connected) {
    if (connected) {
      _fallbackPoll?.cancel();
      _fallbackPoll = null;
      refresh(silent: true);
    } else {
      _schedulePollIfNeeded();
    }
  }

  void _schedulePollIfNeeded() {
    _fallbackPoll?.cancel();
    if (eventBus.isConnected) return;
    _fallbackPoll = Timer.periodic(const Duration(seconds: 25), (_) {
      if (!eventBus.isConnected) {
        refresh(silent: true);
      }
    });
  }

  void _onEvent(RealtimeEvent ev) {
    final evReqId = ev.payload['requestId']?.toString() ?? ev.payload['request_id']?.toString();
    if (evReqId != null && evReqId != requestId) return;
    final evVer = int.tryParse('${ev.payload['entityVersion'] ?? ev.payload['version'] ?? ''}');
    if (evVer != null && evVer < _entityVersion) return;

    if (ev.type == 'tracking.updated') {
      final incomingSessionId = ev.payload['sessionId']?.toString() ??
          ev.payload['locationSessionId']?.toString();
      final seq = (num.tryParse('${ev.payload['sequenceNumber'] ?? -1}') ?? -1).toInt();
      final lat = double.tryParse('${ev.payload['latitude'] ?? ''}');
      final lng = double.tryParse('${ev.payload['longitude'] ?? ''}');
      final capturedAt = DateTime.tryParse('${ev.payload['capturedAt'] ?? ''}');
      if (lat == null || lng == null || capturedAt == null) return;
      if (DateTime.now().difference(capturedAt.toLocal()) > const Duration(seconds: 120)) {
        return;
      }
      // BUG-037: interpret sequence numbers strictly within the same location session;
      // when session switches, accept newer timestamps cleanly instead of rejecting seq=1.
      if (incomingSessionId != null &&
          incomingSessionId.isNotEmpty &&
          incomingSessionId != _locationSessionId) {
        if (_lastLocationCapturedAt != null && capturedAt.isBefore(_lastLocationCapturedAt!)) {
          return;
        }
        _locationSessionId = incomingSessionId;
        _lastSequence = seq;
      } else {
        if (seq <= _lastSequence) return;
        _lastSequence = seq;
      }
      _lastLocationCapturedAt = capturedAt;
      nursePos = LatLng(lat, lng);
      notifyListeners();
      if (status == 'EN_ROUTE' && (_pollCounter++ % 4 == 0 || route == null)) {
        _loadRoute();
      }
      return;
    }
    refresh(silent: true, force: true);
  }

  Future<void> refresh({bool silent = false, bool force = false}) {
    if (kDemoMode) {
      loading = false;
      status = status.isEmpty ? 'EN_ROUTE' : status;
      patientPos ??= kDamascus;
      nursePos ??= const LatLng(33.5200, 36.2860);
      notifyListeners();
      return Future.value();
    }
    if (!force && _refreshInFlight != null) return _refreshInFlight!;
    _refreshCancelToken?.cancel('superseded');
    final cancelToken = CancelToken();
    _refreshCancelToken = cancelToken;
    final future = _doRefresh(silent: silent, cancelToken: cancelToken);
    _refreshInFlight = future.whenComplete(() {
      if (identical(_refreshInFlight, future)) _refreshInFlight = null;
    });
    return _refreshInFlight!;
  }

  Future<void> _doRefresh({required bool silent, required CancelToken cancelToken}) async {
    final gen = ++_refreshGeneration;
    if (!silent) {
      loading = true;
      error = null;
      notifyListeners();
    }
    try {
      final d = await api.getMap('/v1/requests/$requestId/tracking', cancelToken: cancelToken);
      if (gen != _refreshGeneration || cancelToken.isCancelled) return;

      final serverVersion = (num.tryParse('${d['version'] ?? 0}') ?? 0).toInt();
      if (serverVersion > 0 && serverVersion < _entityVersion) return;
      final incomingStatus = '${d['status'] ?? status}';
      const terminal = {'COMPLETED', 'CANCELLED', 'EXPIRED'};
      if (terminal.contains(status) && !terminal.contains(incomingStatus) && serverVersion <= _entityVersion) {
        return;
      }

      if (serverVersion > _entityVersion) _entityVersion = serverVersion;
      status = incomingStatus;
      bookingMode = '${d['booking_mode'] ?? bookingMode}';
      clinicalApprovalStatus = d['clinical_approval_status']?.toString();
      serviceTitle = d['service_title']?.toString() ?? serviceTitle;
      addressText = d['address_text']?.toString() ?? addressText;
      nurseBadge = d['nurseBadge'] is Map
          ? Map<String, dynamic>.from(d['nurseBadge'] as Map)
          : null;
      nurseName = d['nurse_name']?.toString() ?? nurseBadge?['name']?.toString() ?? nurseName;

      final pLat = double.tryParse('${d['patient_lat'] ?? ''}');
      final pLng = double.tryParse('${d['patient_lng'] ?? ''}');
      if (pLat != null && pLng != null) patientPos = LatLng(pLat, pLng);

      final nLat = double.tryParse('${d['nurse_lat'] ?? ''}');
      final nLng = double.tryParse('${d['nurse_lng'] ?? ''}');
      if (nLat != null && nLng != null) nursePos = LatLng(nLat, nLng);

      if (status == 'EN_ROUTE' && nursePos != null) {
        await _loadRoute();
      } else {
        route = null;
      }
      error = null;
    } catch (e) {
      if (cancelToken.isCancelled) return;
      if (!silent) {
        error = explainError(e, fallback: 'تعذر تحميل بيانات التتبع المباشر');
      }
    } finally {
      if (gen == _refreshGeneration) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _loadRoute() async {
    try {
      route = RouteInfo.fromJson(await api.getMap('/v1/requests/$requestId/route'));
      notifyListeners();
    } catch (_) {}
  }

  @override
  void dispose() {
    _refreshCancelToken?.cancel('disposed');
    _sub.cancel();
    _connSub?.cancel();
    _fallbackPoll?.cancel();
    super.dispose();
  }
}
