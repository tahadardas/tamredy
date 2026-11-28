import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import 'package:tamreedy_nurse_app/guardian.dart';
import 'package:tamreedy_nurse_app/guardian_sos_store.dart';

class SessionApi extends TamreedyApi {
  final starts = <Completer<Map<String, dynamic>>>[];

  @override
  Future<Map<String, dynamic>> post(
    String path, [
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    CancelToken? cancelToken,
  ]) {
    final result = Completer<Map<String, dynamic>>();
    starts.add(result);
    return result.future;
  }

  @override
  Future<Map<String, dynamic>> getMap(
    String path, {
    CancelToken? cancelToken,
  }) async => {'checkin': null};
}

class OwnerSosStore implements GuardianSosStore {
  final states = <String, GuardianSosState>{};
  Completer<GuardianSosState>? oldRead;

  @override
  Future<GuardianSosState> read(String owner) async {
    if (owner == 'nurse-a' && oldRead != null) return oldRead!.future;
    return states[owner] ?? (pending: null, receipt: null);
  }

  @override
  Future<void> write(String owner, GuardianSosState state) async =>
      states[owner] = state;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'RC2-011 a late previous-owner safety restore cannot fill the new account',
    () async {
      final api = SessionApi();
      final store = OwnerSosStore()..oldRead = Completer<GuardianSosState>();
      var owner = 'nurse-a';
      final guardian = GuardianController(
        api,
        store: store,
        accountId: () async => owner,
      );
      addTearDown(guardian.dispose);
      final oldRestore = guardian.restoreSos();
      await Future<void>.delayed(Duration.zero);
      guardian.resetForSessionChange();
      owner = 'nurse-b';
      await guardian.restoreSos();
      store.oldRead!.complete((
        pending: {'clientEventId': 'old-sos'},
        receipt: {'id': 'old-event'},
      ));
      await oldRestore;
      expect(guardian.event, isNull);
      expect(guardian.sosUnconfirmed, isFalse);
      expect(guardian.session, isNull);
    },
  );

  test(
    'RC2-011 superseded safety operation cannot clear the new loading state',
    () async {
      final api = SessionApi();
      final guardian = GuardianController(
        api,
        store: OwnerSosStore(),
        accountId: () async => 'nurse',
      );
      addTearDown(guardian.dispose);
      final oldStart = guardian.start('assignment-a');
      expect(guardian.busy, isTrue);
      guardian.resetForSessionChange();
      final newStart = guardian.start('assignment-b');
      api.starts[0].complete({'id': 'old-session'});
      await oldStart;
      expect(guardian.busy, isTrue);
      expect(guardian.session, isNull);
      api.starts[1].complete({'id': 'new-session'});
      await newStart;
      expect(guardian.busy, isFalse);
      expect(guardian.sessionId, 'new-session');
    },
  );

  test(
    'RC2-011 forced revocation clears memory and preserves owner-scoped SOS recovery',
    () async {
      final api = SessionApi();
      final store = OwnerSosStore();
      store.states['nurse-a'] = (
        pending: {'clientEventId': 'pending-a'},
        receipt: null,
      );
      var owner = 'nurse-a';
      final guardian = GuardianController(
        api,
        store: store,
        accountId: () async => owner,
      );
      addTearDown(guardian.dispose);
      await guardian.restoreSos();
      expect(guardian.sosUnconfirmed, isTrue);
      guardian.session = {'id': 'session-a'};
      guardian.resetForSessionChange();
      owner = 'nurse-b';
      await guardian.restoreSos();
      expect(guardian.sosUnconfirmed, isFalse);
      expect(guardian.sessionId, isNull);
      expect(store.states['nurse-a']!.pending!['clientEventId'], 'pending-a');
      guardian.resetForSessionChange();
      owner = 'nurse-a';
      await guardian.restoreSos();
      expect(guardian.sosUnconfirmed, isTrue);
    },
  );
}
