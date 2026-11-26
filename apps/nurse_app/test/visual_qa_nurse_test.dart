import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import 'package:tamreedy_nurse_app/app/nurse_router.dart';
import 'package:tamreedy_nurse_app/app/nurse_shell.dart';
import 'package:tamreedy_nurse_app/core/nurse_session_coordinator.dart';
import 'package:tamreedy_nurse_app/features/finance/financial_center_screen.dart';
import 'package:tamreedy_nurse_app/features/visit/visit_store.dart';
import 'package:tamreedy_nurse_app/features/visit/visit_workspace_screen.dart';

void main() {
  final outDir = Platform.environment['TAM_SHOT_DIR'] ??
      r'C:\Users\BIG\.gemini\antigravity\brain\f17abd3e-0bfb-4950-8e89-ae9ce81b2271\screenshots';

  NurseSessionCoordinator makeSession() {
    final session = NurseSessionCoordinator();
    session.nurseFullName = 'سارة الخطيب';
    session.nurseNumber = 'RN-2041';
    session.ratingAvg = 4.9;
    session.profileVerified = true;
    session.approvedSkills = const ['الحقن والأدوية', 'غيار الجروح', 'العلامات الحيوية'];
    session.finance.todayEarnings = 45000;
    session.finance.netDue = 210000;
    session.finance.monthVisits = 9;
    session.finance.commission = 42000;
    session.finance.nurseOwedAmount = 210000;
    session.finance.companyOwedAmount = 0;
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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

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

  testWidgets('Nurse Visual QA across 320, 360, 390, 430, 600, 768 widths + RTL + 2.0x + dark/light + offer overlay', (tester) async {
    mapsEnabled = false;
    final session = makeSession();
    addTearDown(session.dispose);

    const widths = [320.0, 360.0, 390.0, 430.0, 600.0, 768.0];
    for (final w in widths) {
      NurseRouter.currentTab.value = 0;
      await verifyAndCapture(
        tester,
        name: 'nurse_home_w${w.toInt()}',
        child: NurseShell(session: session),
        size: Size(w, 844),
        textScale: w == 360.0 ? 2.0 : 1.0,
        saveShot: w == 390.0 || w == 320.0,
      );
    }

    await verifyAndCapture(
      tester,
      name: 'nurse_home_dark_390',
      child: NurseShell(session: session),
      size: const Size(390, 844),
      dark: true,
      saveShot: true,
    );

    await verifyAndCapture(
      tester,
      name: 'nurse_financial_390',
      child: FinancialCenterScreen(session: session),
      size: const Size(390, 844),
      saveShot: true,
    );

    session.visit.assignmentId = 'a-1';
    session.visit.requestId = 'r-1';
    session.visit.phase = NurseVisitPhase.enRoute;
    session.visit.serviceTitle = 'غيار جرح جراحي معقم';
    session.visit.addressText = 'دمشق — المالكي';
    session.visit.destination = kDamascus;
    await verifyAndCapture(
      tester,
      name: 'nurse_visit_en_route_390',
      child: VisitWorkspaceScreen(session: session),
      size: const Size(390, 844),
      saveShot: true,
    );

    session.offers.triggerDemoOffer();
    await verifyAndCapture(
      tester,
      name: 'nurse_offer_overlay_390',
      child: NurseShell(session: session),
      size: const Size(390, 844),
      saveShot: true,
    );
    session.offers.clearOffer();
  });
}
