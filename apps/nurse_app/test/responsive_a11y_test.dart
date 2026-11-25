import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import 'package:tamreedy_nurse_app/controller.dart';
import 'package:tamreedy_nurse_app/main.dart';
import 'package:tamreedy_nurse_app/screens/home.dart';
import 'package:tamreedy_nurse_app/screens/earnings.dart';
import 'package:tamreedy_nurse_app/screens/service_outcomes.dart';

void main() {
  testWidgets('Nurse screens render without overflow at 320px, 360px, 768px and 2.0x text scale', (tester) async {
    mapsEnabled = false;
    final c = NurseController();
    final nav = TamBottomNav(items: nurseNav, index: 0, onTap: (_) {});

    for (final size in [const Size(320, 640), const Size(360, 740), const Size(768, 1024)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;

      for (final screen in [
        NurseHomeScreen(c: c, nav: nav),
        EarningsScreen(c: c, nav: TamBottomNav(items: nurseNav, index: 2, onTap: (_) {})),
        ServiceOutcomesScreen(c: c),
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
