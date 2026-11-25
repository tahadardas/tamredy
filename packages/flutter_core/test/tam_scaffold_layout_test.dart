import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tamreedy_core/tamreedy_core.dart';

void main() {
  testWidgets('scrollable body ends above the bottom navigation dock', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: tamreedyTheme(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 740),
            padding: EdgeInsets.only(bottom: 24),
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: TamScaffold(
              title: 'اختبار',
              subtitle: 'تخطيط آمن',
              nav: TamBottomNav(
                items: const [
                  NavItem(Icons.home_outlined, 'الرئيسية'),
                  NavItem(Icons.person_outline, 'حسابي'),
                ],
                index: 0,
                onTap: (_) {},
              ),
              children: const [SizedBox(height: 900)],
            ),
          ),
        ),
      ),
    );

    final bodyBottom = tester.getBottomLeft(find.byType(ListView)).dy;
    final navigationTop = tester.getTopLeft(find.byType(NavigationBar)).dy;

    expect(bodyBottom, lessThanOrEqualTo(navigationTop));
  });
}
