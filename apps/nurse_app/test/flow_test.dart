import 'package:tamreedy_core/tamreedy_core.dart' show mapsEnabled;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tamreedy_nurse_app/controller.dart';
import 'package:tamreedy_nurse_app/main.dart';

void main() {
  moneyTests();
  testWidgets('availability -> offer -> accept -> complete', (tester) async {
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    mapsEnabled = false; // no network tiles in tests
    final c = NurseController();
    await tester.pumpWidget(TamreedyNurseApp(controller: c));
    expect(find.text('لوحة الممرض'), findsOneWidget);
    await c.setAvailable(true);
    await tester.pump(const Duration(seconds: 6));
    expect(c.stage, NurseStage.offer);
    await tester.pump();
    expect(find.text('قبول الطلب'), findsOneWidget);
    await c.accept();
    await c.arrive();
    await c.start();
    await c.complete();
    await tester.pump();
    expect(c.stage, NurseStage.completed);
    expect(find.text('المبلغ المطلوب من المريض'), findsOneWidget);
    c.backToAvailable();
    await tester.pump();
    expect(find.text('لوحة الممرض'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}

void moneyTests() {
  testWidgets(
    'short cash is flagged and blocks closing; the rest completes it',
    (tester) async {
      mapsEnabled = false;
      final c = NurseController();
      await c.setAvailable(true);
      await tester.pump(const Duration(seconds: 6));
      await c.accept();
      await c.arrive();
      await c.start();
      await c.complete();
      expect(c.bill, isNotNull);
      final due = c.bill!.due;
      await c.collect(due - 500);
      expect(c.collectShort, isTrue);
      expect(c.collectMsg, contains('ناقص'));
      expect(c.bill!.status, 'PARTIAL');
      expect(c.bill!.remaining, 500);
      await c.collect(500);
      expect(c.bill!.status, 'PAID');
      expect(c.collectShort, isFalse);
      c.dispose();
    },
  );
}
