import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import 'package:tamreedy_patient_app/controller.dart';
import 'package:tamreedy_patient_app/screens/payment.dart';

void main() {
  testWidgets('RatingScreen starts unselected and submits detailed criteria to backend', (tester) async {
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final c = PatientController();
    c.bill = const BillInfo(
      due: 25000,
      collected: 25000,
      remaining: 0,
      status: 'PAID',
      minutes: 30,
      gross: 25000,
      discount: 0,
      tax: 0,
      taxLabel: '',
      tip: 0,
      surcharge: 0,
      distanceFee: 0,
      visitId: 'visit-123',
    );

    Map<String, dynamic>? sentPayload;
    c.api.dio.interceptors.clear();
    c.api.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.path == '/v1/visits/visit-123/patient-review') {
            sentPayload = Map<String, dynamic>.from(options.data as Map);
            handler.resolve(Response(requestOptions: options, data: {'id': 'rev-1'}));
            return;
          }
          handler.next(options);
        },
      ),
    );

    expect(c.rating, 0);
    expect(c.punctualityRating, 0);
    expect(c.clinicalRating, 0);
    expect(c.conductRating, 0);

    await tester.pumpWidget(
      MaterialApp(
        theme: tamreedyLightTheme(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: RatingScreen(c: c),
        ),
      ),
    );

    expect(find.text('ممتاز'), findsNothing);

    await tester.tap(find.bySemanticsLabel('5 من 5 نجوم'));
    await tester.tap(find.bySemanticsLabel('الالتزام بالموعد: 4 من 5'));
    await tester.tap(find.bySemanticsLabel('الاحترافية: 5 من 5'));
    await tester.tap(find.bySemanticsLabel('حسن التعامل: 3 من 5'));
    await tester.pump();

    await tester.runAsync(() => c.submitRating());

    expect(sentPayload, isNotNull);
    expect(sentPayload!['stars'], 5);
    expect(sentPayload!['overallStars'], 5);
    expect(sentPayload!['punctualityStars'], 4);
    expect(sentPayload!['clinicalStars'], 5);
    expect(sentPayload!['conductStars'], 3);

    c.dispose();
  });
}
