import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import 'package:tamreedy_nurse_app/guardian.dart';

void main() {
  test(
    'silent SOS retries the same event and distinguishes human acknowledgement',
    () async {
      final api = TamreedyApi();
      final guardian = GuardianController(api);
      addTearDown(guardian.dispose);
      final attempts = <Map<String, dynamic>>[];
      api.dio.interceptors.clear();
      api.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            if (request.path == '/v1/safety/sos') {
              attempts.add(Map<String, dynamic>.from(request.data as Map));
              if (attempts.length == 1) {
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
                    data: {'id': 'event-1', 'state': 'RECEIVED'},
                  ),
                );
              }
            } else {
              expect(request.path, '/v1/safety/events/event-1');
              handler.resolve(
                Response(
                  requestOptions: request,
                  data: {'id': 'event-1', 'state': 'ACKNOWLEDGED'},
                ),
              );
            }
          },
        ),
      );
      guardian.session = {'id': 'session-1'};
      await guardian.sendSos();
      expect(guardian.event, isNull);
      expect(guardian.sosUnconfirmed, isTrue);
      await guardian.sendSos();
      expect(attempts, hasLength(2));
      expect(attempts[0], attempts[1]);
      expect(attempts.first['silent'], isTrue);
      expect(attempts.first['sessionId'], 'session-1');
      expect(guardian.event?['state'], 'RECEIVED');
      await guardian.refreshSos();
      expect(guardian.event?['state'], 'ACKNOWLEDGED');
    },
  );
}
