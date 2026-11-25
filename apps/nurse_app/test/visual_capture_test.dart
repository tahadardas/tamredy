import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import 'package:tamreedy_nurse_app/controller.dart';
import 'package:tamreedy_nurse_app/main.dart';
import 'package:tamreedy_nurse_app/screens/home.dart';
import 'package:tamreedy_nurse_app/screens/earnings.dart';

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

  testWidgets('capture nurse screenshots', (tester) async {
    mapsEnabled = false;
    final c = NurseController();
    final nav = TamBottomNav(items: nurseNav, index: 0, onTap: (_) {});
    await snap(tester, 'nurse_home_light', NurseHomeScreen(c: c, nav: nav));
    await snap(tester, 'nurse_home_dark', NurseHomeScreen(c: c, nav: nav), dark: true);
    await snap(tester, 'nurse_earnings', EarningsScreen(c: c, nav: TamBottomNav(items: nurseNav, index: 2, onTap: (_) {})));
    c.dispose();
  });
}
