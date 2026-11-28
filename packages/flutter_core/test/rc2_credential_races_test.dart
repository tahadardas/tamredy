import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tamreedy_core/tamreedy_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel=MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  late Map<String,String> values;
  Future<void> Function(String,String)? beforeWrite;
  setUp(() {
    values={'device_id':'test-device','access_token':'old-access','refresh_token':'old-refresh','cached_user_role':'PATIENT'};
    beforeWrite=null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel,(call) async {
      final args=Map<String,dynamic>.from(call.arguments as Map);
      final key=args['key'] as String?;
      switch(call.method) {
        case 'read': return values[key];
        case 'write':
          final value=args['value'] as String;
          if(beforeWrite!=null) await beforeWrite!(key!,value);
          values[key!]=value; return null;
        case 'delete': values.remove(key);return null;
        default: throw StateError('Unexpected storage operation ${call.method}');
      }
    });
  });
  tearDown(()=>TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel,null));

  Dio transport(Future<Map<String,dynamic>> Function(RequestOptions) respond) {
    final dio=Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest:(request,handler) async {
      handler.resolve(Response(requestOptions:request,statusCode:200,data:await respond(request)));
    }));
    return dio;
  }
  void loginResponses(TamreedyApi api,{Future<Map<String,dynamic>> Function(RequestOptions)? respond}) {
    api.dio.interceptors.clear();
    api.dio.interceptors.add(InterceptorsWrapper(onRequest:(request,handler) async {
      final body=request.data is Map ? request.data as Map : {};
      final user=body['phone'] ?? 'new';
      handler.resolve(Response(requestOptions:request,statusCode:200,data:respond==null ? {
        'accessToken':'$user-access','refreshToken':'$user-refresh','role':'PATIENT',
      } : await respond(request)));
    }));
  }

  test('logout cannot erase a newer login while remote revocation is delayed',() async {
    final blocked=Completer<void>();final release=Completer<void>();
    final api=TamreedyApi();
    loginResponses(api,respond:(request) async {
      if(request.path=='/v1/devices') {blocked.complete();await release.future;return {};}
      return {'accessToken':'new-access','refreshToken':'new-refresh','role':'PATIENT'};
    });
    final logout=api.logout();await blocked.future;
    await api.login('new','password');
    release.complete();await logout;
    expect(values['access_token'],'new-access');expect(values['refresh_token'],'new-refresh');
    expect(api.sessionChanging,false);expect(api.authSessionSignal.value,isNull);
  });

  test('session invalidation during secure token write cannot overwrite next account',() async {
    final blocked=Completer<void>();final release=Completer<void>();
    beforeWrite=(key,value) async {if(key=='access_token'&&value=='first-access'){blocked.complete();await release.future;}};
    final api=TamreedyApi();loginResponses(api);
    final first=api.login('first','password');
    final firstFailure=expectLater(first,throwsA(isA<DioException>()));
    await blocked.future;api.beginSessionChange();
    final second=api.login('second','password');release.complete();
    await firstFailure;await second;
    expect(values['access_token'],'second-access');expect(values['refresh_token'],'second-refresh');
    expect(values['cached_user_role'],'PATIENT');expect(api.sessionChanging,false);
  });

  test('refresh response from previous account cannot replace new credentials',() async {
    final blocked=Completer<void>();final release=Completer<void>();
    final refresh=transport((request) async {blocked.complete();await release.future;return {'accessToken':'stale-refresh-access','refreshToken':'stale-refresh-token'};});
    final api=TamreedyApi(refreshTransport:refresh);loginResponses(api);
    final refreshing=api.refreshNow();await blocked.future;
    api.beginSessionChange();await api.login('new','password');release.complete();
    expect(await refreshing,false);
    expect(values['access_token'],'new-access');expect(values['refresh_token'],'new-refresh');
  });
}
