import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import 'package:tamreedy_patient_app/app/patient_router.dart';
import 'package:tamreedy_patient_app/app/patient_shell.dart';
import 'package:tamreedy_patient_app/core/patient_session_coordinator.dart';
import 'package:tamreedy_patient_app/features/booking/booking_wizard_screen.dart';
import 'package:tamreedy_patient_app/features/catalog/catalog_store.dart';
import 'package:tamreedy_patient_app/features/catalog/service_catalog_screen.dart';

PatientSessionCoordinator _buildMockSession() {
  final session = PatientSessionCoordinator();
  session.catalog.categories = const [
    TypedCategory(id: 'cat-1', code: 'INJ', titleAr: 'الحقن والأدوية', sortOrder: 1),
    TypedCategory(id: 'cat-2', code: 'WND', titleAr: 'العناية بالجروح', sortOrder: 2),
  ];
  session.catalog.services = const [
    PatientService(
      id: 'svc-1',
      code: 'INJ_IM',
      categoryId: 'cat-1',
      categoryCode: 'INJ',
      categoryTitleAr: 'الحقن والأدوية',
      titleAr: 'إبرة عضلية أو وريدية',
      descriptionAr: 'تنفيذ الحقنة وفق وصفة طبية سارية',
      priceAmount: 35000,
      expectedMinutes: 20,
      requiresPrescription: true,
    ),
    PatientService(
      id: 'svc-2',
      code: 'WOUND_DRESS',
      categoryId: 'cat-2',
      categoryCode: 'WND',
      categoryTitleAr: 'العناية بالجروح',
      titleAr: 'غيار جرح جراحي',
      descriptionAr: 'تنظيف وتعقيم الجروح بأدوات معقمة',
      priceAmount: 55000,
      expectedMinutes: 35,
    ),
  ];
  session.bookingDraft.beneficiaries = const [
    TypedBeneficiary(id: 'ben-1', displayName: 'خالد أحمد', relationship: 'SELF'),
  ];
  session.bookingDraft.selectedBeneficiaryId = 'ben-1';
  session.bookingDraft.setMapPoint(kDamascus, 'المزة، دمشق');
  return session;
}

Widget _wrapRtl(Widget child, {ThemeMode mode = ThemeMode.light}) => MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: tamreedyLightTheme(),
      darkTheme: tamreedyDarkTheme(),
      themeMode: mode,
      home: Directionality(textDirection: TextDirection.rtl, child: child),
    );

void main() {
  setUp(() {
    mapsEnabled = false;
    PatientRouter.currentTab.value = 0;
  });

  test('CatalogStore filters accurately with Arabic Alef/Teh-Marbuta normalization', () {
    final session = _buildMockSession();
    addTearDown(session.dispose);

    session.catalog.setSearchQuery('ابره'); // without hamza or taa marbuta
    expect(session.catalog.filteredServices.length, 1);
    expect(session.catalog.filteredServices.first.id, 'svc-1');

    session.catalog.setSearchQuery('');
    session.catalog.setCategory('cat-2');
    expect(session.catalog.filteredServices.length, 1);
    expect(session.catalog.filteredServices.first.id, 'svc-2');
  });

  test('RequestsStore partitions active, upcoming, unpaidBills, and past cleanly', () {
    final session = _buildMockSession();
    addTearDown(session.dispose);

    session.requests.registerCreatedRequest(
      const TypedCareRequest(id: 'r-act', status: 'EN_ROUTE', serviceTitle: 'خدمة نشطة'),
    );
    session.requests.registerCreatedRequest(
      const TypedCareRequest(id: 'r-sch', status: 'SCHEDULED', serviceTitle: 'زيارة مجدولة'),
    );
    session.requests.registerCreatedRequest(
      const TypedCareRequest(
        id: 'r-due',
        status: 'COMPLETED',
        paymentStatus: 'DUE',
        amountDue: 40000,
        serviceTitle: 'فاتورة مستحقة',
      ),
    );
    session.requests.registerCreatedRequest(
      const TypedCareRequest(
        id: 'r-past',
        status: 'COMPLETED',
        paymentStatus: 'PAID',
        serviceTitle: 'زيارة منتهية',
      ),
    );

    expect(session.requests.activeRequests.map((r) => r.id), ['r-act']);
    expect(session.requests.upcomingRequests.map((r) => r.id), ['r-sch']);
    expect(session.requests.unpaidBills.map((r) => r.id), ['r-due']);
    expect(session.requests.pastRequests.map((r) => r.id), ['r-past']);
  });

  testWidgets('PatientShell switches 4 tabs smoothly and ServiceCatalog cart works', (tester) async {
    final session = _buildMockSession();
    addTearDown(session.dispose);

    await tester.pumpWidget(_wrapRtl(PatientShell(session: session)));
    await tester.pumpAndSettle();

    expect(find.text('طلب ممرض الآن'), findsOneWidget);
    expect(find.text('الحقن والأدوية'), findsOneWidget);

    await tester.tap(find.text('طلباتي'));
    await tester.pumpAndSettle();
    expect(find.text('مركز طلباتي'), findsOneWidget);

    await tester.tap(find.text('الرسائل'));
    await tester.pumpAndSettle();
    expect(find.text('المحادثات والتواصل'), findsOneWidget);

    await tester.tap(find.text('حسابي'));
    await tester.pumpAndSettle();
    expect(find.text('حسابي وإعداداتي'), findsOneWidget);

    // Service catalog multi-service selection
    await tester.pumpWidget(_wrapRtl(ServiceCatalogScreen(session: session)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إضافة').first);
    await tester.pump();
    expect(session.bookingDraft.serviceQuantities['svc-1'], 1);
    expect(find.text('متابعة الحجز'), findsOneWidget);

    // Booking Wizard opens cleanly on Step 2 when service already in cart
    await tester.pumpWidget(_wrapRtl(BookingWizardScreen(session: session)));
    await tester.pumpAndSettle();
    expect(find.text('حجز زيارة تمريضية'), findsOneWidget);
    expect(find.text('خالد أحمد'), findsOneWidget);
    // Flush the 280ms BookingDraftStore estimate debounce timer before binding invariants run
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
  });
}
