import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import 'package:tamreedy_patient_app/controller.dart';
import 'package:tamreedy_patient_app/screens/payment.dart';

void main() {
  testWidgets('payment can refresh without a bill and reports the result', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = _PaymentController();
    await tester.pumpWidget(MaterialApp(home: PaymentScreen(c: controller)));

    final refresh = find.text('تحديث حالة الدفع');
    await tester.tap(refresh);
    await tester.pump();
    expect(find.text('جارٍ تحديث حالة الدفع…'), findsOneWidget);

    controller.response.complete(null);
    await tester.pumpAndSettle();
    expect(find.text('تعذر تحديث الفاتورة. حاول مجددًا.'), findsOneWidget);

    controller.response = Completer<BillInfo?>();
    await tester.tap(refresh);
    controller.response.complete(
      const BillInfo(
        due: 5000,
        minutes: 1,
        gross: 5000,
        discount: 0,
        collected: 5000,
        remaining: 0,
        status: 'PAID',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('تم تأكيد الدفع بالكامل.'), findsOneWidget);
    expect(find.text('متابعة إلى التقييم'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}

class _PaymentController extends PatientController {
  Completer<BillInfo?> response = Completer<BillInfo?>();

  @override
  Future<bool> loadBill() async {
    final updated = await response.future;
    if (updated == null) return false;
    bill = updated;
    notifyListeners();
    return true;
  }
}
