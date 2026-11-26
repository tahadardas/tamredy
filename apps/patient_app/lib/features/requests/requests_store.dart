import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:tamreedy_core/tamreedy_core.dart';

class RequestsStore extends ChangeNotifier {
  final TamreedyApi api;
  final RealtimeEventBus eventBus;

  RequestsStore({required this.api, required this.eventBus}) {
    _sub = eventBus.whereType(const {
      'request.created',
      'request.assigned',
      'request.clinical_review_changed',
      'request.cancelled',
      'marketplace.request.published',
      'marketplace.request.updated',
      'marketplace.proposal.created',
      'marketplace.proposal.withdrawn',
      'visit.depart',
      'visit.arrive',
      'visit.start',
      'visit.complete',
      'visit.interrupted',
      'payment.paid',
      'payment.partially_paid',
      'payment.tip',
    }).listen(_onRealtimeEvent);
  }

  late final StreamSubscription<RealtimeEvent> _sub;

  bool loading = false;
  bool loadingMore = false;
  String? error;

  final Map<String, TypedCareRequest> _requestsById = {};
  final Map<String, TypedCareRequest> _detailsCache = {};
  final Map<String, List<TypedProposal>> _proposalsCache = {};
  final Map<String, String> _lastCancellationAttemptKey = {};
  final Map<String, String> _proposalAcceptKeys = {};
  List<Map<String, dynamic>> _pendingReviews = const [];
  String? _nextCursor;

  List<TypedCareRequest> _allRequests = const [];

  int _sessionGeneration = 0;
  int _refreshGeneration = 0;
  Future<void>? _refreshInFlight;
  CancelToken? _refreshCancelToken;

  final Map<String, int> _detailGeneration = {};
  final Map<String, Future<TypedCareRequest?>> _detailInFlight = {};
  final Map<String, CancelToken> _detailCancelTokens = {};

  List<TypedCareRequest> get allRequests => _allRequests;
  List<Map<String, dynamic>> get pendingReviews => _pendingReviews;
  bool get hasMoreHistory => _nextCursor != null && _nextCursor!.isNotEmpty;

  /// In-flight instant/open/assigned/in-visit/unfulfilled requests (excluding future scheduled until dispatch).
  List<TypedCareRequest> get activeRequests => _allRequests
      .where((r) => r.isActive && r.status != 'SCHEDULED')
      .toList();

  List<TypedCareRequest> get upcomingRequests =>
      _allRequests.where((r) => r.status == 'SCHEDULED').toList();

  List<TypedCareRequest> get unpaidBills =>
      _allRequests.where((r) => r.isUnpaid).toList();

  List<TypedCareRequest> get unfulfilledRequests =>
      _allRequests.where((r) => r.isUnfulfilled).toList();

  List<TypedCareRequest> get pastRequests => _allRequests
      .where((r) => !r.isActive && !r.isUnpaid && !r.isUnfulfilled)
      .toList();

  TypedCareRequest? get primaryActiveRequest =>
      activeRequests.isNotEmpty ? activeRequests.first : null;

  TypedCareRequest? requestById(String id) {
    final cached = _detailsCache[id];
    final inMap = _requestsById[id];
    if (cached != null && inMap != null) return inMap.mergePreferRicher(cached);
    return cached ?? inMap;
  }

  List<TypedProposal> proposalsFor(String requestId) =>
      _proposalsCache[requestId] ?? const [];

  void _upsertRequest(TypedCareRequest parsed, {bool isDetail = false}) {
    if (parsed.id.isEmpty) return;
    final current = _requestsById[parsed.id];
    final merged = current == null ? parsed : current.mergePreferRicher(parsed);
    _requestsById[parsed.id] = merged;
    if (isDetail || merged.hasFullDetail) {
      final cached = _detailsCache[parsed.id];
      _detailsCache[parsed.id] = cached == null ? merged : cached.mergePreferRicher(merged);
    }
  }

  void _rebuildSortedList() {
    _allRequests = _requestsById.values.toList()
      ..sort((a, b) => (b.createdAt ?? DateTime(2000)).compareTo(a.createdAt ?? DateTime(2000)));
  }

  void _onRealtimeEvent(RealtimeEvent ev) {
    final reqId = ev.payload['requestId']?.toString() ?? ev.payload['request_id']?.toString();
    final evVer = int.tryParse('${ev.payload['entityVersion'] ?? ev.payload['version'] ?? ''}');
    if (reqId != null && reqId.isNotEmpty) {
      final current = requestById(reqId);
      if (current != null && evVer != null && evVer < current.version) {
        return;
      }
      if (ev.type.contains('proposal')) {
        loadProposals(reqId);
      }
      if (ev.type.startsWith('request.') ||
          ev.type.startsWith('visit.') ||
          ev.type.startsWith('marketplace.') ||
          ev.type.startsWith('payment.')) {
        loadRequestDetail(reqId, force: true);
        if (current == null || ev.type == 'request.created' || ev.type == 'request.cancelled') {
          refreshActiveOnly();
        }
        return;
      }
    }
    refreshActiveOnly();
  }

  /// Refreshes active requests/unpaid bills/pending reviews without refetching full history.
  Future<void> refreshActiveOnly() async {
    if (kDemoMode) return;
    final gen = ++_refreshGeneration;
    final sessGen = _sessionGeneration;
    try {
      final activeEnvelope = await api.getMap('/v1/me/active-request');
      if (gen != _refreshGeneration || sessGen != _sessionGeneration) return;
      _ingestActiveEnvelope(activeEnvelope);
      _rebuildSortedList();
      notifyListeners();
    } catch (_) {}
  }

  void _ingestActiveEnvelope(Map<String, dynamic> activeEnvelope) {
    final activeList = activeEnvelope['requests'] as List? ?? const [];
    for (final raw in activeList) {
      if (raw is Map) {
        _upsertRequest(TypedCareRequest.fromJson(Map<String, dynamic>.from(raw), fullDetail: true));
      }
    }
    final activeReq = activeEnvelope['request'];
    if (activeEnvelope['hasActive'] == true && activeReq is Map) {
      _upsertRequest(TypedCareRequest.fromJson(Map<String, dynamic>.from(activeReq), fullDetail: true));
    }
    for (final raw in (activeEnvelope['unpaidInvoices'] as List? ?? const [])) {
      if (raw is Map) {
        _upsertRequest(TypedCareRequest.fromJson(Map<String, dynamic>.from(raw)));
      }
    }
    final rawReviews = activeEnvelope['pendingReviews'] as List? ?? const [];
    _pendingReviews = [
      for (final r in rawReviews)
        if (r is Map) Map<String, dynamic>.from(r),
    ];
  }

  Future<void> refreshAll({bool silent = false, bool force = false}) {
    if (kDemoMode) return Future.value();
    if (!force && _refreshInFlight != null) return _refreshInFlight!;
    _refreshCancelToken?.cancel('superseded');
    final cancelToken = CancelToken();
    _refreshCancelToken = cancelToken;
    final future = _doRefreshAll(silent: silent, cancelToken: cancelToken);
    _refreshInFlight = future.whenComplete(() {
      if (identical(_refreshInFlight, future)) _refreshInFlight = null;
    });
    return _refreshInFlight!;
  }

  Future<void> _doRefreshAll({required bool silent, required CancelToken cancelToken}) async {
    final gen = ++_refreshGeneration;
    final sessGen = _sessionGeneration;
    if (!silent) {
      loading = true;
      error = null;
      notifyListeners();
    }
    try {
      final results = await Future.wait([
        api.getMap('/v1/me/active-request', cancelToken: cancelToken),
        api.getMap('/v1/requests/mine?limit=40', cancelToken: cancelToken),
      ]);
      if (gen != _refreshGeneration || sessGen != _sessionGeneration || cancelToken.isCancelled) {
        return;
      }

      final activeEnvelope = results[0];
      final historyEnvelope = results[1];

      _ingestActiveEnvelope(activeEnvelope);

      for (final raw in (historyEnvelope['items'] as List? ?? const [])) {
        if (raw is Map) {
          _upsertRequest(TypedCareRequest.fromJson(Map<String, dynamic>.from(raw)));
        }
      }
      _nextCursor = historyEnvelope['nextCursor']?.toString();
      _rebuildSortedList();
      error = null;
    } catch (e) {
      if (cancelToken.isCancelled || sessGen != _sessionGeneration) return;
      if (!silent) {
        error = explainError(e, fallback: 'تعذر تحديث قائمة الطلبات');
      }
    } finally {
      if (gen == _refreshGeneration && sessGen == _sessionGeneration) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMoreHistory() async {
    final cursor = _nextCursor;
    if (kDemoMode || loadingMore || cursor == null || cursor.isEmpty) return;
    loadingMore = true;
    notifyListeners();
    final sessGen = _sessionGeneration;
    try {
      final historyEnvelope = await api.getMap(
        '/v1/requests/mine?limit=40&cursor=${Uri.encodeQueryComponent(cursor)}',
      );
      if (sessGen != _sessionGeneration) return;
      for (final raw in (historyEnvelope['items'] as List? ?? const [])) {
        if (raw is Map) {
          _upsertRequest(TypedCareRequest.fromJson(Map<String, dynamic>.from(raw)));
        }
      }
      _nextCursor = historyEnvelope['nextCursor']?.toString();
      _rebuildSortedList();
    } catch (_) {
    } finally {
      if (sessGen == _sessionGeneration) {
        loadingMore = false;
        notifyListeners();
      }
    }
  }

  void registerCreatedRequest(TypedCareRequest req) {
    _upsertRequest(req, isDetail: true);
    _rebuildSortedList();
    notifyListeners();
    if (!kDemoMode) {
      loadRequestDetail(req.id, force: true);
    }
  }

  Future<TypedCareRequest?> loadRequestDetail(String requestId, {bool force = false}) {
    if (kDemoMode) return Future.value(requestById(requestId));
    if (!force && _detailInFlight.containsKey(requestId)) {
      return _detailInFlight[requestId]!;
    }
    _detailCancelTokens[requestId]?.cancel('superseded');
    final cancelToken = CancelToken();
    _detailCancelTokens[requestId] = cancelToken;
    final future = _doLoadRequestDetail(requestId, cancelToken);
    _detailInFlight[requestId] = future.whenComplete(() {
      if (identical(_detailInFlight[requestId], future)) {
        _detailInFlight.remove(requestId);
      }
    });
    return _detailInFlight[requestId]!;
  }

  Future<TypedCareRequest?> _doLoadRequestDetail(String requestId, CancelToken cancelToken) async {
    final gen = (_detailGeneration[requestId] ?? 0) + 1;
    _detailGeneration[requestId] = gen;
    final sessGen = _sessionGeneration;
    try {
      final res = await api.getMap('/v1/requests/$requestId', cancelToken: cancelToken);
      if (gen != _detailGeneration[requestId] || sessGen != _sessionGeneration || cancelToken.isCancelled) {
        return requestById(requestId);
      }
      final parsed = TypedCareRequest.fromJson(res, fullDetail: true);
      final current = requestById(requestId);
      if (current != null && parsed.version < current.version) {
        return current;
      }
      _upsertRequest(parsed, isDetail: true);
      _rebuildSortedList();
      notifyListeners();
      return requestById(requestId);
    } catch (_) {
      return requestById(requestId);
    }
  }

  void resetForSessionChange() {
    _sessionGeneration++;
    _refreshGeneration++;
    _refreshCancelToken?.cancel('session_changed');
    _refreshCancelToken = null;
    _refreshInFlight = null;
    for (final c in _detailCancelTokens.values) {
      c.cancel('session_changed');
    }
    _detailCancelTokens.clear();
    _detailInFlight.clear();
    _detailGeneration.clear();
    _requestsById.clear();
    _detailsCache.clear();
    _proposalsCache.clear();
    _lastCancellationAttemptKey.clear();
    _proposalAcceptKeys.clear();
    _pendingReviews = const [];
    _nextCursor = null;
    _allRequests = const [];
    loading = false;
    loadingMore = false;
    error = null;
    notifyListeners();
  }

  Future<List<TypedProposal>> loadProposals(String requestId) async {
    if (kDemoMode) return proposalsFor(requestId);
    final raw = await api.getRequestProposals(requestId);
    final list = [
      for (final item in raw)
        if (item is Map) TypedProposal.fromJson(Map<String, dynamic>.from(item)),
    ];
    _proposalsCache[requestId] = list;
    notifyListeners();
    return list;
  }

  Future<bool> acceptProposal(
    String requestId,
    String proposalId, {
    int? requestVersion,
    int? proposalVersion,
  }) async {
    final req = requestById(requestId);
    TypedProposal? matchingProposal;
    for (final p in proposalsFor(requestId)) {
      if (p.id == proposalId) {
        matchingProposal = p;
        break;
      }
    }
    final effReqVer = requestVersion ?? req?.version;
    final effPropVer = proposalVersion ?? matchingProposal?.proposalVersion;
    final signature = '$requestId:$proposalId:$effReqVer:$effPropVer';
    final idemKey = _proposalAcceptKeys.putIfAbsent(signature, () => api.newIdempotencyKey());
    try {
      await api.acceptProposal(
        requestId,
        proposalId,
        requestVersion: effReqVer,
        proposalVersion: effPropVer,
        idempotencyKey: idemKey,
      );
      _proposalAcceptKeys.remove(signature);
      await Future.wait([loadRequestDetail(requestId, force: true), refreshActiveOnly()]);
      return true;
    } catch (e) {
      // On version conflict, refresh request & proposals immediately so patient reviews updated offer
      if (e is ApiFailure && e.kind == ApiErrorKind.conflict) {
        await Future.wait([loadRequestDetail(requestId, force: true), loadProposals(requestId)]);
      }
      rethrow;
    }
  }

  Future<bool> declineProposal(String requestId, String proposalId, {String? reason}) async {
    await api.declineProposal(requestId, proposalId, reason: reason);
    await loadProposals(requestId);
    return true;
  }

  Future<void> switchToOpenMarketplace(String requestId, {int durationMinutes = 60}) async {
    await api.switchRequestToOpenMarketplace(requestId, durationMinutes: durationMinutes);
    await Future.wait([loadRequestDetail(requestId), refreshAll(silent: true)]);
  }

  Future<void> retryInstantDispatch(String requestId) async {
    await api.retryInstantDispatch(requestId);
    await Future.wait([loadRequestDetail(requestId), refreshAll(silent: true)]);
  }

  Future<void> extendOpenWindow(String requestId, {int additionalMinutes = 30}) async {
    await api.extendWaitWindow(requestId, additionalMinutes: additionalMinutes);
    await loadRequestDetail(requestId);
  }

  Future<Map<String, dynamic>> loadCancellationPolicy(String requestId) async {
    if (kDemoMode) return {'canCancel': true, 'requiresAcknowledgement': false};
    return api.getMap('/v1/requests/$requestId/cancellation-policy');
  }

  Future<void> cancelRequest(
    String requestId, {
    required String reasonCode,
    String? reasonNote,
    int? expectedVersion,
    bool policyAcknowledged = false,
  }) async {
    if (kDemoMode) {
      _allRequests = _allRequests.where((r) => r.id != requestId).toList();
      _detailsCache.remove(requestId);
      notifyListeners();
      return;
    }
    final signature = '$requestId:$reasonCode:$expectedVersion:$policyAcknowledged';
    final idemKey = _lastCancellationAttemptKey.putIfAbsent(
      signature,
      () => api.newIdempotencyKey(),
    );
    await api.post('/v1/requests/$requestId/cancel', {
      'reasonCode': reasonCode,
      if (reasonNote != null && reasonNote.trim().isNotEmpty) 'reasonNote': reasonNote.trim(),
      'idempotencyKey': idemKey,
      'expectedVersion': ?expectedVersion,
      'policyAcknowledged': policyAcknowledged,
    });
    _lastCancellationAttemptKey.remove(signature);
    await Future.wait([loadRequestDetail(requestId), refreshAll(silent: true)]);
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
