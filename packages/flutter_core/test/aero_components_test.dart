import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tamreedy_core/tamreedy_core.dart';

void main() {
  testWidgets('AeroChatView renders messages, advisory, and triggers send', (WidgetTester tester) async {
    String sentText = '';
    final messages = [
      AeroChatMessage(
        id: 'msg-1',
        senderId: 'user-1',
        senderName: 'محمد',
        text: 'مرحباً، متى ستصل للزيارة؟',
        createdAt: DateTime(2026, 12, 1, 14, 30),
        isMe: true,
        isRead: true,
      ),
      AeroChatMessage(
        id: 'msg-2',
        senderId: 'nurse-1',
        senderName: 'الممرض أحمد',
        text: 'أنا في الطريق وسأصل خلال 10 دقائق بإذن الله.',
        createdAt: DateTime(2026, 12, 1, 14, 32),
        isMe: false,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AeroChatView(
            recipientName: 'الممرض أحمد',
            recipientRole: 'ممرض مرخص',
            messages: messages,
            showContactAdvisory: true,
            onSendMessage: (text) => sentText = text,
          ),
        ),
      ),
    );

    // Verify recipient header
    expect(find.text('الممرض أحمد'), findsOneWidget);
    expect(find.text('ممرض مرخص'), findsOneWidget);

    // Verify contact advisory banner
    expect(find.textContaining('نوصي بالتواصل ضمن التطبيق'), findsOneWidget);

    // Verify message texts
    expect(find.text('مرحباً، متى ستصل للزيارة؟'), findsOneWidget);
    expect(find.text('أنا في الطريق وسأصل خلال 10 دقائق بإذن الله.'), findsOneWidget);

    // Enter text and send
    await tester.enterText(find.byType(TextField), 'شكراً لك بانتظارك');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(sentText, 'شكراً لك بانتظارك');
  });

  testWidgets('AeroSchedulePickerSheet switches modes and captures schedule', (WidgetTester tester) async {
    AeroScheduleResult? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AeroSchedulePickerSheet(
            initialImmediate: true,
            onConfirm: (res) => result = res,
          ),
        ),
      ),
    );

    expect(find.text('تحديد موعد الزيارة التمريضية'), findsOneWidget);
    expect(find.text('الآن (فوري)'), findsOneWidget);
    expect(find.text('موعد مسبق'), findsOneWidget);

    // Switch to scheduled mode
    await tester.tap(find.text('موعد مسبق'));
    await tester.pumpAndSettle();

    expect(find.text('اختر التاريخ:'), findsOneWidget);
    expect(find.text('غداً'), findsOneWidget);

    // Tap confirm scheduled
    await tester.tap(find.text('تثبيت الموعد المجدول'));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.isImmediate, false);
    expect(result!.timeWindow, isNotNull);
  });

  testWidgets('AeroCarePlanCard renders progress and handles tap', (WidgetTester tester) async {
    bool tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AeroCarePlanCard(
            title: 'خطة تغيير ضماد جراحي',
            frequency: 'كل يومين',
            totalVisits: 6,
            completedVisits: 3,
            status: 'ACTIVE',
            onTap: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.text('خطة تغيير ضماد جراحي'), findsOneWidget);
    expect(find.text('التكرار: كل يومين'), findsOneWidget);
    expect(find.text('الزيارات المنجزة: 3 من 6'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);

    await tester.tap(find.byType(AeroCarePlanCard));
    expect(tapped, true);
  });

  testWidgets('AeroFavoriteNurseCard displays nurse details and direct request button', (WidgetTester tester) async {
    bool requested = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AeroFavoriteNurseCard(
            name: 'سارة الأحمد',
            rating: 4.9,
            totalVisits: 28,
            skills: const ['حقن وريدي', 'عناية بالجروح'],
            onRequestDirect: () => requested = true,
          ),
        ),
      ),
    );

    expect(find.text('سارة الأحمد'), findsOneWidget);
    expect(find.text('4.9'), findsOneWidget);
    expect(find.text('(28 زيارة مكتملة)'), findsOneWidget);
    expect(find.text('حقن وريدي'), findsOneWidget);
    expect(find.text('عناية بالجروح'), findsOneWidget);

    await tester.tap(find.text('طلب زيارة مباشرة'));
    expect(requested, true);
  });

  testWidgets('AeroBookingModePickerSheet selects mode properly', (WidgetTester tester) async {
    AeroBookingMode? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AeroBookingModePickerSheet(
            initialMode: AeroBookingMode.instant,
            onSelectMode: (m) => selected = m,
          ),
        ),
      ),
    );

    expect(find.text('اختر طريقة الحجز'), findsOneWidget);
    expect(find.text('طلب فوري الآن'), findsOneWidget);
    expect(find.text('السوق المفتوح'), findsOneWidget);
    expect(find.text('حجز موعد مسبق'), findsOneWidget);

    await tester.tap(find.text('السوق المفتوح'));
    await tester.pump();
    expect(selected, AeroBookingMode.openMarketplace);
  });

  testWidgets('AeroInstantTimeoutSheet triggers recovery actions', (WidgetTester tester) async {
    bool keepOpen = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AeroInstantTimeoutSheet(
            onKeepOpenInMarketplace: () => keepOpen = true,
            onRetryInstant: () {},
            onScheduleVisit: () {},
            onCancelRequest: () {},
          ),
        ),
      ),
    );

    expect(find.text('لم نجد ممرضاً متاحاً فوراً'), findsOneWidget);
    expect(find.text('إبقاء الطلب مفتوحاً لاستقبال العروض'), findsOneWidget);
    expect(find.text('إعادة البحث الفوري الآن'), findsOneWidget);

    await tester.tap(find.text('إبقاء الطلب مفتوحاً لاستقبال العروض'));
    await tester.pump();
    expect(keepOpen, true);
  });

  testWidgets('AeroProposalCard displays nurse details and accepts proposal', (WidgetTester tester) async {
    bool accepted = false;

    final proposal = AeroProposalData(
      id: 'prop-123',
      nurseId: 'nurse-456',
      nurseName: 'سارة الأحمد',
      ratingAvg: 4.9,
      completedVisitsCount: 142,
      estimatedArrivalMinutes: 30,
      nurseNote: 'قادمة ومعي المعدات المعقمة',
      priceAmount: 150000,
      currencyCode: 'ل.س',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AeroProposalCard(
            proposal: proposal,
            onAccept: () => accepted = true,
            onDecline: () {},
          ),
        ),
      ),
    );

    expect(find.text('سارة الأحمد'), findsOneWidget);
    expect(find.text('4.9'), findsOneWidget);
    expect(find.text(' (142 زيارة)'), findsOneWidget);
    expect(find.text('150000 ل.س'), findsOneWidget);
    expect(find.text('يصل خلال 30 دقيقة تقريباً'), findsOneWidget);
    expect(find.text('قادمة ومعي المعدات المعقمة'), findsOneWidget);

    await tester.tap(find.text('قبول وتأكيد الزيارة'));
    await tester.pump();
    expect(accepted, true);
  });
}
