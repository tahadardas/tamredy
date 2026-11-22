import 'package:flutter_test/flutter_test.dart';
import 'package:tamreedy_core/tamreedy_core.dart';

void main() {
  const rule = PricingRule(
    basePrice: 1200,
    includedMinutes: 30,
    blockMinutes: 15,
    blockPrice: 400,
    expectedMinutes: 40,
    roundingStep: 50,
  );
  test('matches the server algorithm', () {
    expect(rule.gross(30), 1200);
    expect(rule.gross(31), 1600);
    expect(rule.gross(46), 2000);
    final e = estimatePrice(rule);
    expect([e.min, e.expected], [1200, 1600]);
    final b = finalBill(
      rule,
      47 * 60,
      const Promo('W', percent: true, value: 20, maxDiscount: 500),
    );
    expect([b.minutes, b.gross, b.discount, b.due], [47, 2000, 400, 1600]);
  });
  test('short cash payment is flagged, then completed with change', () {
    final a = applyCollection(1600, 0, 1000);
    expect([a.paid, a.remaining], [false, 600]);
    expect(a.message, contains('ناقص'));
    final b = applyCollection(1600, a.collected, 1000);
    expect([b.paid, b.change], [true, 400]);
  });
}
