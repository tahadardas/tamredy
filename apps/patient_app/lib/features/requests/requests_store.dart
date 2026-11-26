import 'dart:async';
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
  String? error;

  List<TypedCareRequest> _allRequests = const [];
  final Map<String, TypedCareRequest> _detailsCache = {};
  final Map<String, List<TypedProposal>> _proposalsCache = {};
  final Map<String, String> _lastCancellationAttemptKey = {};

  List<TypedCareRequest> get allRequests => _allRequests;

  /// In-flight instant/open/assigned/in-visit requests (excluding future scheduled until they enter dispatch).
  List<TypedCareRequest> get activeRequests => _allRequests
      .where((r) => r.isActive && r.status != 'SCHEDULED')
      .toList();

  List<TypedCareRequest> get upcomingRequests =>
      _allRequests.where((r) => r.status == 'SCHEDULED').toList();

  List<TypedCareRequest> get unpaidBills =>
      _allRequests.where((r) => r.isUnpaid).toList();

  List<TypedCareRequest> get pastRequests => _allRequests
      .where((r) => !r.isActive && !r.isUnpaid)
      .toList();

  TypedCareRequest? get primaryActiveRequest =>
      activeRequests.isNotEmpty ? activeRequests.first : null;

  TypedCareRequest? requestById(String id) {
    final cached = _detailsCache[id];
    if (cached != null) return cached;
    for (final r in _allRequests) {
      if (r.id == id) return r;
    }
    return null;
  }

  List<TypedProposal> proposalsFor(String requestId) =>
      _proposalsCache[requestId] ?? const [];

  void _onRealtimeEvent(RealtimeEvent ev) {
    final reqId = ev.payload['requestId']?.toString() ?? ev.payload['request_id']?.toString();
    // Trigger targeted silent refresh of requests list + affected detail/proposals
    refreshAll(silent: true);
    if (reqId != null && reqId.isNotEmpty) {
      if (_detailsCache.containsKey(reqId) ||
          ev.type.startsWith('request.') ||
          ev.type.startsWith('visit.')) {
        loadRequestDetail(reqId);
      }
      if (ev.type.contains('proposal')) {
        loadProposals(reqId);
      }
    }
  }

  Future<void> refreshAll({bool silent = false}) async {
    if (kDemoMode) return;
    if (!silent) {
      loading = true;
      error = null;
      notifyListeners();
    }
    try {
      final results = await Future.wait([
        api.getMap('/v1/me/active-request'),
        api.getMap('/v1/requests/mine?limit=40'),
      ]);

      final activeEnvelope = results[0];
      final historyEnvelope = results[1];
      final map = <String, TypedCareRequest>{};

      final activeReq = activeEnvelope['request'];
      if (activeEnvelope['hasActive'] == true && activeReq is Map) {
        final parsed = TypedCareRequest.fromJson(Map<String, dynamic>.from(activeReq));
        map[parsed.id] = parsed;
      }

      for (final raw in (activeEnvelope['unpaidInvoices'] as List? ?? const [])) {
        if (raw is Map) {
          final parsed = TypedCareRequest.fromJson(Map<String, dynamic>.from(raw));
          map.putIfAbsent(parsed.id, () => parsed);
        }
      }

      for (final raw in (historyEnvelope['items'] as List? ?? const [])) {
        if (raw is Map) {
          final parsed = TypedCareRequest.fromJson(Map<String, dynamic>.from(raw));
          final existing = map[parsed.id];
          // Prefer detailed entry if version is equal or higher
          if (existing == null || parsed.version > existing.version) {
            map[parsed.id] = parsed;
          }
        }
      }

      _allRequests = map.values.toList()
        ..sort((a, b) => (b.createdAt ?? DateTime(2000)).compareTo(a.createdAt ?? DateTime(2000)));
      error = null;
    } catch (e) {
      if (!silent) {
        error = explainError(e, fallback: 'تعذر تحديث قائمة الطلبات');
      }
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void registerCreatedRequest(TypedCareRequest req) {
    _detailsCache[req.id] = req;
    _allRequests = [req, ..._allRequests.where((r) => r.id != req.id)];
    notifyListeners();
    if (!kDemoMode) {
      loadRequestDetail(req.id);
    }
  }

  Future<TypedCareRequest?> loadRequestDetail(String requestId) async {
    if (kDemoMode) return requestById(requestId);
    try {
      final res = await api.getMap('/v1/requests/$requestId');
      final parsed = TypedCareRequest.fromJson(res);
      _detailsCache[requestId] = parsed;
      final idx = _allRequests.indexWhere((r) => r.id == requestId);
      if (idx >= 0) {
        _allRequests = [..._allRequests]..[idx] = parsed;
      } else {
        _allRequests = [parsed, ..._allRequests];
      }
      notifyListeners();
      return parsed;
    } catch (_) {
      return requestById(requestId);
    }
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

  Future<bool> acceptProposal(String requestId, String proposalId) async {
    await api.acceptProposal(requestId, proposalId);
    await Future.wait([loadRequestDetail(requestId), refreshAll(silent: true)]);
    return true;
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
