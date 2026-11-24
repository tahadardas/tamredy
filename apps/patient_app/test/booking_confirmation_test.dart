import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import 'package:tamreedy_patient_app/controller.dart';

void main() {
  test(
    'booking submits the selected beneficiary and prevents concurrent submission',
    () async {
      final controller = PatientController();
      addTearDown(controller.dispose);
      final requests = <Map<String, dynamic>>[];
      controller.api.dio.interceptors.clear();
      controller.api.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            if (request.path == '/v1/beneficiaries/mine') {
              handler.resolve(
                Response(
                  requestOptions: request,
                  data: [
                    {'id': 'first', 'display_name': 'المستفيد الأول'},
                    {'id': 'second', 'display_name': 'المستفيد الثاني'},
                  ],
                ),
              );
            } else {
              expect(request.path, '/v1/requests');
              expect(request.headers['Idempotency-Key'], isNotEmpty);
              requests.add(Map<String, dynamic>.from(request.data as Map));
              handler.resolve(
                Response(requestOptions: request, data: {'id': 'visit'}),
              );
            }
          },
        ),
      );
      await controller.loadBeneficiary();
      controller.selectBeneficiary('second');
      controller.service = kSampleServices.first;
      controller.selectVisitLocation(const LatLng(33.5, 36.3), 'دمشق، المزة');
      final first = controller.submit();
      expect(await controller.submit(), isFalse);
      expect(await first, isTrue);
      expect(requests.single['beneficiaryId'], 'second');
      expect(requests.single['addressText'], 'دمشق، المزة');
    },
    skip: kDemoMode,
  );
}
