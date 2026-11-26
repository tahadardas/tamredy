import 'package:flutter/foundation.dart';
import 'package:tamreedy_core/tamreedy_core.dart';

class FinanceStore extends ChangeNotifier {
  final TamreedyApi api;

  FinanceStore({required this.api});

  bool loadingWallet = false;
  String? walletError;
  Map<String, dynamic>? walletStatus;
  Map<String, dynamic>? walletSummary;

  Map<String, dynamic>? referralInfo;
  bool loadingReferral = false;

  void resetForSessionChange() {
    walletStatus = null;
    walletSummary = null;
    walletError = null;
    referralInfo = null;
    loadingWallet = false;
    loadingReferral = false;
    notifyListeners();
  }

  Future<BillInfo> loadBill(String requestId) async {
    if (kDemoMode) {
      return const BillInfo(
        due: 45000,
        minutes: 35,
        gross: 45000,
        discount: 0,
        collected: 45000,
        remaining: 0,
        status: 'PAID',
        visitId: 'demo-visit-1',
      );
    }
    final res = await api.getMap('/v1/requests/$requestId/bill');
    return BillInfo.fromJson(res);
  }

  Future<BillInfo> applyTip(String requestId, int amount) async {
    if (kDemoMode) {
      return BillInfo(
        due: 45000,
        minutes: 35,
        gross: 45000,
        discount: 0,
        collected: 0,
        remaining: 45000 + amount,
        status: 'DUE',
        tip: amount,
      );
    }
    await api.post(
      '/v1/requests/$requestId/tip',
      {'amount': amount},
      {'Idempotency-Key': 'tip:$requestId:$amount'},
    );
    return loadBill(requestId);
  }

  Future<void> submitReview({
    required String visitId,
    required int overallStars,
    int punctualityStars = 0,
    int clinicalStars = 0,
    int conductStars = 0,
    String comment = '',
  }) async {
    if (kDemoMode) return;
    await api.post('/v1/visits/$visitId/patient-review', {
      'stars': overallStars,
      'overallStars': overallStars,
      if (punctualityStars > 0) 'punctualityStars': punctualityStars,
      if (clinicalStars > 0) 'clinicalStars': clinicalStars,
      if (conductStars > 0) 'conductStars': conductStars,
      if (comment.trim().isNotEmpty) 'comment': comment.trim(),
    });
  }

  Future<void> loadWallet() async {
    if (kDemoMode) {
      walletStatus = {'mode': 'DISABLED', 'reason': 'LICENSED_PAYMENT_PROVIDER_REQUIRED'};
      walletSummary = {'activePaymentMethod': 'CASH_ON_DELIVERY'};
      notifyListeners();
      return;
    }
    loadingWallet = true;
    walletError = null;
    notifyListeners();
    try {
      final res = await Future.wait([
        api.getMap('/v1/wallet/status'),
        api.getMap('/v1/wallet/patient-summary').catchError((_) => <String, dynamic>{}),
      ]);
      walletStatus = res[0];
      walletSummary = res[1];
    } catch (e) {
      walletError = explainError(e, fallback: 'تعذر التحقق من حالة المحفظة من الخادم');
    } finally {
      loadingWallet = false;
      notifyListeners();
    }
  }

  Future<void> loadReferral() async {
    if (kDemoMode) {
      referralInfo = {
        'enabled': true,
        'code': 'TMDEMO12',
        'invited': 2,
        'rewarded': 1,
        'friendGets': 15,
        'youGet': 15,
        'alreadyReferred': false,
      };
      notifyListeners();
      return;
    }
    loadingReferral = true;
    notifyListeners();
    try {
      referralInfo = await api.getMap('/v1/referral/mine');
    } catch (_) {}
    loadingReferral = false;
    notifyListeners();
  }

  Future<String> claimPromoCode(String code) async {
    final cleaned = code.trim().toUpperCase();
    if (cleaned.isEmpty) return 'أدخل رمز الخصم أولاً';
    if (kDemoMode) return 'تم حفظ الكود — سيُطبَّق على طلبك القادم';
    await api.post('/v1/promos/claim', {'code': cleaned});
    return 'تم حفظ الكود — سيُطبَّق على طلبك القادم';
  }

  Future<String> claimReferralCode(String code) async {
    final cleaned = code.trim().toUpperCase();
    if (cleaned.isEmpty) return 'أدخل رمز الدعوة أولاً';
    if (kDemoMode) return 'تم تطبيق خصم 15% على طلبك الأول';
    final r = await api.post('/v1/referral/claim', {'code': cleaned});
    await loadReferral();
    return 'تم تطبيق خصم ${r['discountPercent'] ?? 15}% على طلبك الأول';
  }
}
