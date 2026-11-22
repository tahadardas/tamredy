import 'package:flutter_test/flutter_test.dart';
import 'package:tamreedy_patient_app/controller.dart';

void main() {
  test(
    'estimate appears instantly, promo lowers it, bad code is rejected',
    () async {
      final c = PatientController();
      final dress = c.services.firstWhere((s) => s.id == 'dress');
      c.pick(dress);
      expect([c.est!.min, c.est!.expected], [1200, 1600]);
      await c.applyPromo('welcome20');
      expect(c.promoCode, 'WELCOME20');
      expect(c.est!.expected, lessThan(1600));
      await c.applyPromo('NOPE');
      expect(c.promoMsg, 'الكود غير صحيح');
      expect(c.promoCode, '');
      c.dispose();
    },
  );

  test(
    'bill is produced from the visit and matches the estimate rules',
    () async {
      final c = PatientController();
      c.pick(c.services.firstWhere((s) => s.id == 'dress'));
      c.requestId = 'x';
      await c.loadBill();
      expect(c.bill!.minutes, 47);
      expect(c.bill!.due, 2000); // 47 min: base 1200 + 2 blocks x 400
      c.dispose();
    },
  );
}
