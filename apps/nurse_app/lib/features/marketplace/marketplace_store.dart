import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:tamreedy_core/tamreedy_core.dart';

class MarketplaceStore extends ChangeNotifier {
  final TamreedyApi api;
  final RealtimeEventBus eventBus;
  final bool Function() _canUseOpenMarketplace;

  MarketplaceStore({
    required this.api,
    required this.eventBus,
    bool Function()? canUseOpenMarketplace,
  }) : _canUseOpenMarketplace = canUseOpenMarketplace ?? (() => false) {
    _sub = eventBus
        .whereType(const {
          'marketplace.request.published',
          'marketplace.request.updated',
          'marketplace.proposal.accepted',
        })
        .listen((_) {
          refreshAll(silent: true);
        });
  }

  late final StreamSubscription<RealtimeEvent> _sub;

  bool loading = false;
  String? error;
  double? maxDistanceKm;
  List<Map<String, dynamic>> requests = const [];
  List<Map<String, dynamic>> myProposals = const [];
  List<Map<String, dynamic>> completedHistory = const [];

  int _sessionGen = 0;

  void resetForSessionChange() {
    _sessionGen++;
    requests = const [];
    myProposals = const [];
    completedHistory = const [];
    maxDistanceKm = null;
    loading = false;
    error = null;
    notifyListeners();
  }

  Future<void> refreshAll({bool silent = false}) async {
    if (kDemoMode) return;
    final gen = _sessionGen;
    if (!silent) {
      loading = true;
      error = null;
      notifyListeners();
    }
    try {
      final results = await Future.wait([
        _canUseOpenMarketplace()
            ? api.getMarketplaceRequests(maxDistanceKm: maxDistanceKm)
            : Future<List<dynamic>>.value(const []),
        api.getMyProposals().catchError((_) => const []),
        api.getList('/v1/nurse/me/history').catchError((_) => const []),
      ]);
      if (gen != _sessionGen) return;
      requests = results[0]
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      myProposals = results[1]
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      completedHistory = results[2]
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      error = null;
    } catch (e) {
      if (gen != _sessionGen) return;
      if (!silent) {
        error = explainError(e, fallback: 'تعذر تحميل السوق المفتوح');
      }
    } finally {
      if (gen == _sessionGen) {
        loading = false;
        notifyListeners();
      }
    }
  }

  void setMaxDistance(double? km) {
    maxDistanceKm = km;
    refreshAll();
  }

  Future<void> toggleSave(String requestId, bool currentlySaved) async {
    _requireOpenMarketplace();
    if (currentlySaved) {
      await api.delete('/v1/marketplace/requests/$requestId/save');
    } else {
      await api.post('/v1/marketplace/requests/$requestId/save', {});
    }
    await refreshAll(silent: true);
  }

  Future<void> submitProposal(
    String requestId, {
    int? estimatedMinutes,
    String? specificTime,
    String? note,
  }) async {
    _requireOpenMarketplace();
    await api.submitProposal(
      requestId,
      estimatedMinutes: estimatedMinutes,
      specificTime: specificTime,
      note: note,
    );
    await refreshAll(silent: true);
  }

  Future<void> withdrawProposal(String proposalId, {String? reason}) async {
    await api.withdrawProposal(proposalId, reason: reason);
    await refreshAll(silent: true);
  }

  void _requireOpenMarketplace() {
    if (!_canUseOpenMarketplace()) {
      throw const ApiFailure(
        kind: ApiErrorKind.featureUnavailable,
        code: 'OPEN_MARKETPLACE_UNAVAILABLE',
        messageAr: 'السوق المفتوح غير متاح حاليًا لتقديم عروض جديدة',
      );
    }
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
