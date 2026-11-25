import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import 'package:tamreedy_patient_app/controller.dart';
import 'package:tamreedy_patient_app/main.dart';

void main() {
  Future<PatientController> pumpRecoveryScreen(
    WidgetTester tester, {
    required void Function(RequestOptions, RequestInterceptorHandler) onRequest,
  }) async {
    final controller = PatientController();
    controller.requestId = 'request-1';
    controller.stage = VisitStage.unfulfilled;
    controller.setTab(1);
    controller.api.dio.interceptors.clear();
    controller.api.dio.interceptors.add(
      InterceptorsWrapper(onRequest: onRequest),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: tamreedyTheme(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: PatientShell(c: controller),
        ),
      ),
    );

    return controller;
  }

  testWidgets('keep-open button publishes the request to the marketplace', (
    tester,
  ) async {
    final previousMapsEnabled = mapsEnabled;
    mapsEnabled = false;
    addTearDown(() => mapsEnabled = previousMapsEnabled);
    final controller = await pumpRecoveryScreen(
      tester,
      onRequest: (request, handler) {
        expect(request.path, '/v1/requests/request-1/booking-mode');
        handler.resolve(
          Response(
            requestOptions: request,
            data: {
              'requestId': 'request-1',
              'bookingMode': 'OPEN',
              'status': 'OPEN_FOR_PROPOSALS',
              'openExpiresAt': '2026-11-24T20:00:00.000Z',
            },
          ),
        );
      },
    );

    await tester.tap(find.text('إبقاء الطلب مفتوحاً للعروض'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(controller.stage, VisitStage.openMarketplace);
    expect(controller.openExpiresAt, isNotNull);
    controller.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('retry button starts a new instant search', (tester) async {
    final previousMapsEnabled = mapsEnabled;
    mapsEnabled = false;
    addTearDown(() => mapsEnabled = previousMapsEnabled);
    final controller = await pumpRecoveryScreen(
      tester,
      onRequest: (request, handler) {
        expect(request.path, '/v1/requests/request-1/retry-dispatch');
        handler.resolve(
          Response(
            requestOptions: request,
            data: {
              'requestId': 'request-1',
              'bookingMode': 'INSTANT',
              'status': 'OFFERING',
              'retried': true,
            },
          ),
        );
      },
    );

    await tester.tap(find.text('إعادة البحث الفوري الآن'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(controller.stage, VisitStage.searching);
    controller.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
