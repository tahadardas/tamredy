import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import 'package:tamreedy_nurse_app/guardian.dart';
import 'package:tamreedy_nurse_app/guardian_sos_store.dart';

class MemorySosStore implements GuardianSosStore {
  final items = <String, GuardianSosState>{};

  @override
  Future<GuardianSosState> read(String owner) async =>
      items[owner] ?? (pending: null, receipt: null);

  @override
  Future<void> write(String owner, GuardianSosState state) async {
    items[owner] = state;
  }
}

void main() {
  test(
    'silent SOS survives restart, retries the same event, and isolates accounts',
    () async {
      final api = TamreedyApi();
      final store = MemorySosStore();
      var account = 'nurse-a';
      GuardianController open() =>
          GuardianController(api, store: store, accountId: () async => account);
      final guardian = open();
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
      final restarted = open();
      addTearDown(restarted.dispose);
      await restarted.restoreSos();
      expect(restarted.sosUnconfirmed, isTrue);
      expect(restarted.sosTriggeredAt, isNotNull);
      await restarted.sendSos();
      expect(attempts, hasLength(2));
      expect(attempts[0], attempts[1]);
      expect(attempts.first['silent'], isTrue);
      expect(attempts.first['sessionId'], 'session-1');
      expect(restarted.event?['state'], 'RECEIVED');
      await restarted.refreshSos();
      expect(restarted.event?['state'], 'ACKNOWLEDGED');
      account = 'nurse-b';
      await restarted.restoreSos();
      expect(restarted.event, isNull);
      expect(restarted.sosUnconfirmed, isFalse);
      account = 'nurse-a';
      await restarted.restoreSos();
      expect(restarted.event?['state'], 'ACKNOWLEDGED');
    },
  );
}
