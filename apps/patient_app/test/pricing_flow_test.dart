import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tamreedy_patient_app/controller.dart';

void main() {
  test(
    'estimate appears instantly, promo lowers it, bad code is rejected',
    () async {
      final c = PatientController();
      c.api.dio.interceptors.clear();
      c.api.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path == '/v1/pricing/quote') {
              final promo = (options.data as Map?)?['promoCode']?.toString().toUpperCase();
              if (promo == 'WELCOME20') {
                return handler.resolve(
                  Response(
                    requestOptions: options,
                    data: {'min': 960, 'expected': 1280, 'discount': 320},
                  ),
                );
              } else {
                return handler.reject(
                  DioException(
                    requestOptions: options,
                    response: Response(
                      requestOptions: options,
                      statusCode: 400,
                      data: {'code': 'PROMO_NOT_FOUND'},
                    ),
                  ),
                );
              }
            }
            handler.next(options);
          },
        ),
      );

      c.services = kSampleServices;
      final dress = c.services.firstWhere((s) => s.id == 'dress');
      c.pick(dress);
      expect([c.est!.min, c.est!.expected], [1200, 1600]);
      await c.applyPromo('welcome20');
      expect(c.promoCode, 'WELCOME20');
      expect(c.est!.expected, lessThan(1600));
      await c.applyPromo('NOPE');
      expect(c.promoMsg, 'الكود غير صحيح');
      expect(c.promoCode, '');
      c.dispose();
    },
  );

  test(
    'bill is produced from the visit and matches the estimate rules',
    () async {
      final c = PatientController();
      c.api.dio.interceptors.clear();
      c.api.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path == '/v1/requests/x/bill') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  data: {
                    'minutes': 47,
                    'due': 2000,
                    'gross': 2000,
                    'surcharge': 0,
                    'distanceFee': 0,
                    'discount': 0,
                    'tax': 0,
                    'taxLabel': 'ضريبة',
                    'tip': 0,
                    'collected': 0,
                    'remaining': 2000,
                    'status': 'UNPAID',
                  },
                ),
              );
            }
            handler.next(options);
          },
        ),
      );

      c.services = kSampleServices;
      c.pick(c.services.firstWhere((s) => s.id == 'dress'));
      c.requestId = 'x';
      await c.loadBill();
      expect(c.bill!.minutes, 47);
      expect(c.bill!.due, 2000); // 47 min: base 1200 + 2 blocks x 400
      c.dispose();
    },
  );
}
