import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import 'package:tamreedy_patient_app/controller.dart';
import 'package:tamreedy_patient_app/main.dart';
import 'package:tamreedy_patient_app/screens/service_catalog.dart';
import 'package:tamreedy_patient_app/screens/history.dart';
import 'package:tamreedy_patient_app/screens/payment.dart';

void main() {
  testWidgets('Patient screens render without overflow at 320px, 360px, 768px and 2.0x text scale', (tester) async {
    mapsEnabled = false;
    final c = PatientController();
    c.services = [
      const ServiceItem('s1', 'حقنة عضل أو وريد', 'تنفيذ الحقن الموصوفة طبياً', 'خدمة تمريضية', 25000, 0, expectedMinutes: 20),
      const ServiceItem('s2', 'تغيير ضماد جراحي', 'تعقيم وتضميد الجروح', 'خدمة تمريضية', 40000, 1, expectedMinutes: 35, requiresPrescription: true),
    ];
    c.serviceState = ServiceLoadState.loaded;

    for (final size in [const Size(320, 640), const Size(360, 740), const Size(768, 1024)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;

      for (final screen in [
        PatientShell(c: c),
        ServiceCatalogScreen(c: c),
        HistoryScreen(c: c, nav: TamBottomNav(items: patientNav, index: 1, onTap: (_) {})),
        RatingScreen(c: c),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: tamreedyLightTheme(),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: screen,
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull, reason: 'No overflow on $screen at $size');
      }
    }

    tester.view.reset();
    c.dispose();
  });
}
