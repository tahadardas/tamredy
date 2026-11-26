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
  Duration serverOffset = Duration.zero;
  Map<String, dynamic>? commitmentWarning;
  bool acting = false;
  bool muted = false;
  String? error;
  Timer? _expiryTimer;
  int _sessionGen = 0;

  void resetForSessionChange() {
    _sessionGen++;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    if (activeOffer != null) {
      OfferAlarm.cancelOffer(activeOffer!.offerId);
    }
    activeOffer = null;
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
      OfferAlarm.cancelOffer(offerId);
      if (activeOffer?.offerId == offerId && !acting) {
        clearOffer();
      }
    }
  }

  Future<void> fetchOpenOffers() async {
    if (kDemoMode || acting) return;
    try {
      final raw = await api.getList('/v1/nurse/me/offers');
      ingestRawOffers(raw);
    } catch (_) {}
  }

  void ingestRawOffers(List<dynamic> rawOffers) {
    if (acting) return;
    if (rawOffers.isEmpty) {
      if (activeOffer != null &&
          activeOffer!.remainingFrom(DateTime.now(), serverOffset) == Duration.zero) {
        clearOffer();
      }
      return;
    }
    final raw = Map<String, dynamic>.from(rawOffers.first as Map);
    final parsed = TypedNurseOffer.fromJson(raw);
    final now = DateTime.now();
    final offset = parsed.serverNow.difference(now);
    final remaining = parsed.remainingFrom(now, offset);
    if (!kDemoMode && remaining <= Duration.zero) {
      return;
    }

    if (activeOffer?.offerId == parsed.offerId) return;

    serverOffset = offset;
    activeOffer = parsed;
    error = null;
    muted = false;
    commitmentWarning = null;

    _scheduleExpiryCheck(remaining);
    if (!kDemoMode) {
      api.getMap('/v1/nurse/offers/${parsed.offerId}/commitment').then((c) {
        if (activeOffer?.offerId == parsed.offerId) {
          commitmentWarning = c;
          notifyListeners();
        }
      }).catchError((_) {});
    }

    OfferAlarm.show(
      AlarmData(
        parsed.offerId,
        'طلب زيارة جديد في ${parsed.area}',
        '${parsed.serviceTitle} — حصتك ${formatMoney(parsed.nurseShare)}',
        remaining.inSeconds.clamp(2, 60),
        data: raw,
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
    error = null;
    notifyListeners();

    try {
      if (kDemoMode) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
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
      activeOffer = null;
      _expiryTimer?.cancel();
      onOfferAccepted(requestId, assignmentId);
      return true;
    } catch (e) {
      error = explainError(
        e,
        fallback: 'انتهت صلاحية العرض أو تم قبوله من ممرض آخر.',
      );
      activeOffer = null;
      _expiryTimer?.cancel();
      await fetchOpenOffers();
      return false;
    } finally {
      acting = false;
      notifyListeners();
    }
  }

  Future<void> decline() async {
    final offer = activeOffer;
    if (offer == null || acting) return;
    OfferAlarm.cancelAll();
    acting = true;
    notifyListeners();
    try {
      if (!kDemoMode) {
        await api.post('/v1/nurse/offers/${offer.offerId}/decline', {});
      }
    } catch (_) {}
    activeOffer = null;
    _expiryTimer?.cancel();
    acting = false;
    notifyListeners();
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
