import 'package:flutter_test/flutter_test.dart';
import 'package:tamreedy_core/tamreedy_core.dart';

void main() {
  test('decimal invoice uses exact wire amounts and real currency', () {
    final bill = BillInfo.fromJson({'requestId':'request','invoiceId':'invoice','invoiceVersion':4,
      'currencyCode':'USD','currencyDecimalPlaces':2,'paymentStatus':'PARTIAL',
      'moneyAmounts':{'gross':'100001.25','surcharge':'0.07','remaining':'0.31','collected':'100000.94'}});
    expect(bill.invoiceId,'invoice');
    expect(bill.invoiceVersion,4);
    expect(bill.money('remaining').amountMinor,BigInt.from(31));
    expect((bill.money('gross')-bill.money('surcharge')).formatted,'100,001.18 US\$');
    expect(bill.cashCollectionSupported,isFalse);
  });
  test('whole-unit operational currency and required invoice currency', () {
    expect(MoneyAmount.parse('2500.00','SYP_NEW',decimalPlaces:0).formatted,'2,500 ل.س جديدة');
    expect(formatMoney('1234.50',currency:'USD'),'1,234.50 US\$');
    expect(() => BillInfo.fromJson({'due':1}),throwsFormatException);
  });
}
