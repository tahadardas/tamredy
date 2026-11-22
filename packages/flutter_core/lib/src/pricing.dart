/// Dart mirror of apps/api/src/pricing/pricing.ts (the server is the source of truth).
/// Used for the demo mode and for instant on-screen previews.
class PricingRule {
  final int basePrice,
      includedMinutes,
      blockMinutes,
      blockPrice,
      expectedMinutes,
      roundingStep;
  const PricingRule({
    required this.basePrice,
    this.includedMinutes = 30,
    this.blockMinutes = 15,
    this.blockPrice = 0,
    this.expectedMinutes = 30,
    this.roundingStep = 1,
  });

  factory PricingRule.fromService(Map<String, dynamic> j) => PricingRule(
    basePrice: _i(j['price_amount']),
    includedMinutes: _i(j['included_minutes'], 30),
    blockMinutes: _i(j['block_minutes'], 15),
    blockPrice: _i(j['block_price']),
    expectedMinutes: _i(j['expected_minutes'], 30),
  );
  static int _i(Object? v, [int d = 0]) =>
      (num.tryParse('${v ?? ''}') ?? d).round();

  int gross(int minutes) {
    final extra = (minutes - includedMinutes).clamp(0, 1 << 30);
    return basePrice + (extra / blockMinutes).ceil() * blockPrice;
  }
}

class Promo {
  final String code;
  final bool percent;
  final num value;
  final int? maxDiscount;
  const Promo(
    this.code, {
    required this.percent,
    required this.value,
    this.maxDiscount,
  });

  int discount(int gross) {
    var d = percent ? (gross * value / 100).round() : value.round();
    if (maxDiscount != null && d > maxDiscount!) d = maxDiscount!;
    return d.clamp(0, gross);
  }
}

class PriceEstimate {
  final int min, expected;
  const PriceEstimate(this.min, this.expected);
}

int _roundUp(int n, int step) => step <= 1 ? n : (n / step).ceil() * step;

PriceEstimate estimatePrice(PricingRule r, [Promo? p]) {
  int net(int g) => _roundUp(g - (p?.discount(g) ?? 0), r.roundingStep);
  return PriceEstimate(net(r.gross(0)), net(r.gross(r.expectedMinutes)));
}

class Bill {
  final int minutes, gross, discount, due;
  const Bill(this.minutes, this.gross, this.discount, this.due);
}

Bill finalBill(PricingRule r, int secondsAtPatient, [Promo? p]) {
  final minutes = (secondsAtPatient / 60).ceil().clamp(1, 1 << 30);
  final g = r.gross(minutes);
  final d = p?.discount(g) ?? 0;
  return Bill(minutes, g, d, _roundUp(g - d, r.roundingStep));
}

class CollectionResult {
  final int applied, collected, remaining, change;
  final bool paid;
  const CollectionResult(
    this.applied,
    this.collected,
    this.remaining,
    this.change,
    this.paid,
  );
  String get message => paid
      ? (change > 0
            ? 'تم الدفع. أعد للمريض $change فكة.'
            : 'تم استلام المبلغ كاملًا.')
      : 'المبلغ ناقص: المتبقي $remaining. أكمل التحصيل.';
}

CollectionResult applyCollection(int due, int already, int received) {
  if (received <= 0) throw ArgumentError('INVALID_AMOUNT');
  final before = (due - already).clamp(0, 1 << 30);
  final applied = received < before ? received : before;
  final collected = already + applied;
  final remaining = due - collected;
  return CollectionResult(
    applied,
    collected,
    remaining,
    received - applied,
    remaining == 0,
  );
}

/// Bill as returned by `/v1/requests/:id/bill` (patient) and `/v1/nurse/requests/:id/bill` (nurse).
class BillInfo {
  final int due, minutes, gross, discount, collected, remaining;
  final int surcharge, distanceFee, tax, tip, payable, nurseEarning;
  final String status; // DUE | PARTIAL | PAID
  final String taxLabel;
  final String? visitId, promoCode;
  const BillInfo({
    required this.due,
    required this.minutes,
    required this.gross,
    required this.discount,
    required this.collected,
    required this.remaining,
    required this.status,
    this.visitId,
    this.promoCode,
    this.surcharge = 0,
    this.distanceFee = 0,
    this.tax = 0,
    this.tip = 0,
    int? payable,
    this.nurseEarning = 0,
    this.taxLabel = 'ضريبة',
  }) : payable = payable ?? due + tip;

  static int _i(Object? v) => (num.tryParse('$v') ?? 0).round();

  factory BillInfo.fromJson(Map<String, dynamic> j) => BillInfo(
    due: _i(j['due']),
    minutes: _i(j['minutes']),
    gross: _i(j['gross']),
    discount: _i(j['discount']),
    collected: _i(j['collected']),
    remaining: _i(j['remaining']),
    status: '${j['paymentStatus']}',
    visitId: j['visitId']?.toString(),
    promoCode: j['promoCode']?.toString(),
    surcharge: _i(j['surcharge']),
    distanceFee: _i(j['distanceFee']),
    tax: _i(j['tax']),
    tip: _i(j['tip']),
    payable: j['payable'] == null ? null : _i(j['payable']),
    nurseEarning: _i(j['nurseEarning']),
    taxLabel: '${j['taxLabel'] ?? 'ضريبة'}',
  );
}
