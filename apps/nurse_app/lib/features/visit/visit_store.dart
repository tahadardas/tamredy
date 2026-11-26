import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../../guardian.dart';

enum NurseVisitPhase {
  idle,
  scheduled,
  assigned,
  enRoute,
  arrived,
  inService,
  completed,
  escalated,
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
  TypedAssignmentSnapshot? activeSnapshot;
  List<TypedAssignmentSnapshot> assignments = const [];
  List<TypedUnpaidInvoice> unpaidInvoices = const [];
  TypedUnpaidInvoice? activeUnpaidInvoice;
  String? _collectionRequestId;

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
  String? syncError;
  String? cancellationNotice;
  bool arrivalOverrideAvailable = false;

  bool collecting = false;
  String? collectionMessage;
  bool collectionShort = false;

  int _entityVersion = 0;
  int _restoreGeneration = 0;
  int _sessionGeneration = 0;
  Future<void>? _restoreInFlight;

  bool get hasActiveWork => const {
    NurseVisitPhase.assigned,
    NurseVisitPhase.enRoute,
    NurseVisitPhase.arrived,
    NurseVisitPhase.inService,
    NurseVisitPhase.escalated,
  }.contains(phase);

  bool canPerform(String action) =>
      activeSnapshot == null || activeSnapshot!.allowedActions.isEmpty
          ? true
          : activeSnapshot!.allowedActions.contains(action);

  void _onEvent(RealtimeEvent ev) {
    final evReqId = ev.payload['requestId']?.toString() ?? ev.payload['request_id']?.toString();
    final evVer = int.tryParse('${ev.payload['entityVersion'] ?? ev.payload['version'] ?? ''}');
    if (ev.type == 'request.cancelled' && requestId != null && evReqId == requestId) {
      cancellationNotice = 'أُلغيت الزيارة من المريض. إذا كنت تقود، توقف في مكان آمن أولاً.';
      stopNavigation();
      restoreActiveAssignment(force: true);
      return;
    }
    if (ev.type.startsWith('payment.') && activeUnpaidInvoice != null && evReqId == activeUnpaidInvoice!.requestId) {
      loadBill(targetRequestId: activeUnpaidInvoice!.requestId);
      restoreActiveAssignment(force: true);
      return;
    }
    if (evReqId != null && requestId != null && evReqId == requestId) {
      if (evVer != null && evVer < _entityVersion) return;
      restoreActiveAssignment(force: true);
    } else if (ev.type == 'request.assigned') {
      restoreActiveAssignment(force: true);
    }
  }

  Future<void> activateFromAcceptedOffer(String reqId, String assignId) async {
    requestId = reqId;
    assignmentId = assignId;
    phase = NurseVisitPhase.assigned;
    _entityVersion = 1;
    cancellationNotice = null;
    error = null;
    syncError = null;
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
    await restoreActiveAssignment(force: true);
  }

  Future<void> restoreActiveAssignment({bool force = false}) {
    if (kDemoMode) return Future.value();
    if (!force && _restoreInFlight != null) return _restoreInFlight!;
    final future = _doRestoreActiveAssignment();
    _restoreInFlight = future.whenComplete(() {
      if (identical(_restoreInFlight, future)) _restoreInFlight = null;
    });
    return _restoreInFlight!;
  }

  NurseVisitPhase? _mapRequestStatusToPhase(String requestStatus) => switch (requestStatus) {
    'SCHEDULED' => NurseVisitPhase.scheduled,
    'ASSIGNED' => NurseVisitPhase.assigned,
    'EN_ROUTE' => NurseVisitPhase.enRoute,
    'ARRIVED' => NurseVisitPhase.arrived,
    'IN_SERVICE' => NurseVisitPhase.inService,
    'COMPLETED' => NurseVisitPhase.completed,
    'ESCALATED' => NurseVisitPhase.escalated,
    _ => null,
  };

  Future<void> _doRestoreActiveAssignment() async {
    final gen = ++_restoreGeneration;
    final sessGen = _sessionGeneration;
    loading = true;
    notifyListeners();
    try {
      final res = await api.getMap('/v1/nurse/me/active-assignment');
      if (gen != _restoreGeneration || sessGen != _sessionGeneration) return;

      final rawInvoices = res['unpaidInvoices'] as List? ?? const [];
      unpaidInvoices = [
        for (final inv in rawInvoices)
          if (inv is Map) TypedUnpaidInvoice.fromJson(Map<String, dynamic>.from(inv)),
      ];

      final rawAssignments = res['assignments'] as List? ?? const [];
      assignments = [
        for (final row in rawAssignments)
          if (row is Map) TypedAssignmentSnapshot.fromJson(Map<String, dynamic>.from(row)),
      ];

      if (res['hasActive'] != true && res['assignment'] == null) {
        activeSnapshot = null;
        if (unpaidInvoices.isEmpty) {
          activeUnpaidInvoice = null;
          _collectionRequestId = null;
        } else if (activeUnpaidInvoice != null) {
          final stillUnpaid = unpaidInvoices.where((i) => i.requestId == activeUnpaidInvoice!.requestId);
          if (stillUnpaid.isEmpty) {
            activeUnpaidInvoice = null;
            _collectionRequestId = null;
            bill = null;
          } else {
            activeUnpaidInvoice = stillUnpaid.first;
          }
        }
        _resetActiveFieldVisit(keepCancellationNotice: true);
        return;
      }

      final a = Map<String, dynamic>.from(res['assignment'] as Map? ?? res);
      final snap = TypedAssignmentSnapshot.fromJson(a);
      if (snap.assignmentId == assignmentId && snap.version < _entityVersion) {
        return;
      }

      final mappedPhase = _mapRequestStatusToPhase(snap.requestStatus);
      if (mappedPhase == null) {
        // BUG-001: never silently coerce an unknown requestStatus to idle!
        syncError = 'تم استلام حالة غير معروفة من الخادم (${snap.requestStatus}). يتم الاحتفاظ بآخر حالة مؤكدة.';
        return;
      }
      // Prevent stale downgrades from terminal local completion
      if (snap.requestId == requestId && phase == NurseVisitPhase.completed && mappedPhase != NurseVisitPhase.completed && snap.version <= _entityVersion) {
        return;
      }

      syncError = null;
      activeSnapshot = snap;
      _entityVersion = snap.version;
      assignmentId = snap.assignmentId;
      requestId = snap.requestId;
      phase = mappedPhase;

      serviceTitle = snap.serviceTitle ?? serviceTitle;
      beneficiaryName = snap.beneficiaryName ?? beneficiaryName;
      patientName = snap.patientName ?? patientName;
      addressText = snap.addressText ?? addressText;
      bookingMode = snap.bookingMode ?? bookingMode;

      if (snap.patientLat != null && snap.patientLng != null) {
        destination = LatLng(snap.patientLat!, snap.patientLng!);
      }

      if (snap.items != null) {
        items = snap.items!;
      } else if (assignmentId != null && assignmentId!.isNotEmpty) {
        await refreshAssignmentDetail();
        if (gen != _restoreGeneration || sessGen != _sessionGeneration) return;
      }

      onActiveAssignmentChanged(hasActiveWork);

      if (phase == NurseVisitPhase.enRoute) {
        unawaited(_startNavigation());
      } else {
        stopNavigation();
      }
      if (phase == NurseVisitPhase.completed) {
        _collectionRequestId = requestId;
        await loadBill(targetRequestId: requestId);
      }
      error = null;
    } catch (_) {
      // Keep local state on transient network failure
    } finally {
      if (gen == _restoreGeneration && sessGen == _sessionGeneration) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> openUnpaidInvoice(TypedUnpaidInvoice invoice) async {
    activeUnpaidInvoice = invoice;
    _collectionRequestId = invoice.requestId;
    collectionMessage = null;
    collectionShort = false;
    bill = null;
    notifyListeners();
    await loadBill(targetRequestId: invoice.requestId);
  }

  void clearSelectedUnpaidInvoice() {
    activeUnpaidInvoice = null;
    if (phase != NurseVisitPhase.completed) {
      _collectionRequestId = null;
      bill = null;
    }
    collectionMessage = null;
    collectionShort = false;
    notifyListeners();
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
      _collectionRequestId = requestId;
      await loadBill(targetRequestId: requestId);
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

  Future<void> loadBill({String? targetRequestId}) async {
    final reqId = targetRequestId ?? _collectionRequestId ?? activeUnpaidInvoice?.requestId ?? requestId;
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
    if (reqId == null || reqId.isEmpty) return;
    final sessGen = _sessionGeneration;
    try {
      final fetched = BillInfo.fromJson(await api.getMap('/v1/nurse/requests/$reqId/bill'));
      if (sessGen != _sessionGeneration) return;
      bill = fetched;
      _collectionRequestId = reqId;
      notifyListeners();
    } catch (e) {
      if (sessGen != _sessionGeneration) return;
      error = explainError(e, fallback: 'تعذر تحميل تفاصيل الفاتورة');
      notifyListeners();
    }
  }

  Future<bool> collectCash(int amount, {String? targetRequestId}) async {
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

      final id = targetRequestId ?? _collectionRequestId ?? activeUnpaidInvoice?.requestId ?? requestId;
      if (id == null || id.isEmpty) return false;
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
      await loadBill(targetRequestId: id);
      if (!collectionShort) {
        unpaidInvoices = unpaidInvoices.where((inv) => inv.requestId != id).toList();
        if (activeUnpaidInvoice?.requestId == id) activeUnpaidInvoice = null;
      }
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

  void resetForSessionChange() {
    _sessionGeneration++;
    _restoreGeneration++;
    _restoreInFlight = null;
    unpaidInvoices = const [];
    assignments = const [];
    activeUnpaidInvoice = null;
    _collectionRequestId = null;
    _resetState(keepCancellationNotice: false);
  }

  void _resetActiveFieldVisit({required bool keepCancellationNotice}) {
    stopNavigation();
    phase = NurseVisitPhase.idle;
    activeSnapshot = null;
    assignmentId = null;
    requestId = null;
    serviceTitle = null;
    beneficiaryName = null;
    patientName = null;
    addressText = null;
    bookingMode = null;
    destination = null;
    nursePos = null;
    items = const [];
    _entityVersion = 0;
    arrivalOverrideAvailable = false;
    syncError = null;
    if (!keepCancellationNotice) cancellationNotice = null;
    onActiveAssignmentChanged(false);
    notifyListeners();
  }

  void _resetState({required bool keepCancellationNotice}) {
    activeUnpaidInvoice = null;
    _collectionRequestId = null;
    bill = null;
    collectionMessage = null;
    collectionShort = false;
    _resetActiveFieldVisit(keepCancellationNotice: keepCancellationNotice);
  }

  @override
  void dispose() {
    stopNavigation();
    _sub.cancel();
    super.dispose();
  }
}
