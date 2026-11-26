import 'dart:async';
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
  }

  late final StreamSubscription<RealtimeEvent> _sub;
  Timer? _fallbackPoll;

  bool loading = true;
  String? error;

  String status = '';
  String bookingMode = 'INSTANT';
  String? clinicalApprovalStatus;
  LatLng? patientPos;
  LatLng? nursePos;
  RouteInfo? route;
  Map<String, dynamic>? nurseBadge;
  String? nurseName;
  String? addressText;
  String? serviceTitle;
  int _lastSequence = -1;
  int _pollCounter = 0;

  void start() {
    refresh();
    _fallbackPoll?.cancel();
    _fallbackPoll = Timer.periodic(const Duration(seconds: 25), (_) => refresh(silent: true));
  }

  void _onEvent(RealtimeEvent ev) {
    final evReqId = ev.payload['requestId']?.toString() ?? ev.payload['request_id']?.toString();
    if (evReqId != null && evReqId != requestId) return;
    if (ev.type == 'tracking.updated') {
      final seq = (num.tryParse('${ev.payload['sequenceNumber'] ?? -1}') ?? -1).toInt();
      if (seq <= _lastSequence) return;
      final lat = double.tryParse('${ev.payload['latitude'] ?? ''}');
      final lng = double.tryParse('${ev.payload['longitude'] ?? ''}');
      final capturedAt = DateTime.tryParse('${ev.payload['capturedAt'] ?? ''}');
      if (lat == null || lng == null || capturedAt == null) return;
      if (DateTime.now().difference(capturedAt.toLocal()) > const Duration(seconds: 120)) {
        return;
      }
      _lastSequence = seq;
      nursePos = LatLng(lat, lng);
      notifyListeners();
      if (status == 'EN_ROUTE' && (_pollCounter++ % 4 == 0 || route == null)) {
        _loadRoute();
      }
      return;
    }
    refresh(silent: true);
  }

  Future<void> refresh({bool silent = false}) async {
    if (kDemoMode) {
      loading = false;
      status = status.isEmpty ? 'EN_ROUTE' : status;
      patientPos ??= kDamascus;
      nursePos ??= const LatLng(33.5200, 36.2860);
      notifyListeners();
      return;
    }

    if (!silent) {
      loading = true;
      error = null;
      notifyListeners();
    }
    try {
      final d = await api.getMap('/v1/requests/$requestId/tracking');
      status = '${d['status'] ?? status}';
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
      if (!silent) {
        error = explainError(e, fallback: 'تعذر تحميل بيانات التتبع المباشر');
      }
    } finally {
      loading = false;
      notifyListeners();
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
    _sub.cancel();
    _fallbackPoll?.cancel();
    super.dispose();
  }
}
