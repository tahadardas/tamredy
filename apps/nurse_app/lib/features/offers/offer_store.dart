import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../../alarm.dart';

class OfferStore extends ChangeNotifier {
  final TamreedyApi api;
  final RealtimeEventBus eventBus;
  final void Function(String requestId, String assignmentId) onOfferAccepted;

  OfferStore({
    required this.api,
    required this.eventBus,
    required this.onOfferAccepted,
  }) {
    _sub = eventBus
        .whereType(const {'offer.created', 'offer.closed', 'offer.expired'})
        .listen(_onEvent);
  }

  late final StreamSubscription<RealtimeEvent> _sub;

  TypedNurseOffer? activeOffer;
  final List<TypedNurseOffer> _offerQueue = [];
  final Set<String> _closedOfferIds = {};
  Duration serverOffset = Duration.zero;
  Map<String, dynamic>? commitmentWarning;
  bool acting = false;
  String? _actingOfferId;
  bool muted = false;
  String? error;
  Timer? _expiryTimer;
  int _sessionGen = 0;

  void resetForSessionChange() {
    _sessionGen++;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    for (final o in _offerQueue) {
      OfferAlarm.cancelOffer(o.offerId);
    }
    if (activeOffer != null) {
      OfferAlarm.cancelOffer(activeOffer!.offerId);
    }
    _offerQueue.clear();
    _closedOfferIds.clear();
    activeOffer = null;
    _actingOfferId = null;
    commitmentWarning = null;
    acting = false;
    muted = false;
    error = null;
    notifyListeners();
  }

  void _onEvent(RealtimeEvent ev) {
    if (ev.type == 'offer.created') {
      fetchOpenOffers();
      return;
    }
    final offerId = ev.payload['offerId']?.toString() ?? ev.payload['offer_id']?.toString();
    if (offerId != null && offerId.isNotEmpty) {
      _closedOfferIds.add(offerId);
      OfferAlarm.cancelOffer(offerId);
      _offerQueue.removeWhere((o) => o.offerId == offerId);
      if (activeOffer?.offerId == offerId && _actingOfferId != offerId) {
        _advanceQueue();
      }
    }
  }

  Future<void> fetchOpenOffers() async {
    if (kDemoMode) return;
    final gen = _sessionGen;
    try {
      final raw = await api.getList('/v1/nurse/me/offers');
      if (gen != _sessionGen) return;
      ingestRawOffers(raw);
    } catch (_) {}
  }

  void _advanceQueue() {
    _expiryTimer?.cancel();
    while (_offerQueue.isNotEmpty) {
      final candidate = _offerQueue.first;
      if (_closedOfferIds.contains(candidate.offerId) ||
          candidate.remainingFrom(DateTime.now(), serverOffset) <= Duration.zero) {
        _offerQueue.removeAt(0);
        continue;
      }
      activeOffer = candidate;
      _scheduleExpiryCheck(candidate.remainingFrom(DateTime.now(), serverOffset));
      notifyListeners();
      return;
    }
    activeOffer = null;
    commitmentWarning = null;
    notifyListeners();
  }

  void ingestRawOffers(List<dynamic> rawOffers) {
    final now = DateTime.now();
    final validIncoming = <TypedNurseOffer>[];
    final validIds = <String>{};

    for (final entry in rawOffers) {
      if (entry is! Map) continue;
      final parsed = TypedNurseOffer.fromJson(Map<String, dynamic>.from(entry));
      if (parsed.offerId.isEmpty || _closedOfferIds.contains(parsed.offerId)) continue;
      final offset = parsed.serverNow.difference(now);
      final remaining = parsed.remainingFrom(now, offset);
      if (!kDemoMode && remaining <= Duration.zero) {
        _closedOfferIds.add(parsed.offerId);
        OfferAlarm.cancelOffer(parsed.offerId);
        continue;
      }
      serverOffset = offset;
      validIncoming.add(parsed);
      validIds.add(parsed.offerId);
    }

    // BUG-032: Remove all offers no longer open on server immediately (never leave stale offers open)
    if (activeOffer != null &&
        !validIds.contains(activeOffer!.offerId) &&
        _actingOfferId != activeOffer!.offerId) {
      OfferAlarm.cancelOffer(activeOffer!.offerId);
      activeOffer = null;
      commitmentWarning = null;
      _expiryTimer?.cancel();
    }

    _offerQueue
      ..clear()
      ..addAll(validIncoming);

    if (validIncoming.isEmpty) {
      if (_actingOfferId == null) {
        activeOffer = null;
        commitmentWarning = null;
        _expiryTimer?.cancel();
        notifyListeners();
      }
      return;
    }

    final next = validIncoming.first;
    if (activeOffer?.offerId == next.offerId) {
      notifyListeners();
      return;
    }

    if (_actingOfferId != null) {
      notifyListeners();
      return;
    }

    activeOffer = next;
    error = null;
    muted = false;
    commitmentWarning = null;
    final remaining = next.remainingFrom(now, serverOffset);
    _scheduleExpiryCheck(remaining);
    if (!kDemoMode) {
      api.getMap('/v1/nurse/offers/${next.offerId}/commitment').then((c) {
        if (activeOffer?.offerId == next.offerId) {
          commitmentWarning = c;
          notifyListeners();
        }
      }).catchError((_) {});
    }

    OfferAlarm.show(
      AlarmData(
        next.offerId,
        'طلب زيارة جديد في ${next.area}',
        '${next.serviceTitle} — حصتك ${next.formattedNurseShare}',
        remaining.inSeconds.clamp(2, 60),
        data: Map<String, dynamic>.from(rawOffers.first as Map),
      ),
    );
    notifyListeners();
  }

  void triggerDemoOffer() {
    final now = DateTime.now();
    activeOffer = TypedNurseOffer(
      offerId: 'demo-offer-1',
      requestId: 'demo-req-1',
      serviceTitle: 'حقنة عضلية وفحص ضغط',
      area: 'دمشق — المزة',
      distanceMeters: 1400,
      expectedMinutes: 30,
      priceAmount: 45000,
      nurseShare: 36000,
      waveNo: 1,
      serverNow: now,
      expiresAt: now.add(const Duration(seconds: 30)),
    );
    serverOffset = Duration.zero;
    error = null;
    _scheduleExpiryCheck(const Duration(seconds: 30));
    notifyListeners();
  }

  void _scheduleExpiryCheck(Duration remaining) {
    _expiryTimer?.cancel();
    _expiryTimer = Timer(remaining + const Duration(milliseconds: 200), () {
      if (activeOffer != null && !acting) {
        OfferAlarm.cancelOffer(activeOffer!.offerId);
        clearOffer();
      }
    });
  }

  void muteAlarm() {
    muted = true;
    OfferAlarm.cancelAll();
    notifyListeners();
  }

  Future<bool> accept() async {
    final offer = activeOffer;
    if (offer == null || acting) return false;
    OfferAlarm.cancelAll();
    acting = true;
    _actingOfferId = offer.offerId;
    error = null;
    notifyListeners();

    try {
      if (kDemoMode) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        _closedOfferIds.add(offer.offerId);
        _offerQueue.removeWhere((o) => o.offerId == offer.offerId);
        activeOffer = null;
        _expiryTimer?.cancel();
        onOfferAccepted(offer.requestId, 'demo-assign-1');
        return true;
      }

      final res = await api.post('/v1/nurse/offers/${offer.offerId}/accept', {});
      final assignmentId = res['assignmentId']?.toString() ?? '';
      final requestId = res['requestId']?.toString() ?? offer.requestId;
      if (assignmentId.isEmpty) {
        throw StateError('MISSING_ASSIGNMENT_ID');
      }
      _closedOfferIds.add(offer.offerId);
      _offerQueue.removeWhere((o) => o.offerId == offer.offerId);
      activeOffer = null;
      _expiryTimer?.cancel();
      onOfferAccepted(requestId, assignmentId);
      return true;
    } catch (e) {
      error = explainError(
        e,
        fallback: 'انتهت صلاحية العرض أو تم قبوله من ممرض آخر.',
      );
      _closedOfferIds.add(offer.offerId);
      _offerQueue.removeWhere((o) => o.offerId == offer.offerId);
      activeOffer = null;
      _expiryTimer?.cancel();
      await fetchOpenOffers();
      return false;
    } finally {
      _actingOfferId = null;
      acting = false;
      notifyListeners();
    }
  }

  Future<bool> decline() async {
    final offer = activeOffer;
    if (offer == null || acting) return false;
    OfferAlarm.cancelAll();
    acting = true;
    _actingOfferId = offer.offerId;
    error = null;
    notifyListeners();
    try {
      if (!kDemoMode && offer.offerId != 'demo-offer-1') {
        await api.post('/v1/nurse/offers/${offer.offerId}/decline', {});
      }
      _closedOfferIds.add(offer.offerId);
      _offerQueue.removeWhere((o) => o.offerId == offer.offerId);
      _actingOfferId = null;
      acting = false;
      _advanceQueue();
      return true;
    } catch (e) {
      error = explainError(e, fallback: 'تعذر رفض العرض؛ تحقق من الاتصال.');
      _actingOfferId = null;
      acting = false;
      notifyListeners();
      return false;
    }
  }

  void clearOffer() {
    _expiryTimer?.cancel();
    activeOffer = null;
    commitmentWarning = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    _sub.cancel();
    super.dispose();
  }
}
