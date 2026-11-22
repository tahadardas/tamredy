import 'package:tamreedy_core/tamreedy_core.dart' show mapsEnabled;
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:tamreedy_patient_app/controller.dart';
import 'package:tamreedy_patient_app/main.dart';

void main() {
  testWidgets('home shows services and opens service details', (tester) async {
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    mapsEnabled = false; // no network tiles in tests
    final c = PatientController();
    await tester.pumpWidget(TamreedyPatientApp(controller: c));
    expect(find.text('طلب تمريض منزلي'), findsOneWidget);
    await tester.tap(find.text('تغيير ضماد'));
    await tester.pumpAndSettle();
    expect(find.text('تفاصيل الخدمة'), findsOneWidget);
    await tester.tap(find.text('متابعة'));
    await tester.pumpAndSettle();
    expect(find.text('تأكيد موقع الزيارة'), findsOneWidget);
    await tester.tap(find.text('تأكيد الموقع ومتابعة الطلب'));
    await tester.pump();
    await tester.pump();
    expect(c.stage, VisitStage.searching);
    c.dispose();
  });
}
