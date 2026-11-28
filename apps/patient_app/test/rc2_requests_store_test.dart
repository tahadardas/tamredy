import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import 'package:tamreedy_patient_app/features/requests/requests_store.dart';

class RequestsApi extends TamreedyApi {
  final calls = <String>[];
  late Future<Map<String,dynamic>> Function(String path) read;
  @override
  Future<Map<String,dynamic>> getMap(String path, {CancelToken? cancelToken}) {
    calls.add(path);
    return read(path);
  }
}
Map<String,dynamic> row(String id, String status, int version) => {
  'id':id, 'status':status, 'version':version, 'service_title':'رعاية منزلية',
};
void main() {
  test('disposed store cancels pending details without notifying listeners', () async {
    final api = RequestsApi();
    final response = Completer<Map<String, dynamic>>();
    api.read = (_) => response.future;
    final store = RequestsStore(api: api, eventBus: RealtimeEventBus());
    final read = store.loadRequestDetail('one');
    store.dispose();
    response.completeError(StateError('offline'));
    expect(await read, isNull);
  });
  test('superseded reconciliation keeps the last state visibly pending', () async {
    final api = RequestsApi();
    api.read = (_) async => row('one', 'ASSIGNED', 1);
    final store = RequestsStore(api: api, eventBus: RealtimeEventBus());
    await store.loadRequestDetail('one');
    final stale = Completer<Map<String, dynamic>>();
    final latest = Completer<Map<String, dynamic>>();
    var reads = 0;
    api.read = (path) => path.contains('active-request')
        ? Future.value({'requests': []})
        : (++reads == 1 ? stale.future : latest.future);
    final reconcile = store.refreshActiveOnly();
    await Future<void>.delayed(Duration.zero);
    final freshDetail = store.loadRequestDetail('one', force: true);
    stale.complete(row('one', 'ASSIGNED', 1));
    await reconcile;
    expect(store.reconciliationPending, contains('one'));
    latest.completeError(StateError('offline'));
    await freshDetail;
    expect(store.reconciliationPending, contains('one'));
    expect(store.requestById('one')!.status, 'ASSIGNED');
    api.read = (path) async => path.contains('active-request')
        ? {'requests': []} : row('one', 'CANCELLED', 2);
    await store.refreshActiveOnly();
    expect(store.reconciliationPending, isEmpty);
    expect(store.requestById('one')!.status, 'CANCELLED');
    store.dispose();
  });
  test('refresh singleflight releases after success and after failure', () async {
    final api = RequestsApi();
    var pending = Completer<Map<String,dynamic>>();
    api.read = (path) => path.contains('active-request') ? pending.future : Future.value({'items':[]});
    final store = RequestsStore(api:api, eventBus:RealtimeEventBus());
    final first = store.refreshAll();
    final duplicate = store.refreshAll();
    expect(identical(first, duplicate), isTrue);
    pending.complete({'requests':[]});
    await first;
    expect(api.calls.length, 2);
    pending = Completer<Map<String,dynamic>>();
    final failed = store.refreshAll();
    pending.completeError(StateError('offline'));
    await failed;
    expect(store.loading, isFalse);
    expect(store.error, isNotNull);
    pending = Completer<Map<String,dynamic>>();
    final retried = store.refreshAll();
    pending.complete({'requests':[]});
    await retried;
    expect(api.calls.length, 6);
    store.dispose();
  });
  test('detail refresh is singleflight and fetches a new confirmed version', () async {
    final api = RequestsApi();
    var pending = Completer<Map<String,dynamic>>();
    api.read = (_) => pending.future;
    final store = RequestsStore(api:api,eventBus:RealtimeEventBus());
    final first = store.loadRequestDetail('one');
    expect(identical(first,store.loadRequestDetail('one')),isTrue);
    pending.complete(row('one','ASSIGNED',1));
    await first;
    pending = Completer<Map<String,dynamic>>();
    final next = store.loadRequestDetail('one');
    pending.complete(row('one','COMPLETED',2));
    await next;
    expect(store.requestById('one')!.status,'COMPLETED');
    expect(api.calls.length,2);
    store.dispose();
  });
  test('absent active snapshot reconciles actual state and preserves history', () async {
    final api = RequestsApi();
    final store = RequestsStore(api:api,eventBus:RealtimeEventBus());
    api.read = (_) async => row('one','ASSIGNED',1);
    await store.loadRequestDetail('one');
    api.read = (path) async => path.contains('active-request') ? {'requests':[]} : row('one','CANCELLED',2);
    await store.refreshActiveOnly();
    expect(store.requestById('one')!.status,'CANCELLED');
    expect(store.pastRequests.map((r)=>r.id),contains('one'));
    expect(store.reconciliationPending,isEmpty);
    store.dispose();
  });
  test('active refresh cannot supersede history and session reset rejects late reads', () async {
    final api = RequestsApi();
    final history = Completer<Map<String,dynamic>>();
    api.read = (path) => path.contains('/mine') ? history.future : Future.value({'requests':[]});
    final store = RequestsStore(api:api,eventBus:RealtimeEventBus());
    final all = store.refreshAll();
    await store.refreshActiveOnly();
    history.complete({'items':[row('old','COMPLETED',3)]});
    await all;
    expect(store.requestById('old'),isNotNull);
    expect(store.loading,isFalse);
    final detail = Completer<Map<String,dynamic>>();
    api.read = (_) => detail.future;
    final late = store.loadRequestDetail('other');
    store.resetForSessionChange();
    detail.complete(row('other','ASSIGNED',1));
    await late;
    expect(store.allRequests,isEmpty);
    store.dispose();
  });
  test('old forced refresh cannot clear loading owned by newer refresh', () async {
    final api = RequestsApi();
    final old = Completer<Map<String,dynamic>>();
    final newer = Completer<Map<String,dynamic>>();
    var activeReads=0;
    api.read=(path) => path.contains('active-request')
        ? (++activeReads == 1 ? old.future : newer.future) : Future.value({'items':[]});
    final store=RequestsStore(api:api,eventBus:RealtimeEventBus());
    final a=store.refreshAll();
    final b=store.refreshAll(force:true);
    old.complete({'requests':[]});
    await a;
    expect(store.loading,isTrue);
    newer.complete({'requests':[]});
    await b;
    expect(store.loading,isFalse);
    store.dispose();
  });
}
