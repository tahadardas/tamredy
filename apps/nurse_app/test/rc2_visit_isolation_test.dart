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
  @override
  Future<String?> currentUserId() async => 'confirmed-nurse';
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
  test('upgrade retries an unresolved cash operation with its original key', () async {
    final api = VisitCommandApi();
    api.local['cash_collect_v3_request-a_50'] = 'original-operation-key';
    api.read = (_) async => {'due':100,'minutes':30,'gross':100,'discount':0,
      'collected':50,'remaining':50,'paymentStatus':'PARTIAL','visitId':'visit-a'};
    final store = VisitStore(api:api,eventBus:RealtimeEventBus(),onActiveAssignmentChanged:(_){});
    store.requestId = 'request-a';
    store.bill = const BillInfo(due:100,minutes:30,gross:100,discount:0,
      collected:0,remaining:100,status:'DUE',visitId:'visit-a');
    api.loseResponse = true;
    expect(await store.collectCash(50),isFalse);
    expect(api.sentKey,'original-operation-key');
    expect(api.local['cash_collect_v3_request-a_50'],'original-operation-key');
    api.loseResponse = false;
    api.reply = {'remaining':50,'change':0,'status':'PARTIALLY_PAID'};
    await store.collectCash(50);
    expect(api.sentKey,'original-operation-key');
    expect(store.bill!.collected,50);
    expect(api.local.containsKey('cash_collect_v3_request-a_50'),isFalse);
    store.dispose();
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
