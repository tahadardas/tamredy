import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../../guardian.dart';
import 'pending_cash_collection_store.dart';

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
  bool billIsStale = true;
  bool _cashRecoveryBlocked = false;
  PendingCashCollection? pendingCashCollection;
  late final _cashOperations = PendingCashCollectionStore(api);
  bool get canStartCashCollection => !collecting && !billLoading && !billIsStale &&
      !_cashRecoveryBlocked && pendingCashCollection == null &&
      (kDemoMode || bill?.cashCollectionSupported == true);
  bool get canResumeCashCollection => !collecting && !billLoading && !billIsStale &&
      pendingCashCollection?.status == CashCollectionStatus.pending;

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
        if (collecting) return;
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

  Future<BillInfo?> loadBill({String? targetRequestId}) =>
      _refreshBill(targetRequestId: targetRequestId);

  Future<BillInfo?> _refreshBill({String? targetRequestId, bool afterCollection = false}) async {
    if (collecting && !afterCollection) return null;
    final reqId = targetRequestId ?? _collectionRequestId ?? activeUnpaidInvoice?.requestId ?? requestId;
    if (kDemoMode) {
      bill = const BillInfo(due:45000,minutes:35,gross:45000,discount:0,collected:0,
        remaining:45000,status:'DUE',visitId:'demo-visit-1',nurseEarning:36000);
      billIsStale = false;
      notifyListeners();
      return bill;
    }
    if (reqId == null || reqId.isEmpty || (reqId == requestId && invoiceAbsent)) return null;
    final session = _sessionGeneration;
    final generation = ++_billGeneration;
    bool current() => session == _sessionGeneration && generation == _billGeneration;
    billLoading = true;
    billIsStale = true;
    notifyListeners();
    try {
      final response = await api.getMap('/v1/nurse/requests/$reqId/bill', cancelToken: CancelToken());
      final fetched = BillInfo.fromJson(response);
      if (!current()) return null;
      if (fetched.requestId != reqId || fetched.invoiceId == null || fetched.invoiceVersion == null) {
        throw const FormatException('بيانات الفاتورة غير مكتملة');
      }
      bill = fetched;
      _collectionRequestId = reqId;
      error = null;
      final owner = await api.currentUserId();
      if (!current()) return null;
      if (owner == null || owner.isEmpty) throw const FormatException('تعذر التحقق من الحساب');
      var operation = await _cashOperations.read(owner,fetched);
      if (!current()) return null;
      operation ??= await _cashOperations.recoverLegacy(owner,fetched);
      if (!current()) return null;
      if (operation?.status == CashCollectionStatus.reconciled) operation = null;
      pendingCashCollection = operation;
      if (!afterCollection && operation?.status == CashCollectionStatus.pending && operation!.legacyKey == null) {
        final receipt = await api.readCashCollection(reqId,operation.key);
        if (!current()) return null;
        if (receipt['found'] == true) {
          operation = operation.confirm(receipt);
          await _cashOperations.save(owner,fetched,operation);
          if (!current()) return null;
          pendingCashCollection = operation;
        }
      }
      if (operation?.status == CashCollectionStatus.confirmed &&
          fetched.invoiceVersion! >= operation!.invoiceVersion!) {
        await _cashOperations.reconcile(owner,fetched,operation);
        if (!current()) return null;
        pendingCashCollection = null;
      }
      _cashRecoveryBlocked = false;
      billIsStale = false;
      return fetched;
    } catch (e) {
      if (!current()) return null;
      _cashRecoveryBlocked = true;
      error = e is FormatException ? e.message : explainError(e, fallback:'تعذر مزامنة الفاتورة');
      return null;
    } finally {
      if (current()) {
        billLoading = false;
        notifyListeners();
      }
    }
  }

  Future<CashCollectionOutcome> resumeCashCollection() async {
    final operation = pendingCashCollection;
    if (operation == null || !canResumeCashCollection) return CashCollectionOutcome.failed;
    return _collectCash(operation.amount, existing:operation);
  }

  Future<CashCollectionOutcome> collectCash(int amount, {String? targetRequestId}) {
    if (!canStartCashCollection || (targetRequestId != null && targetRequestId != bill?.requestId)) {
      return Future.value(CashCollectionOutcome.failed);
    }
    return _collectCash(amount);
  }

  Future<CashCollectionOutcome> _collectCash(int amount, {PendingCashCollection? existing}) async {
    final b = bill;
    if (b == null || (b.status == 'PAID' && existing == null) || amount <= 0 || amount > 1000000000 || collecting) {
      return CashCollectionOutcome.failed;
    }
    final session = _sessionGeneration;
    final generation = _assignmentGeneration;
    bool current() => session == _sessionGeneration && generation == _assignmentGeneration &&
        bill?.invoiceId == b.invoiceId;
    collecting = true;
    collectionMessage = null;
    notifyListeners();
    try {
      if (kDemoMode) {
        final r = applyCollection(b.payable,b.collected,amount);
        bill = BillInfo(due:b.due,minutes:b.minutes,gross:b.gross,discount:b.discount,
          collected:r.collected,remaining:r.remaining,status:r.paid?'PAID':'PARTIAL',visitId:b.visitId,
          tip:b.tip,nurseEarning:b.nurseEarning);
        collectionMessage = r.message;
        return r.paid ? CashCollectionOutcome.fullyConfirmed : CashCollectionOutcome.partialConfirmed;
      }
      final owner = await api.currentUserId();
      if (!current() || owner == null || owner.isEmpty || b.requestId == null || b.invoiceId == null ||
          !b.cashCollectionSupported || (existing != null && !existing.matches(b,owner))) {
        return CashCollectionOutcome.failed;
      }
      final operation = existing ?? _cashOperations.create(owner,b,amount);
      await _cashOperations.save(owner,b,operation);
      if (!current()) return CashCollectionOutcome.failed;
      pendingCashCollection = operation;
      final lookup = existing == null ? null : await api.readCashCollection(b.requestId!,operation.key);
      if (!current()) return CashCollectionOutcome.failed;
      if (lookup != null && (lookup['invoiceId'] != b.invoiceId || lookup['currencyCode'] != b.currencyCode)) {
        throw const FormatException('بيانات التحصيل لا تطابق الفاتورة');
      }
      if (lookup?['found'] != true && b.status == 'PAID') {
        final failed = PendingCashCollection({...operation.data, 'status':CashCollectionStatus.failedRequiresAction.name});
        await _cashOperations.save(owner,b,failed);
        if (current()) {
          pendingCashCollection = failed;
          collectionMessage = 'الفاتورة مدفوعة، لكن لم يُعثر على إيصال العملية المحفوظة. راجع الإدارة.';
        }
        return CashCollectionOutcome.failed;
      }
      final receipt = lookup?['found'] == true ? lookup! : await api.post(
        '/v1/nurse/requests/${b.requestId}/collect', {'amount':operation.amount}, {'Idempotency-Key':operation.key});
      if (!current()) return CashCollectionOutcome.failed;
      final confirmed = operation.confirm(receipt);
      await _cashOperations.save(owner,b,confirmed);
      if (!current()) return CashCollectionOutcome.failed;
      pendingCashCollection = confirmed;
      final refreshed = await _refreshBill(targetRequestId:b.requestId,afterCollection:true);
      if (!current()) return CashCollectionOutcome.failed;
      if (refreshed == null || pendingCashCollection != null) {
        collectionMessage = 'تم تسجيل الدفعة، جارٍ تحديث الفاتورة.';
        return CashCollectionOutcome.pendingReconciliation;
      }
      final paid = refreshed.status == 'PAID';
      collectionShort = !paid;
      final change = MoneyAmount.parse(receipt['change'] as Object? ?? 0,b.currencyCode,decimalPlaces:0);
      collectionMessage = paid
          ? (change.amountMinor > BigInt.zero ? 'تم التحصيل بالكامل — أعد للمريض ${change.formatted}' : 'تم تحصيل كامل المبلغ بنجاح')
          : 'تم استلام دفعة جزئية — المتبقي ${refreshed.money('remaining').formatted}';
      if (paid) {
        unpaidInvoices = unpaidInvoices.where((inv) => inv.requestId != b.requestId).toList();
        if (activeUnpaidInvoice?.requestId == b.requestId) activeUnpaidInvoice = null;
      }
      return paid ? CashCollectionOutcome.fullyConfirmed : CashCollectionOutcome.partialConfirmed;
    } catch (e) {
      if (!current()) return CashCollectionOutcome.failed;
      final confirmed = pendingCashCollection?.status == CashCollectionStatus.confirmed;
      collectionMessage = confirmed ? 'تم تسجيل الدفعة، جارٍ تحديث الفاتورة.' :
          explainError(e, fallback:'تعذر تأكيد التحصيل. تحقق من العملية المحفوظة.');
      return confirmed ? CashCollectionOutcome.pendingReconciliation : CashCollectionOutcome.failed;
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
    pendingCashCollection = null;
    billIsStale = true;
    _cashRecoveryBlocked = false;
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
    collecting = false;
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
