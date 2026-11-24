import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import 'package:tamreedy_patient_app/controller.dart';

void main() {
  test(
    'reconnect restores an unknown active visit and coalesces tracking reads',
    () async {
      final controller = PatientController();
      addTearDown(controller.dispose);
      var trackingReads = 0;
      controller.api.dio.interceptors.clear();
      controller.api.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            final data = switch (request.path) {
              '/v1/me/active-request' => {
                'hasActive': true,
                'request': {
                  'id': 'visit',
                  'status': 'ASSIGNED',
                  'address_text': 'دمشق، المزة',
                },
              },
              '/v1/requests/mine' => {'items': []},
              '/v1/requests/visit/tracking' => {'status': 'EN_ROUTE'},
              _ => throw StateError('Unexpected path: ${request.path}'),
            };
            if (request.path.endsWith('/tracking')) trackingReads++;
            handler.resolve(Response(requestOptions: request, data: data));
          },
        ),
      );
      await controller.resync();
      expect(controller.requestId, 'visit');
      expect(controller.stage, VisitStage.assigned);
      await Future.wait([controller.resync(), controller.resync()]);
      expect(controller.stage, VisitStage.enRoute);
      expect(controller.nursePos, isNull);
      expect(controller.route, isNull);
      expect(trackingReads, 1);
    },
    skip: kDemoMode,
  );
}
