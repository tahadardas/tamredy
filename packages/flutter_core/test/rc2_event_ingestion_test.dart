import 'package:flutter_test/flutter_test.dart';
import 'package:tamreedy_core/tamreedy_core.dart';

Map<String,dynamic> event({String user='patient-a',String id='event-1'}) => {
  'eventId':id,'eventType':'request.assigned','recipientUserId':user,
  'recipientRole':'PATIENT','targetApp':'PATIENT_APP','requestId':'request-a',
  'createdAt':DateTime.now().toUtc().toIso8601String(),
};

void main() {
  for (final sources in [['FCM','WS'],['WS','FCM'],['FCM'],['WS']]) {
    test('domain, presentation and tap remain independent for $sources', () async {
      final coordinator=NotificationCoordinator(expectedRole:'PATIENT',expectedApp:'PATIENT_APP',authenticatedUserId:'patient-a');
      final bus=RealtimeEventBus();
      addTearDown(coordinator.dispose); addTearDown(bus.dispose);
      var updates=0;var notifications=0;
      final subscription=bus.stream.listen((e) { if(e.type=='request.assigned') updates++; });
      addTearDown(subscription.cancel);
      for (final source in sources) {
        expect(source,isNotEmpty);
        ingestPrivateEvent(payload:event(),coordinator:coordinator,eventBus:bus,present:(raw) {
          if(coordinator.acceptEvent(AppNotificationEvent.fromMap(raw))) notifications++;
        });
      }
      await Future<void>.delayed(Duration.zero);
      expect(updates,1);expect(notifications,1);
      expect(coordinator.routeFromTap(event())?.requestId,'request-a');
      expect(coordinator.routeFromTap(event()),isNull);
    });
  }

  test('domain-only ingestion does not consume presentation eligibility', () {
    final coordinator=NotificationCoordinator(expectedRole:'PATIENT',expectedApp:'PATIENT_APP',authenticatedUserId:'patient-a');
    addTearDown(coordinator.dispose);
    var updates=0;var presented=0;
    ingestPrivateEvent(payload:event(),coordinator:coordinator,eventBus:null,onDomainEvent:(_)=>updates++);
    ingestPrivateEvent(payload:event(),coordinator:coordinator,eventBus:null,onDomainEvent:(_)=>updates++,present:(raw) {
      if(coordinator.acceptEvent(AppNotificationEvent.fromMap(raw))) presented++;
    });
    expect(updates,1);expect(presented,1);
  });

  test('private events require authenticated identity and cannot cross accounts', () {
    final coordinator=NotificationCoordinator(expectedRole:'PATIENT',expectedApp:'PATIENT_APP');
    addTearDown(coordinator.dispose);
    expect(coordinator.acceptDomainEvent(AppNotificationEvent.fromMap(event())),false);
    coordinator.routeFromTap(event(),coldStart:true);
    coordinator.setAuthenticatedUserId('patient-b');
    expect(coordinator.takePendingColdStartTarget(),isNull);
    expect(coordinator.acceptEvent(AppNotificationEvent.fromMap(event())),false);
    expect(coordinator.acceptDomainEvent(AppNotificationEvent.fromMap(event(user:'patient-b'))),true);
  });

  test('expiration applies to every private domain event', () {
    final coordinator=NotificationCoordinator(expectedRole:'PATIENT',expectedApp:'PATIENT_APP',authenticatedUserId:'patient-a');
    addTearDown(coordinator.dispose);
    final expired=event()..['expiresAt']=DateTime.now().subtract(const Duration(seconds:5)).toIso8601String();
    expect(coordinator.acceptDomainEvent(AppNotificationEvent.fromMap(expired)),false);
    expect(coordinator.acceptEvent(AppNotificationEvent.fromMap(expired)),false);
    expect(coordinator.routeFromTap(expired),isNull);
  });
}
