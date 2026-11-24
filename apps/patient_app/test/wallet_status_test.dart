import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import 'package:tamreedy_patient_app/controller.dart';
import 'package:tamreedy_patient_app/main.dart';
import 'package:tamreedy_patient_app/screens/wallet.dart';

void main() {
  testWidgets(
    'wallet retries the server status without showing a local balance',
    (tester) async {
      final controller = PatientController();
      addTearDown(controller.dispose);
      var attempts = 0;
      controller.api.dio.interceptors.clear();
      controller.api.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            expect(request.path, '/v1/wallet/status');
            attempts++;
            if (attempts == 1) {
              handler.reject(
                DioException(
                  requestOptions: request,
                  type: DioExceptionType.connectionError,
                ),
              );
            } else {
              handler.resolve(
                Response(
                  requestOptions: request,
                  data: {
                    'mode': 'DISABLED',
                    'reason': 'LICENSED_PAYMENT_PROVIDER_REQUIRED',
                  },
                ),
              );
            }
          },
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: WalletScreen(
            c: controller,
            nav: TamBottomNav(items: patientNav, index: 2, onTap: (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('الرصيد المتاح'), findsNothing);
      await tester.tap(find.text('إعادة المحاولة'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(
        find.text(
          'شحن المحفظة والدفع عبرها غير متاحين حاليًا. يمكنك الدفع نقدًا للممرض.',
        ),
        findsOneWidget,
      );
      expect(controller.payMethod, 'cash');
    },
    skip: kDemoMode,
  );
}
