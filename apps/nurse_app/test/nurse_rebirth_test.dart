import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import 'package:tamreedy_nurse_app/app/nurse_router.dart';
import 'package:tamreedy_nurse_app/app/nurse_shell.dart';
import 'package:tamreedy_nurse_app/core/nurse_session_coordinator.dart';
import 'package:tamreedy_nurse_app/features/offers/incoming_offer_overlay.dart';
import 'package:tamreedy_nurse_app/features/visit/service_outcomes_screen.dart';
import 'package:tamreedy_nurse_app/features/visit/visit_store.dart';

NurseSessionCoordinator _buildMockNurseSession() {
  final session = NurseSessionCoordinator();
  session.nurseFullName = 'سارة الخطيب';
  session.nurseNumber = 'RN-204';
  session.ratingAvg = 4.9;
  session.profileVerified = true;
  session.finance.todayEarnings = 36000;
  session.finance.netDue = 180000;
  session.finance.monthVisits = 7;
  session.finance.commission = 36000;
  session.finance.balance = 12000;
  return session;
}

Widget _wrapRtl(Widget child) => MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: tamreedyLightTheme(),
      home: Directionality(textDirection: TextDirection.rtl, child: child),
    );

void main() {
  setUp(() {
    mapsEnabled = false;
    NurseRouter.currentTab.value = 0;
  });

  testWidgets('Global IncomingOfferOverlay displays above ALL tabs including Finance & Marketplace', (tester) async {
    final session = _buildMockNurseSession();
    addTearDown(session.dispose);

    // Nurse navigates away from Home to Financial Center (tab 3)
    NurseRouter.currentTab.value = 3;

    await tester.pumpWidget(
      _wrapRtl(
        Stack(
          children: [
            NurseShell(session: session),
            ListenableBuilder(
              listenable: session.offers,
              builder: (_, _) {
                final offer = session.offers.activeOffer;
                if (offer == null) return const SizedBox.shrink();
                return Positioned.fill(
                  child: IncomingOfferOverlay(session: session, offer: offer),
                );
              },
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(find.text('المركز المالي والمستحقات'), findsOneWidget);
    expect(find.text('قبول الطلب والبدء'), findsNothing);

    // Incoming offer arrives while nurse is on Finance tab!
    session.offers.triggerDemoOffer();
    await tester.pump();

    expect(find.text('قبول الطلب والبدء'), findsOneWidget);
    expect(find.text('تجاهل العرض'), findsOneWidget);
    expect(find.text('حقنة عضلية وفحص ضغط'), findsOneWidget);

    // Declining closes the overlay immediately
    await tester.tap(find.text('تجاهل العرض'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('قبول الطلب والبدء'), findsNothing);
    session.offers.clearOffer();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  test('NurseFinanceStore never fabricates hardcoded balances before server load', () {
    final session = _buildMockNurseSession();
    addTearDown(session.dispose);

    final fresh = NurseSessionCoordinator();
    addTearDown(fresh.dispose);
    expect(fresh.finance.todayEarnings, isNull);
    expect(fresh.finance.netDue, isNull);
    expect(fresh.finance.monthVisits, isNull);
  });

  testWidgets('ServiceOutcomesScreen starts with NO default COMPLETED status and enforces explicit documentation', (tester) async {
    final session = _buildMockNurseSession();
    addTearDown(session.dispose);

    session.visit.assignmentId = 'a-1';
    session.visit.requestId = 'r-1';
    session.visit.phase = NurseVisitPhase.inService;
    session.visit.items = [
      {
        'id': 'item-1',
        'title_ar': 'حقنة عضلية',
        'quantity': 1,
        'expected_minutes': 20,
        'item_status': 'PENDING',
      },
    ];

    await tester.pumpWidget(_wrapRtl(ServiceOutcomesScreen(session: session)));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    // Tapping submit immediately fails validation because status was NOT defaulted to COMPLETED
    final submitFinder = find.text('حفظ النتائج وإنهاء الزيارة');
    await tester.dragUntilVisible(
      submitFinder,
      find.byType(CustomScrollView).first,
      const Offset(0, -200),
    );
    await tester.pump();
    await tester.tap(submitFinder);
    await tester.pump();
    expect(find.text('يرجى تحديد نتيجة التنفيذ لهذه الخدمة'), findsOneWidget);
  });
}
