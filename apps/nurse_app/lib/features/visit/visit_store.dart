import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../../guardian.dart';

enum NurseVisitPhase {
  idle,
  assigned,
  enRoute,
  arrived,
  inService,
  completed,
}

class VisitStore extends ChangeNotifier {
  final TamreedyApi api;
  final RealtimeEventBus eventBus;
  final void Function(bool active) onActiveAssignmentChanged;

  VisitStore({
    required this.api,
    required this.eventBus,
    required this.onActiveAssignmentChanged,
  }) {
    _sub = eventBus.whereType(const {
      'request.cancelled',
      'request.assigned',
      'visit.depart',
      'visit.arrive',
      'visit.start',
      'visit.complete',
      'payment.paid',
      'payment.partially_paid',
      'payment.tip',
    }).listen(_onEvent);
  }

  late final StreamSubscription<RealtimeEvent> _sub;
  LiveLocationChannel? _navChannel;
  StreamSubscription<Position>? _posSub;
  Timer? _routeTimer;
  Timer? _demoNavTimer;
  DateTime _lastSentAt = DateTime.fromMillisecondsSinceEpoch(0);

  NurseVisitPhase phase = NurseVisitPhase.idle;
  String? assignmentId;
  String? requestId;
  String? serviceTitle;
  String? beneficiaryName;
  String? patientName;
  String? addressText;
  String? bookingMode;
  LatLng? destination;
  LatLng? nursePos;
  RouteInfo? route;
  BillInfo? bill;
  List<Map<String, dynamic>> items = const [];

  bool busy = false;
  bool loading = false;
  String? error;
  String? cancellationNotice;
  bool arrivalOverrideAvailable = false;

  bool collecting = false;
  String? collectionMessage;
  bool collectionShort = false;

  bool get hasActiveWork => phase != NurseVisitPhase.idle;

  void _onEvent(RealtimeEvent ev) {
    final evReqId = ev.payload['requestId']?.toString() ?? ev.payload['request_id']?.toString();
    if (ev.type == 'request.cancelled' && requestId != null && evReqId == requestId) {
      cancellationNotice = 'أُلغيت الزيارة من المريض. إذا كنت تقود، توقف في مكان آمن أولاً.';
      stopNavigation();
      restoreActiveAssignment();
      return;
    }
    if (evReqId != null && requestId != null && evReqId == requestId) {
      restoreActiveAssignment();
    }
  }

  Future<void> activateFromAcceptedOffer(String reqId, String assignId) async {
    requestId = reqId;
    assignmentId = assignId;
    phase = NurseVisitPhase.assigned;
    cancellationNotice = null;
    error = null;
    onActiveAssignmentChanged(true);
    notifyListeners();
    if (kDemoMode) {
      serviceTitle ??= 'حقنة عضلية وفحص ضغط';
      addressText ??= 'دمشق — المزة';
      beneficiaryName ??= 'المستفيد';
      destination ??= kDamascus;
      items = [
        {
          'id': 'demo-item-1',
          'service_title': serviceTitle,
          'quantity': 1,
          'expected_minutes': 30,
          'item_status': 'PENDING',
        }
      ];
      notifyListeners();
      return;
    }
    await restoreActiveAssignment();
  }

  Future<void> restoreActiveAssignment() async {
    if (kDemoMode) return;
    loading = true;
    notifyListeners();
    try {
      final res = await api.getMap('/v1/nurse/me/active-assignment');
      if (res['hasActive'] != true && res['assignment'] == null) {
        final unpaid = res['unpaidInvoices'] as List?;
        if (unpaid != null && unpaid.isNotEmpty) {
          final firstUnpaid = Map<String, dynamic>.from(unpaid.first as Map);
          requestId = firstUnpaid['id']?.toString();
          assignmentId = firstUnpaid['assignment_id']?.toString();
          serviceTitle = firstUnpaid['service_title']?.toString() ?? serviceTitle;
          phase = NurseVisitPhase.completed;
          onActiveAssignmentChanged(true);
          await loadBill();
          return;
        }
        _resetState(keepCancellationNotice: true);
        return;
      }

      final a = Map<String, dynamic>.from(res['assignment'] as Map? ?? res);
      assignmentId = a['id']?.toString() ?? a['assignment_id']?.toString();
      requestId = a['request_id']?.toString() ?? a['requestId']?.toString();
      final status = '${a['assignment_status'] ?? a['status'] ?? ''}';

      serviceTitle = a['service_title']?.toString() ?? serviceTitle;
      beneficiaryName = a['beneficiary_name']?.toString() ?? beneficiaryName;
      patientName = a['patient_name']?.toString() ?? patientName;
      addressText = a['address_text']?.toString() ?? addressText;
      bookingMode = a['booking_mode']?.toString() ?? bookingMode;

      final lat = double.tryParse('${a['latitude'] ?? a['patient_lat'] ?? ''}');
      final lng = double.tryParse('${a['longitude'] ?? a['patient_lng'] ?? ''}');
      if (lat != null && lng != null) destination = LatLng(lat, lng);

      if (a['items'] is List) {
        items = (a['items'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      } else if (assignmentId != null) {
        await refreshAssignmentDetail();
      }

      phase = switch (status) {
        'ASSIGNED' => NurseVisitPhase.assigned,
        'EN_ROUTE' => NurseVisitPhase.enRoute,
        'ARRIVED' => NurseVisitPhase.arrived,
        'IN_SERVICE' => NurseVisitPhase.inService,
        'COMPLETED' => NurseVisitPhase.completed,
        _ => NurseVisitPhase.idle,
      };

      onActiveAssignmentChanged(phase != NurseVisitPhase.idle);

      if (phase == NurseVisitPhase.enRoute) {
        unawaited(_startNavigation());
      } else {
        stopNavigation();
      }
      if (phase == NurseVisitPhase.completed) {
        await loadBill();
      }
      error = null;
    } catch (_) {
      // Keep local state on transient network failure
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> refreshAssignmentDetail() async {
    if (kDemoMode || assignmentId == null) return;
    try {
      final d = await api.getMap('/v1/nurse/assignments/$assignmentId');
      serviceTitle = d['service_title']?.toString() ?? serviceTitle;
      beneficiaryName = d['beneficiary_name']?.toString() ?? beneficiaryName;
      patientName = d['patient_name']?.toString() ?? patientName;
      addressText = d['address_text']?.toString() ?? addressText;
      final lat = double.tryParse('${d['latitude'] ?? ''}');
      final lng = double.tryParse('${d['longitude'] ?? ''}');
      if (lat != null && lng != null) destination = LatLng(lat, lng);
      if (d['items'] is List) {
        items = (d['items'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _step(
    String command,
    NurseVisitPhase nextPhase, {
    Map<String, dynamic>? body,
  }) async {
    if (busy || (!kDemoMode && assignmentId == null)) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      if (!kDemoMode) {
        await api.post('/v1/nurse/assignments/$assignmentId/$command', body);
      }
      phase = nextPhase;
    } on DioException catch (de) {
      final data = de.response?.data;
      if (command == 'arrive' &&
          data is Map &&
          data['code'] == 'ARRIVAL_GEOFENCE_FAILED') {
        arrivalOverrideAvailable = true;
        error = 'الموقع الحالي خارج النطاق الدقيق. حدّث GPS أو وثّق سبب الاستثناء.';
        return;
      }
      if (de.response?.statusCode == 409) {
        await restoreActiveAssignment();
      } else {
        error = explainError(de, fallback: 'تعذر تنفيذ الانتقال. تحقق من الحالة وأعد المحاولة.');
      }
    } catch (e) {
      error = explainError(e, fallback: 'تعذر تنفيذ الانتقال. حاول مرة أخرى.');
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> depart() async {
    if (phase != NurseVisitPhase.assigned || busy) return;
    await _step('depart', NurseVisitPhase.enRoute);
    if (phase == NurseVisitPhase.enRoute) {
      await _startNavigation();
    }
  }

  Future<void> arrive({String? overrideReason}) async {
    if (phase != NurseVisitPhase.enRoute || busy) return;
    await _step(
      'arrive',
      NurseVisitPhase.arrived,
      body: overrideReason == null ? null : {'geofenceOverrideReason': overrideReason},
    );
    if (phase == NurseVisitPhase.arrived) {
      arrivalOverrideAvailable = false;
      stopNavigation();
    }
  }

  Future<void> startService() async {
    if (phase != NurseVisitPhase.arrived || busy) return;
    await _step('start', NurseVisitPhase.inService);
    Analytics.log('visit_started');
  }

  Future<void> completeVisit() async {
    if (phase != NurseVisitPhase.inService || busy) return;
    await _step('complete', NurseVisitPhase.completed);
    Analytics.log('visit_completed', {'request_id': requestId ?? ''});
    if (phase == NurseVisitPhase.completed) {
      await loadBill();
    }
  }

  Future<void> _startNavigation() async {
    if (kDemoMode) {
      destination ??= kDamascus;
      _demoNavTimer?.cancel();
      var step = 0;
      _demoNavTimer = Timer.periodic(const Duration(seconds: 2), (t) {
        step++;
        final f = (1 - step / 6).clamp(0.0, 1.0);
        nursePos = LatLng(
          destination!.latitude + 0.01 * f,
          destination!.longitude - 0.01 * f,
        );
        notifyListeners();
        if (step >= 6) t.cancel();
      });
      return;
    }

    if (assignmentId == null || _posSub != null) return;
    try {
      _navChannel ??= LiveLocationChannel(api);
      await _navChannel!.start();
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        return;
      }
      final settings = defaultTargetPlatform == TargetPlatform.android
          ? AndroidSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 10,
              foregroundNotificationConfig: const ForegroundNotificationConfig(
                notificationTitle: 'تمريضي للممرضين',
                notificationText: 'مشاركة موقعك أثناء التوجه إلى الزيارة',
                enableWakeLock: true,
              ),
            )
          : const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10);

      _posSub = Geolocator.getPositionStream(locationSettings: settings).listen((pos) async {
        nursePos = LatLng(pos.latitude, pos.longitude);
        notifyListeners();
        if (DateTime.now().difference(_lastSentAt).inSeconds >= 4) {
          _lastSentAt = DateTime.now();
          try {
            final sessionId = await api.deviceSessionId();
            if (sessionId == null) return;
            final payload = <String, dynamic>{
              'latitude': pos.latitude,
              'longitude': pos.longitude,
              'accuracyMeters': pos.accuracy,
              'capturedAt': pos.timestamp.toUtc().toIso8601String(),
              'sequenceNumber': await api.nextLocationSequence(),
              'sessionId': sessionId,
              if (pos.speed >= 0) 'speedMetersPerSecond': pos.speed,
              if (pos.heading >= 0) 'heading': pos.heading,
              'locationSource': 'GPS',
              'assignmentId': ?assignmentId,
            };
            final sentViaSocket = await (_navChannel?.send(payload) ?? Future.value(false));
            if (!sentViaSocket) {
              api.put('/v1/nurse/me/location', payload).catchError((_) => <String, dynamic>{});
            }
          } catch (_) {}
        }
      });

      await _refreshRoute();
      _routeTimer?.cancel();
      _routeTimer = Timer.periodic(const Duration(seconds: 20), (_) => _refreshRoute());
    } catch (_) {
      error = 'تعذر تفعيل التتبع الملاحي، تأكد من تشغيل GPS.';
      notifyListeners();
    }
  }

  Future<void> _refreshRoute() async {
    if (assignmentId == null || phase != NurseVisitPhase.enRoute) return;
    try {
      route = RouteInfo.fromJson(await api.getMap('/v1/nurse/assignments/$assignmentId/route'));
      notifyListeners();
    } catch (_) {}
  }

  void stopNavigation() {
    _posSub?.cancel();
    _posSub = null;
    _routeTimer?.cancel();
    _routeTimer = null;
    _demoNavTimer?.cancel();
    _demoNavTimer = null;
    _navChannel?.dispose();
    _navChannel = null;
    route = null;
  }

  Future<void> loadBill() async {
    if (kDemoMode) {
      bill = const BillInfo(
        due: 45000,
        minutes: 35,
        gross: 45000,
        discount: 0,
        collected: 0,
        remaining: 45000,
        status: 'DUE',
        visitId: 'demo-visit-1',
        nurseEarning: 36000,
      );
      notifyListeners();
      return;
    }
    if (requestId == null) return;
    try {
      bill = BillInfo.fromJson(await api.getMap('/v1/nurse/requests/$requestId/bill'));
      notifyListeners();
    } catch (e) {
      error = explainError(e, fallback: 'تعذر تحميل تفاصيل الفاتورة');
      notifyListeners();
    }
  }

  Future<bool> collectCash(int amount) async {
    final b = bill;
    if (b == null || amount <= 0 || collecting) return false;
    collecting = true;
    collectionMessage = null;
    notifyListeners();
    try {
      if (kDemoMode) {
        final r = applyCollection(b.payable, b.collected, amount);
        collectionMessage = r.message;
        collectionShort = !r.paid;
        bill = BillInfo(
          due: b.due,
          minutes: b.minutes,
          gross: b.gross,
          discount: b.discount,
          collected: r.collected,
          remaining: r.remaining,
          status: r.paid ? 'PAID' : 'PARTIAL',
          visitId: b.visitId,
          tip: b.tip,
          nurseEarning: b.nurseEarning,
        );
        return r.paid;
      }

      final id = requestId;
      if (id == null) return false;
      final storageKey = 'cash_collect_v3_${id}_$amount';
      var idemKey = await api.readLocal(storageKey);
      if (idemKey == null || idemKey.isEmpty) {
        idemKey = api.newIdempotencyKey();
        await api.writeLocal(storageKey, idemKey);
      }

      final r = await api.post(
        '/v1/nurse/requests/$id/collect',
        {'amount': amount},
        {'Idempotency-Key': idemKey},
      );
      await api.writeLocal(storageKey, null);

      final remaining = (num.tryParse('${r['remaining'] ?? 0}') ?? 0).round();
      final change = (num.tryParse('${r['change'] ?? 0}') ?? 0).round();
      collectionMessage = remaining > 0
          ? 'تم استلام دفعة جزئية — المتبقي ${formatMoney(remaining)}'
          : change > 0
              ? 'تم التحصيل بالكامل — أعد للمريض ${formatMoney(change)}'
              : 'تم تحصيل كامل المبلغ بنجاح';
      collectionShort = r['status'] != 'PAID';
      await loadBill();
      return !collectionShort;
    } catch (e) {
      collectionMessage = explainError(e, fallback: 'تعذر تأكيد التحصيل النقدي. حاول مرة أخرى.');
      collectionShort = true;
      return false;
    } finally {
      collecting = false;
      notifyListeners();
    }
  }

  Future<void> submitPostVisitReport({
    required int stars,
    String note = '',
    String category = 'NORMAL',
  }) async {
    final visitId = bill?.visitId;
    if (kDemoMode || visitId == null || visitId.isEmpty) return;
    await api.post('/v1/visits/$visitId/nurse-report', {
      'category': category,
      'stars': stars,
      if (note.trim().isNotEmpty) 'note': note.trim(),
    });
  }

  Future<bool> safeAbort(GuardianController guardian) async {
    if (assignmentId == null || kDemoMode) return false;
    final ok = await guardian.abortAssignment(assignmentId!);
    if (ok) {
      _resetState(keepCancellationNotice: false);
    }
    return ok;
  }

  void finishAndReturnAvailable() {
    _resetState(keepCancellationNotice: false);
  }

  void clearCancellationNotice() {
    cancellationNotice = null;
    notifyListeners();
  }

  void _resetState({required bool keepCancellationNotice}) {
    stopNavigation();
    phase = NurseVisitPhase.idle;
    assignmentId = null;
    requestId = null;
    serviceTitle = null;
    beneficiaryName = null;
    patientName = null;
    addressText = null;
    bookingMode = null;
    destination = null;
    nursePos = null;
    bill = null;
    items = const [];
    arrivalOverrideAvailable = false;
    collectionMessage = null;
    collectionShort = false;
    if (!keepCancellationNotice) cancellationNotice = null;
    onActiveAssignmentChanged(false);
    notifyListeners();
  }

  @override
  void dispose() {
    stopNavigation();
    _sub.cancel();
    super.dispose();
  }
}
