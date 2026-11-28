import 'format.dart';
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
  final String? visitId, promoCode, requestId, invoiceId;
  final int? invoiceVersion;
  final String currencyCode;
  final int currencyDecimalPlaces;
  final bool cashCollectionSupported;
  final Map<String, MoneyAmount> exactAmounts;

  MoneyAmount money(String field) => exactAmounts[field] ?? MoneyAmount.parse(
    switch (field) {
      'due' => due,'gross' => gross,'discount' => discount,'collected' => collected,
      'remaining' => remaining,'surcharge' => surcharge,'distanceFee' => distanceFee,
      'tax' => tax,'tip' => tip,'payable' => payable,'nurseEarning' => nurseEarning,
      _ => throw ArgumentError.value(field),
    }, currencyCode, decimalPlaces: currencyDecimalPlaces);
  const BillInfo({
    required this.due,
    required this.minutes,
    required this.gross,
    required this.discount,
    required this.collected,
    required this.remaining,
    required this.status,
    this.visitId,
    this.requestId,
    this.invoiceId,
    this.invoiceVersion,
    this.currencyCode = 'SYP_NEW',
    this.currencyDecimalPlaces = 0,
    this.cashCollectionSupported = false,
    this.exactAmounts = const {},
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

  factory BillInfo.fromJson(Map<String, dynamic> j) {
    final currency = (j['currencyCode'] ?? j['currency'])?.toString();
    if (currency == null || currency.isEmpty) throw const FormatException('عملة الفاتورة غير متوفرة');
    final scale = j['currencyDecimalPlaces'] as int? ?? (currency == 'SYP_NEW' ? 0 : 2);
    final raw = j['moneyAmounts'] as Map? ?? j;
    final exact = {
      for (final field in ['due','gross','discount','collected','remaining','surcharge','distanceFee','tax','tip','payable','nurseEarning'])
        if (raw[field] != null) field: MoneyAmount.parse(raw[field] as Object,currency,decimalPlaces:scale),
    };
    int major(String field) {
      final amount = exact[field];
      return amount == null ? 0 : (amount.amountMinor ~/ BigInt.from(10).pow(amount.decimalPlaces)).toInt();
    }
    return BillInfo(
    requestId: j['requestId']?.toString(), invoiceId: j['invoiceId']?.toString(),
    invoiceVersion: int.tryParse('${j['invoiceVersion']}'), currencyCode: currency,
    currencyDecimalPlaces: scale, cashCollectionSupported: j['cashCollectionSupported'] == true,
    exactAmounts: Map.unmodifiable(exact),
    due: major('due'),
    minutes: _i(j['minutes']),
    gross: major('gross'),
    discount: major('discount'),
    collected: major('collected'),
    remaining: major('remaining'),
    status: '${j['paymentStatus']}',
    visitId: j['visitId']?.toString(),
    promoCode: j['promoCode']?.toString(),
    surcharge: major('surcharge'),
    distanceFee: major('distanceFee'),
    tax: major('tax'),
    tip: major('tip'),
    payable: !exact.containsKey('payable') ? null : major('payable'),
    nurseEarning: major('nurseEarning'),
    taxLabel: '${j['taxLabel'] ?? 'ضريبة'}',
  );
  }
}
