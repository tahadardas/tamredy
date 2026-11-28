import 'package:tamreedy_nurse_app/features/visit/pending_cash_collection_store.dart';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import 'package:tamreedy_nurse_app/features/visit/visit_store.dart';
class VisitApi extends TamreedyApi {
  late Future<Map<String,dynamic>> Function(String path) read;
  @override
  Future<Map<String,dynamic>> getMap(String path,{CancelToken? cancelToken}) => read(path);
}
class VisitCommandApi extends VisitApi {
  final local = <String, String>{};
  Map<String, dynamic> reply = {};
  String? sentKey;
  bool loseResponse = false;
  String owner = 'confirmed-nurse';
  Map<String,dynamic> lookup = {'found':false,'invoiceId':'bill-a','currencyCode':'SYP_NEW'};
  @override
  Future<Map<String,String>> readLocalByPrefix(String prefix) async =>
      Map.fromEntries(local.entries.where((entry) => entry.key.startsWith(prefix)));
  @override
  Future<Map<String,dynamic>> readCashCollection(String requestId,String key) async => lookup;
  @override
  Future<String?> currentUserId() async => owner;
  @override
  Future<String?> readLocal(String key) async => local[key];
  @override
  Future<void> writeLocal(String key, String? value) async {
    if (value == null) {
      local.remove(key);
    } else {
      local[key] = value;
    }
  }
  @override
  Future<Map<String, dynamic>> post(String path, [Map<String, dynamic>? body,
      Map<String, String>? headers, CancelToken? cancelToken]) async {
    sentKey = headers?['Idempotency-Key'];
    if (loseResponse) throw StateError('response lost');
    return reply;
  }
}
Map<String,dynamic> snapshot(String id,{required bool authorized}) => {'hasActive':true,'assignment':{
  'assignment_id':id,'request_id':'request-$id','assignment_status':'RESERVED','request_status':'SCHEDULED',
  'exact_location_authorized':authorized,'patient_name':authorized?'المريض أ':null,
  'beneficiary_name':authorized?'المستفيد أ':null,'address_text':authorized?'دمشق':null,
  'patient_lat':authorized?33.5:null,'patient_lng':authorized?36.3:null,'items':[]}};
void main(){
  test('legacy key, uncertain POST, failed bill refresh and a second equal payment', () async {
    final api = VisitCommandApi();
    api.local['cash_collect_v3_request-a_50'] = 'original-operation-key';
    var version = 1;
    var failBill = false;
    api.read = (_) async {
      if (failBill) throw StateError('bill unavailable');
      return {'requestId':'request-a','invoiceId':'bill-a','invoiceVersion':version,
        'currencyCode':'SYP_NEW','cashCollectionSupported':true,'due':100,'gross':100,
        'collected':(version-1)*50,'remaining':100-(version-1)*50,
        'paymentStatus':version==3?'PAID':version==2?'PARTIAL':'DUE','visitId':'visit-a'};
    };
    final store = VisitStore(api:api,eventBus:RealtimeEventBus(),onActiveAssignmentChanged:(_){});
    store.requestId = 'request-a';
    await store.loadBill();
    expect(api.sentKey,isNull);
    expect(store.canStartCashCollection,isFalse);
    api.loseResponse = true;
    expect(await store.resumeCashCollection(),CashCollectionOutcome.failed);
    expect(api.sentKey,'original-operation-key');
    api.loseResponse = false;
    api.reply = {'paymentId':'payment-a','invoiceId':'bill-a','currencyCode':'SYP_NEW','invoiceVersion':2,'change':0};
    failBill = true;
    expect(await store.resumeCashCollection(),CashCollectionOutcome.pendingReconciliation);
    expect(api.sentKey,'original-operation-key');
    expect(store.canStartCashCollection,isFalse);
    expect(store.pendingCashCollection!.status,CashCollectionStatus.confirmed);
    expect(await store.collectCash(50),CashCollectionOutcome.failed);
    failBill = false;
    version = 2;
    await store.loadBill();
    expect(store.canStartCashCollection,isTrue);
    expect(api.local.containsKey('cash_collect_v3_request-a_50'),isFalse);
    version = 3;
    api.reply = {'paymentId':'payment-b','invoiceId':'bill-a','currencyCode':'SYP_NEW','invoiceVersion':3,'change':0};
    expect(await store.collectCash(50),CashCollectionOutcome.fullyConfirmed);
    expect(api.sentKey,isNot('original-operation-key'));
    store.dispose();
  });

  test('cash recovery record is scoped to owner and invoice', () async {
    final api = VisitCommandApi();
    final operations = PendingCashCollectionStore(api);
    final bill = BillInfo.fromJson({'requestId':'request-a','invoiceId':'bill-a','invoiceVersion':1,
      'currencyCode':'SYP_NEW','paymentStatus':'DUE','remaining':100});
    final operation = operations.create('owner-a',bill,50);
    await operations.save('owner-a',bill,operation);
    expect(await operations.read('owner-b',bill),isNull);
    expect((await operations.read('owner-a',bill))!.key,operation.key);
  });
  test('no-service completion preserves reason without requesting an absent bill', () async {
    final api = VisitCommandApi();
    var reads = 0;
    api.read = (_) async { reads++; throw StateError('no invoice expected'); };
    api.reply = {'visitOutcome':'NOT_PERFORMED','visitOutcomeReason':'PATIENT_REFUSED'};
    final store = VisitStore(api:api,eventBus:RealtimeEventBus(),onActiveAssignmentChanged:(_){});
    store.assignmentId = 'assignment-a';
    store.requestId = 'request-a';
    store.phase = NurseVisitPhase.inService;
    await store.completeVisit();
    expect(store.phase,NurseVisitPhase.completed);
    expect(store.invoiceAbsent,isTrue);
    expect(store.visitOutcomeReason,'PATIENT_REFUSED');
    expect(store.bill,isNull);
    expect(reads,0);
    store.dispose();
  });
  test('new assignment and revoked location clear previous patient fields',() async {
    final api=VisitApi();
    api.read=(_)async=>snapshot('a',authorized:true);
    final store=VisitStore(api:api,eventBus:RealtimeEventBus(),onActiveAssignmentChanged:(_){});
    await store.restoreActiveAssignment();
    expect(store.addressText,'دمشق');
    expect(store.destination,isNotNull);
    api.read=(_)async=>snapshot('b',authorized:false);
    await store.restoreActiveAssignment();
    expect(store.assignmentId,'b');
    expect(store.patientName,isNull);
    expect(store.beneficiaryName,isNull);
    expect(store.addressText,isNull);
    expect(store.destination,isNull);
    expect(store.route,isNull);
    store.dispose();
  });
  test('late assignment detail does not repopulate previous patient after reset',()async{
    final api=VisitApi();
    api.read=(_)async=>snapshot('a',authorized:true);
    final store=VisitStore(api:api,eventBus:RealtimeEventBus(),onActiveAssignmentChanged:(_){});
    await store.restoreActiveAssignment();
    final response=Completer<Map<String,dynamic>>();
    api.read=(_)=>response.future;
    final detail=store.refreshAssignmentDetail();
    store.resetForSessionChange();
    response.complete({'patient_name':'المريض أ','address_text':'دمشق','exact_location_authorized':true});
    await detail;
    expect(store.patientName,isNull);
    expect(store.addressText,isNull);
    expect(store.loading,isFalse);
    store.dispose();
  });
  test('unknown location permission fails closed in typed assignment',(){
    final parsed=TypedAssignmentSnapshot.fromJson({'assignment_id':'a','request_status':'SCHEDULED'});
    expect(parsed.exactLocationAuthorized,isFalse);
  });
}
