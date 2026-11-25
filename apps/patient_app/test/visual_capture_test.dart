import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import 'package:tamreedy_patient_app/controller.dart';
import 'package:tamreedy_patient_app/main.dart';
import 'package:tamreedy_patient_app/screens/history.dart';
import 'package:tamreedy_patient_app/screens/payment.dart';

void main() {
  final outDir = Platform.environment['TAM_SHOT_DIR'] ??
      r'C:\Users\BIG\.gemini\antigravity\brain\64bd58f2-5546-4de5-9bff-1a5a4cae339f\screenshots\before';

  Future<void> snap(WidgetTester tester, String name, Widget child, {bool dark = false}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: dark ? tamreedyDarkTheme() : tamreedyLightTheme(),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: child,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() async {
      final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$outDir\\$name.png');
      file.parent.createSync(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  testWidgets('capture patient screenshots', (tester) async {
    mapsEnabled = false;
    final c = PatientController();
    c.services = [
      const ServiceItem('s1', 'حقنة عضل أو وريد', 'تنفيذ الحقن الموصوفة طبياً', 'خدمة تمريضية', 25000, 0, expectedMinutes: 20),
      const ServiceItem('s2', 'تغيير ضماد جراحي', 'تعقيم وتضميد الجروح', 'خدمة تمريضية', 40000, 1, expectedMinutes: 35),
    ];
    c.serviceState = ServiceLoadState.loaded;

    await snap(tester, 'patient_home_light', PatientShell(c: c));
    await snap(tester, 'patient_home_dark', PatientShell(c: c), dark: true);
    await snap(tester, 'patient_history', HistoryScreen(c: c, nav: TamBottomNav(items: patientNav, index: 1, onTap: (_) {})));
    await snap(tester, 'patient_rating', RatingScreen(c: c));
    c.dispose();
  });
}
