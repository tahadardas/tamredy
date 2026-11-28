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
  String? visitOutcome;
  String? visitOutcomeReason;
  bool invoiceAbsent = false;
  bool billLoading = false;
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
  int _assignmentGeneration = 0;
  int _billGeneration = 0;
  CancelToken? _detailCancelToken;
  CancelToken? _restoreCancelToken;

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
    _restoreCancelToken?.cancel('superseded');
    final token = CancelToken();
    _restoreCancelToken = token;
    late final Future<void> tracked;
    tracked = _doRestoreActiveAssignment(token).whenComplete(() {
      if (identical(_restoreInFlight, tracked)) _restoreInFlight = null;
    });
    _restoreInFlight = tracked;
    return tracked;
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

  Future<void> _doRestoreActiveAssignment(CancelToken token) async {
    final gen = ++_restoreGeneration;
    final sessGen = _sessionGeneration;
    loading = true;
    notifyListeners();
    try {
      final res = await api.getMap('/v1/nurse/me/active-assignment', cancelToken: token);
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

      final assignmentChanged = assignmentId != snap.assignmentId;
      if (assignmentChanged) {
        _resetActiveFieldVisit(keepCancellationNotice: false);
        bill = null;
        activeUnpaidInvoice = null;
        _collectionRequestId = null;
        collectionMessage = null;
        collectionShort = false;
      }
      syncError = null;
      activeSnapshot = snap;
      _entityVersion = snap.version;
      assignmentId = snap.assignmentId;
      requestId = snap.requestId;
      phase = mappedPhase;

      serviceTitle = snap.serviceTitle;
      beneficiaryName = snap.beneficiaryName;
      patientName = snap.patientName;
      addressText = snap.exactLocationAuthorized ? snap.addressText : null;
      bookingMode = snap.bookingMode;
      visitOutcome = snap.visitOutcome;
      visitOutcomeReason = snap.visitOutcomeReason;
      invoiceAbsent = visitOutcome == 'NOT_PERFORMED';
      destination = snap.exactLocationAuthorized && snap.patientLat != null && snap.patientLng != null
          ? LatLng(snap.patientLat!, snap.patientLng!) : null;
      if (destination == null) stopNavigation();

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
    } catch (e) {
      if (gen != _restoreGeneration || sessGen != _sessionGeneration || token.isCancelled) return;
      syncError = explainError(e, fallback: 'تعذر تحديث الزيارة؛ يتم عرض آخر بيانات مؤكدة');
      api.markStale();
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
    final id = assignmentId;
    if (kDemoMode || id == null) return;
    final session = _sessionGeneration;
    final generation = _assignmentGeneration;
    _detailCancelToken?.cancel('superseded');
    final token = CancelToken();
    _detailCancelToken = token;
    try {
      final d = await api.getMap('/v1/nurse/assignments/$id', cancelToken: token);
      if (session != _sessionGeneration || generation != _assignmentGeneration || id != assignmentId || token.isCancelled) return;
      serviceTitle = d['service_title']?.toString();
      beneficiaryName = d['beneficiary_name']?.toString();
      patientName = d['patient_name']?.toString();
      final authorized = d['exact_location_authorized'] == true;
      addressText = authorized ? d['address_text']?.toString() : null;
      final lat = double.tryParse('${d['latitude'] ?? ''}');
      final lng = double.tryParse('${d['longitude'] ?? ''}');
      destination = authorized && lat != null && lng != null ? LatLng(lat, lng) : null;
      if (destination == null) stopNavigation();
      visitOutcome = d['visit_outcome']?.toString();
      visitOutcomeReason = d['visit_outcome_reason']?.toString();
      invoiceAbsent = visitOutcome == 'NOT_PERFORMED';
      items = (d['items'] as List? ?? const []).whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e)).toList();
      notifyListeners();
    } catch (e) {
      if (session != _sessionGeneration || generation != _assignmentGeneration || token.isCancelled) return;
      syncError = explainError(e, fallback: 'تعذر تحديث تفاصيل الزيارة');
      notifyListeners();
    }
  }

  Future<void> _step(
    String command,
    NurseVisitPhase nextPhase, {
    Map<String, dynamic>? body,
  }) async {
    if (busy || (!kDemoMode && assignmentId == null)) return;
    final session = _sessionGeneration;
    final generation = _assignmentGeneration;
    final id = assignmentId;
    busy = true;
    error = null;
    notifyListeners();
    try {
      if (!kDemoMode) {
        final response = await api.post('/v1/nurse/assignments/$id/$command', body);
        if (session != _sessionGeneration || generation != _assignmentGeneration || id != assignmentId) return;
        visitOutcome = (response['visit_outcome'] ?? response['visitOutcome'])?.toString() ?? visitOutcome;
        visitOutcomeReason = (response['visit_outcome_reason'] ?? response['visitOutcomeReason'] ?? response['reason'])?.toString() ?? visitOutcomeReason;
        invoiceAbsent = visitOutcome == 'NOT_PERFORMED';
      }
      phase = nextPhase;
    } on DioException catch (de) {
      if (session != _sessionGeneration || generation != _assignmentGeneration) return;
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
      if (session != _sessionGeneration || generation != _assignmentGeneration) return;
      error = explainError(e, fallback: 'تعذر تنفيذ الانتقال. حاول مرة أخرى.');
    } finally {
      if (session == _sessionGeneration && generation == _assignmentGeneration) {
        busy = false;
        notifyListeners();
      }
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

    if (assignmentId == null || destination == null || _posSub != null) return;
    final session = _sessionGeneration;
    final generation = _assignmentGeneration;
    final id = assignmentId;
    bool current() => session == _sessionGeneration && generation == _assignmentGeneration && id == assignmentId
        && destination != null && phase == NurseVisitPhase.enRoute;
    try {
      _navChannel ??= LiveLocationChannel(api);
      await _navChannel!.start();
      if (!current()) return;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        return;
      }
      if (!current()) return;
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
        if (!current()) return;
        nursePos = LatLng(pos.latitude, pos.longitude);
        notifyListeners();
        if (DateTime.now().difference(_lastSentAt).inSeconds >= 4) {
          _lastSentAt = DateTime.now();
          try {
            final sessionId = await api.deviceSessionId();
            if (sessionId == null || !current()) return;
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
              'assignmentId': ?id,
            };
            final sentViaSocket = await (_navChannel?.send(payload) ?? Future.value(false));
            if (!sentViaSocket && current()) {
              api.put('/v1/nurse/me/location', payload).catchError((_) => <String, dynamic>{});
            }
          } catch (_) {}
        }
      });

      await _refreshRoute();
      if (!current()) return;
      _routeTimer?.cancel();
      _routeTimer = Timer.periodic(const Duration(seconds: 20), (_) => _refreshRoute());
    } catch (_) {
      if (!current()) return;
      error = 'تعذر تفعيل التتبع الملاحي، تأكد من تشغيل GPS.';
      notifyListeners();
    }
  }

  Future<void> _refreshRoute() async {
    if (assignmentId == null || phase != NurseVisitPhase.enRoute) return;
    final id = assignmentId;
    final generation = _assignmentGeneration;
    try {
      final fetched = RouteInfo.fromJson(await api.getMap('/v1/nurse/assignments/$id/route'));
      if (id != assignmentId || generation != _assignmentGeneration || destination == null) return;
      route = fetched;
      notifyListeners();
    } catch (e) {
      if (id == assignmentId && generation == _assignmentGeneration) {
        syncError = explainError(e, fallback: 'تعذر تحديث مسار الزيارة');
        notifyListeners();
      }
    }
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
    if (reqId == requestId && invoiceAbsent) {
      bill = null;
      billLoading = false;
      notifyListeners();
      return;
    }
    final sessGen = _sessionGeneration;
    final billGen = ++_billGeneration;
    billLoading = true;
    notifyListeners();
    try {
      final fetched = BillInfo.fromJson(await api.getMap('/v1/nurse/requests/$reqId/bill'));
      if (sessGen != _sessionGeneration || billGen != _billGeneration) return;
      bill = fetched;
      _collectionRequestId = reqId;
      notifyListeners();
    } catch (e) {
      if (sessGen != _sessionGeneration || billGen != _billGeneration) return;
      error = explainError(e, fallback: 'تعذر تحميل تفاصيل الفاتورة');
    } finally {
      if (sessGen == _sessionGeneration && billGen == _billGeneration) {
        billLoading = false;
        notifyListeners();
      }
    }
  }

  Future<bool> collectCash(int amount, {String? targetRequestId}) async {
    final b = bill;
    if (b == null || amount <= 0 || collecting) return false;
    final session = _sessionGeneration;
    final generation = _assignmentGeneration;
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
      final owner = await api.currentUserId();
      if (owner == null || owner.isEmpty || session != _sessionGeneration) return false;
      // Keep issued operation keys stable across upgrades. The request bill is
      // server-authorized for this account and session before collection opens.
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
      if (session != _sessionGeneration || generation != _assignmentGeneration) return false;
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
      if (session != _sessionGeneration || generation != _assignmentGeneration) return false;
      if (!collectionShort) {
        unpaidInvoices = unpaidInvoices.where((inv) => inv.requestId != id).toList();
        if (activeUnpaidInvoice?.requestId == id) activeUnpaidInvoice = null;
      }
      return !collectionShort;
    } catch (e) {
      if (session != _sessionGeneration || generation != _assignmentGeneration) return false;
      collectionMessage = explainError(e, fallback: 'تعذر تأكيد التحصيل النقدي. حاول مرة أخرى.');
      collectionShort = true;
      return false;
    } finally {
      if (session == _sessionGeneration && generation == _assignmentGeneration) {
        collecting = false;
        notifyListeners();
      }
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
    _restoreCancelToken?.cancel('session_changed');
    loading = false;
    busy = false;
    collecting = false;
    billLoading = false;
    _billGeneration++;
    error = null;
    unpaidInvoices = const [];
    assignments = const [];
    activeUnpaidInvoice = null;
    _collectionRequestId = null;
    _resetState(keepCancellationNotice: false);
  }

  void _resetActiveFieldVisit({required bool keepCancellationNotice}) {
    _assignmentGeneration++;
    _billGeneration++;
    _detailCancelToken?.cancel('assignment_changed');
    _detailCancelToken = null;
    stopNavigation();
    busy = false;
    billLoading = false;
    visitOutcome = null;
    visitOutcomeReason = null;
    invoiceAbsent = false;
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
    _sessionGeneration++;
    _restoreGeneration++;
    _assignmentGeneration++;
    _billGeneration++;
    _restoreCancelToken?.cancel('disposed');
    _detailCancelToken?.cancel('disposed');
    stopNavigation();
    _sub.cancel();
    super.dispose();
  }
}
