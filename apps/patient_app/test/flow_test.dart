import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart' show mapsEnabled;
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
    c.services = kSampleServices;
    c.serviceState = ServiceLoadState.loaded;
    await tester.pumpWidget(TamreedyPatientApp(controller: c));
    expect(find.text('طلب تمريض منزلي'), findsOneWidget);
    await tester.tap(find.text('تغيير ضماد'));
    await tester.pumpAndSettle();
    expect(find.text('تفاصيل الخدمة'), findsOneWidget);
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('متابعة إلى تحديد الموقع'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('أين تريد الزيارة؟'), findsOneWidget);
    await tester.tap(find.text('استخدم موقعي الحالي'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('ثبّت مكان بيتك'), findsOneWidget);
    await tester.tap(find.text('هذا بيتي — أرسل الطلب'));
    await tester.pump();
    await tester.pump();
    expect(c.stage, VisitStage.searching);
    c.dispose();
  });
}
