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
Map<String,dynamic> snapshot(String id,{required bool authorized}) => {'hasActive':true,'assignment':{
  'assignment_id':id,'request_id':'request-$id','assignment_status':'RESERVED','request_status':'SCHEDULED',
  'exact_location_authorized':authorized,'patient_name':authorized?'المريض أ':null,
  'beneficiary_name':authorized?'المستفيد أ':null,'address_text':authorized?'دمشق':null,
  'patient_lat':authorized?33.5:null,'patient_lng':authorized?36.3:null,'items':[]}};
void main(){
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
