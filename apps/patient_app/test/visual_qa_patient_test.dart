import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import 'package:tamreedy_patient_app/app/patient_router.dart';
import 'package:tamreedy_patient_app/app/patient_shell.dart';
import 'package:tamreedy_patient_app/core/patient_session_coordinator.dart';
import 'package:tamreedy_patient_app/features/booking/booking_wizard_screen.dart';
import 'package:tamreedy_patient_app/features/catalog/catalog_store.dart';
import 'package:tamreedy_patient_app/features/finance/rating_screen.dart';
import 'package:tamreedy_patient_app/features/requests/requests_center_screen.dart';

void main() {
  final outDir = Platform.environment['TAM_SHOT_DIR'] ??
      r'C:\Users\BIG\.gemini\antigravity\brain\f17abd3e-0bfb-4950-8e89-ae9ce81b2271\screenshots';

  PatientSessionCoordinator makeSession() {
    final session = PatientSessionCoordinator();
    session.catalog.categories = const [
      TypedCategory(id: 'c1', code: 'INJ', titleAr: 'الحقن والأدوية'),
      TypedCategory(id: 'c2', code: 'WND', titleAr: 'الجروح والضمادات'),
      TypedCategory(id: 'c3', code: 'VIT', titleAr: 'المتابعة الحيوية'),
    ];
    session.catalog.services = const [
      PatientService(
        id: 's1',
        code: 'INJ_IM',
        categoryId: 'c1',
        categoryTitleAr: 'الحقن والأدوية',
        titleAr: 'حقنة عضلية أو وريدية',
        descriptionAr: 'تُنفذ مع مراعاة التعقيم الكامل والتثبت من الوصفة الطبية',
        priceAmount: 35000,
        expectedMinutes: 20,
        requiresPrescription: true,
      ),
      PatientService(
        id: 's2',
        code: 'WOUND',
        categoryId: 'c2',
        categoryTitleAr: 'الجروح والضمادات',
        titleAr: 'غيار جرح جراحي معقم',
        descriptionAr: 'تنظيف وتعقيم الجرح وتبديل الضماد بأدوات معقمة',
        priceAmount: 55000,
        expectedMinutes: 35,
      ),
    ];
    session.bookingDraft.beneficiaries = const [
      TypedBeneficiary(id: 'b1', displayName: 'أحمد محمد', relationship: 'SELF'),
    ];
    session.bookingDraft.selectedBeneficiaryId = 'b1';
    session.bookingDraft.setSingleService(session.catalog.services.first);
    session.bookingDraft.setMapPoint(kDamascus, 'المزة، دمشق');
    session.requests.registerCreatedRequest(
      const TypedCareRequest(
        id: 'req-1',
        status: 'EN_ROUTE',
        serviceTitle: 'حقنة عضلية أو وريدية',
        beneficiaryName: 'أحمد محمد',
        nurseName: 'سارة علي',
        priceAmount: 35000,
      ),
    );
    return session;
  }

  Future<void> verifyAndCapture(
    WidgetTester tester, {
    required String name,
    required Widget child,
    required Size size,
    bool dark = false,
    double textScale = 1.0,
    bool saveShot = false,
  }) async {
    final errors = <FlutterErrorDetails>[];
    final prevOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      errors.add(details);
    };

    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;

    final key = GlobalKey();
    try {
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('ar'),
            supportedLocales: const [Locale('ar'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: dark ? tamreedyDarkTheme() : tamreedyLightTheme(),
            builder: (ctx, c) => MediaQuery(
              data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(textScale)),
              child: Directionality(textDirection: TextDirection.rtl, child: c!),
            ),
            home: child,
          ),
        ),
      );
      await tester.pumpAndSettle();

      if (saveShot) {
        await tester.runAsync(() async {
          final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1.0);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('$outDir\\$name.png');
          file.parent.createSync(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
        });
      }
    } finally {
      FlutterError.onError = prevOnError;
      tester.view.reset();
    }

    expect(
      errors.where((e) => e.toString().contains('overflowed') || e.toString().contains('RenderFlex')),
      isEmpty,
      reason: 'Layout overflow on $name ($size, scale=$textScale, dark=$dark)',
    );
  }

  testWidgets('Patient Visual QA across 320, 360, 390, 430, 600, 768 widths + RTL + 2.0x scale + dark/light', (tester) async {
    mapsEnabled = false;
    final session = makeSession();
    addTearDown(session.dispose);

    const widths = [320.0, 360.0, 390.0, 430.0, 600.0, 768.0];
    for (final w in widths) {
      PatientRouter.currentTab.value = 0;
      await verifyAndCapture(
        tester,
        name: 'patient_home_w${w.toInt()}',
        child: PatientShell(session: session),
        size: Size(w, 844),
        textScale: w == 360.0 ? 2.0 : 1.0,
        saveShot: w == 390.0 || w == 320.0,
      );
    }

    await verifyAndCapture(
      tester,
      name: 'patient_home_dark_390',
      child: PatientShell(session: session),
      size: const Size(390, 844),
      dark: true,
      saveShot: true,
    );

    await verifyAndCapture(
      tester,
      name: 'patient_booking_wizard_390',
      child: BookingWizardScreen(session: session),
      size: const Size(390, 844),
      saveShot: true,
    );

    await verifyAndCapture(
      tester,
      name: 'patient_requests_center_390',
      child: RequestsCenterScreen(session: session),
      size: const Size(390, 844),
      saveShot: true,
    );

    await verifyAndCapture(
      tester,
      name: 'patient_rating_390',
      child: VisitRatingScreen(session: session, visitId: 'v-1'),
      size: const Size(390, 844),
      textScale: 1.5,
      saveShot: false,
    );
  });
}
