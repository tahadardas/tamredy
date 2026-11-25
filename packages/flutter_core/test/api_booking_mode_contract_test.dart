import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tamreedy_core/tamreedy_core.dart';

void main() {
  test(
    'open marketplace request follows the API booking-mode contract',
    () async {
      final api = TamreedyApi();
      Map<String, dynamic>? requestBody;

      api.dio.interceptors.clear();
      api.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            expect(request.path, '/v1/requests/request-1/booking-mode');
            requestBody = Map<String, dynamic>.from(request.data as Map);
            handler.resolve(
              Response(
                requestOptions: request,
                data: {
                  'requestId': 'request-1',
                  'bookingMode': 'OPEN',
                  'status': 'OPEN_FOR_PROPOSALS',
                },
              ),
            );
          },
        ),
      );

      await api.switchRequestToOpenMarketplace(
        'request-1',
        durationMinutes: 90,
      );

      expect(requestBody, {'bookingMode': 'OPEN', 'openDurationMinutes': 90});
    },
  );
}
