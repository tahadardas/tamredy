import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tamreedy_core/tamreedy_core.dart';

class CallSnapshotApi extends TamreedyApi {
  Map<String,dynamic> snapshot={'call_status':'RINGING','session_version':1,'signals':<dynamic>[]};
  @override
  Future<Map<String,dynamic>> getMap(String path,{CancelToken? cancelToken}) async => snapshot;
}

void main() {
  test('older call state cannot replace a newer version and terminal state cannot reopen',() async {
    final api=CallSnapshotApi(); final bus=RealtimeEventBus();
    final manager=CallManager(api:api,eventBus:bus);
    addTearDown(manager.dispose);addTearDown(bus.dispose);
    await manager.presentIncoming(callId:'call-a',requestId:'request-a',peerName:'أحمد',peerRole:'PATIENT');
    Future<void> deliver(String type,int version) async {
      bus.emit(eventId:'$type:$version',type:type,payload:{'callId':'call-a','sessionVersion':version});
      await Future<void>.delayed(Duration.zero);
    }
    await deliver('call.accepted',3);expect(manager.phase,CallPhase.accepted);
    await deliver('call.reconnecting',2);expect(manager.phase,CallPhase.accepted);
    api.snapshot={'call_status':'RINGING','session_version':1,'signals':<dynamic>[]};
    await manager.refresh();expect(manager.phase,CallPhase.accepted);
    await deliver('call.ended',4);expect(manager.phase,CallPhase.ended);
    await deliver('call.connected',5);expect(manager.phase,CallPhase.ended);
    manager.dismissOverlay();
    await manager.presentIncoming(callId:'call-a',requestId:'request-a',peerName:'أحمد',peerRole:'PATIENT');
    expect(manager.phase,CallPhase.idle);
    expect(manager.elapsedSeconds,0);
  });
}
