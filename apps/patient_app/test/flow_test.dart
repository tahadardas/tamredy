import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart' show LatLng, LoginScreen, TamreedyApi, mapsEnabled;
import 'package:flutter_test/flutter_test.dart';
import 'package:tamreedy_patient_app/controller.dart';
import 'package:tamreedy_patient_app/main.dart';

void main() {
  testWidgets('password visibility and manual recovery are accessible', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: LoginScreen(api: TamreedyApi(), expectedRole: 'PATIENT', onLoggedIn: () {}),
    ));
    final password = find.widgetWithText(TextField, 'كلمة المرور');
    expect(tester.widget<TextField>(password).obscureText, isTrue);
    await tester.tap(find.byTooltip('إظهار كلمة المرور'));
    await tester.pump();
    expect(tester.widget<TextField>(password).obscureText, isFalse);
    await tester.tap(find.text('نسيت كلمة المرور؟'));
    await tester.pumpAndSettle();
    expect(find.text('استعادة كلمة المرور'), findsOneWidget);
  });

  test('a moved pin never retains the old area or GPS accuracy', () {
    final c = PatientController();
    c.selectVisitLocation(
      const LatLng(33.5, 36.25),
      'المزة، دمشق',
      accuracyMeters: 50,
    );
    c.extraAddress = 'البناء 8';
    const moved = LatLng(33.5, 36.31);
    c.setPicked(moved, '');

    expect(c.position, moved);
    expect(c.accuracy, 0);
    expect(c.visitAddress, 'الموقع المحدد على الخريطة • البناء 8');

    c.setPicked(moved, 'القصاع - دمشق');
    expect(c.visitAddress, 'القصاع - دمشق • البناء 8');
    c.setPicked(moved, '');
    expect(c.visitAddress, 'القصاع - دمشق • البناء 8');
    c.dispose();
  });


  testWidgets('scrollable content stays above navigation and the keyboard', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = PatientController();
    await tester.pumpWidget(TamreedyPatientApp(controller: c));

    final nav = find.byType(NavigationBar);
    final emergencyNotice = find.text('تنبيه طبي للحالات الإسعافية');
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    scroll.position.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    expect(emergencyNotice.hitTestable(), findsOneWidget);
    expect(tester.getBottomLeft(emergencyNotice).dy, lessThan(tester.getTopLeft(nav).dy));

    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    await tester.pump();
    expect(nav, findsNothing);

    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

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
    expect(find.text('موقعي الحالي'), findsOneWidget);
    await tester.tap(find.text('هذا بيتي — أرسل الطلب'));
    await tester.pump();
    await tester.pump();
    expect(c.stage, VisitStage.searching);
    c.dispose();
  });
}
