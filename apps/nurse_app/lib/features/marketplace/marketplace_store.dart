import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:tamreedy_core/tamreedy_core.dart';

class MarketplaceStore extends ChangeNotifier {
  final TamreedyApi api;
  final RealtimeEventBus eventBus;

  MarketplaceStore({required this.api, required this.eventBus}) {
    _sub = eventBus.whereType(const {
      'marketplace.request.published',
      'marketplace.request.updated',
      'marketplace.proposal.accepted',
    }).listen((_) {
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

  Future<void> refreshAll({bool silent = false}) async {
    if (kDemoMode) return;
    if (!silent) {
      loading = true;
      error = null;
      notifyListeners();
    }
    try {
      final results = await Future.wait([
        api.getMarketplaceRequests(maxDistanceKm: maxDistanceKm),
        api.getMyProposals().catchError((_) => const []),
        api.getList('/v1/nurse/me/history').catchError((_) => const []),
      ]);
      requests = results[0].whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      myProposals = results[1].whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      completedHistory = results[2].whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      error = null;
    } catch (e) {
      if (!silent) {
        error = explainError(e, fallback: 'تعذر تحميل السوق المفتوح');
      }
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void setMaxDistance(double? km) {
    maxDistanceKm = km;
    refreshAll();
  }

  Future<void> toggleSave(String requestId, bool currentlySaved) async {
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

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
