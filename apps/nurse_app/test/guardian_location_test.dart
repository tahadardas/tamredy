import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import 'package:tamreedy_nurse_app/guardian_location.dart';

class MemoryPointStore implements SafetyPointStore {
  final data = <String, String>{};
  @override
  Future<String?> read(String account) async => data[account];
  @override
  Future<void> write(String account, String value) async {
    data[account] = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'foreground point survives failure and is acknowledged with its original sequence',
    () async {
      final api = TamreedyApi();
      final storage = MemoryPointStore();
      final stream = StreamController<SafetyFix>();
      var reachable = false;
      final requests = <List<dynamic>>[];
      final firstRequest = Completer<void>();
      api.dio.interceptors.clear();
      api.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            expect(
              request.path,
              '/v1/nurse/safety/sessions/visit/locations/batch',
            );
            final points = (request.data as Map)['points'] as List;
            requests.add(points);
            if (!firstRequest.isCompleted) firstRequest.complete();
            if (!reachable) {
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
                    'acceptedSequences': [8],
                  },
                ),
              );
            }
          },
        ),
      );
      final tracker = GuardianLocation(
        api,
        () async => 'nurse-a',
        store: storage,
        positions: () async => stream.stream,
      );
      final now = DateTime.now();
      await tracker.start('visit', now, 8);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      stream.add((
        latitude: 33.5,
        longitude: 36.3,
        accuracy: 15,
        capturedAt: now,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await firstRequest.future.timeout(const Duration(seconds: 2));
      expect(tracker.queued, 1);
      expect(requests.first.single['sequence'], 8);
      tracker.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(tracker.capturing, isFalse);
      tracker.dispose();
      await stream.close();

      reachable = true;
      final replacement = GuardianLocation(
        api,
        () async => 'nurse-a',
        store: storage,
      );
      await replacement.sync();
      expect(replacement.queued, 0);
      expect(requests.last, requests.first);
      replacement.dispose();
    },
  );
}
