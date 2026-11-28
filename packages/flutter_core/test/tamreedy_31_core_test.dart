import 'package:flutter_test/flutter_test.dart';
import 'package:tamreedy_core/tamreedy_core.dart';

void main() {
  test('TypedAssignmentSnapshot separates assignment_status from request_status (BUG-001)', () {
    final activeSnap = TypedAssignmentSnapshot.fromJson({
      'assignment_id': 'a-1',
      'assignment_status': 'ACTIVE',
      'request_id': 'r-1',
      'request_status': 'EN_ROUTE',
      'version': 4,
      'departure_window_open': true,
      'allowedActions': ['arrive'],
      'service_title': 'رعاية منزلية',
      'beneficiary_name': 'أحمد',
    });
    expect(activeSnap.assignmentStatus, 'ACTIVE');
    expect(activeSnap.requestStatus, 'EN_ROUTE');
    expect(activeSnap.version, 4);
    expect(activeSnap.allowedActions, ['arrive']);

    final reservedSnap = TypedAssignmentSnapshot.fromJson({
      'assignment_id': 'a-2',
      'assignment_status': 'RESERVED',
      'request_id': 'r-2',
      'request_status': 'ASSIGNED',
      'departure_window_open': false,
      'allowedActions': <String>[],
    });
    expect(reservedSnap.assignmentStatus, 'RESERVED');
    expect(reservedSnap.requestStatus, 'ASSIGNED');
    expect(reservedSnap.departureWindowOpen, false);
  });

  test('TypedCareRequest mergePreferRicher retains version and richer non-empty details (BUG-004/005)', () {
    final full = TypedCareRequest.fromJson({
      'id': 'req-1',
      'status': 'EN_ROUTE',
      'version': 3,
      'service_title': 'حقن وريدي',
      'beneficiary_name': 'سلمى',
      'nurse_name': 'ممرض طارق',
      'assigned_nurse_id': 'n-1',
      'address_text': 'دمشق',
    });
    final thin = TypedCareRequest.fromJson({
      'id': 'req-1',
      'status': 'EN_ROUTE',
      'version': 2,
      'service_title': 'حقن وريدي',
      'beneficiary_name': 'سلمى',
    });
    final merged = full.mergePreferRicher(thin);
    expect(merged.version, 3);
    expect(merged.nurseName, 'ممرض طارق');
    expect(merged.addressText, 'دمشق');
  });

  test('NotificationCoordinator enforces role/app/user isolation and deduplicates eventId (BUG-028/029)', () {
    final coord = NotificationCoordinator(expectedRole: 'NURSE', expectedApp: 'NURSE_APP');
    addTearDown(coord.dispose);
    coord.setAuthenticatedUserId('user-nurse-1');

    // Cross-role event MUST be rejected even for same user ID or mismatched role
    final wrongRole = coord.acceptEvent(AppNotificationEvent.fromMap({
      'eventId': 'evt-1',
      'eventType': 'request.assigned',
      'recipientUserId': 'user-nurse-1',
      'recipientRole': 'PATIENT',
      'targetApp': 'PATIENT_APP',
      'requestId': 'req-1',
    }));
    expect(wrongRole, false);

    // Wrong user ID MUST be rejected
    final wrongUser = coord.acceptEvent(AppNotificationEvent.fromMap({
      'eventId': 'evt-2',
      'eventType': 'offer.created',
      'recipientUserId': 'user-nurse-other',
      'recipientRole': 'NURSE',
      'targetApp': 'NURSE_APP',
      'requestId': 'req-1',
      'offerId': 'off-1',
    }));
    expect(wrongUser, false);

    // Valid event accepted once, duplicate eventId dropped
    final validEvt = AppNotificationEvent.fromMap({
      'eventId': 'evt-3',
      'eventType': 'offer.created',
      'recipientUserId': 'user-nurse-1',
      'recipientRole': 'NURSE',
      'targetApp': 'NURSE_APP',
      'requestId': 'req-1',
      'offerId': 'off-1',
    });
    expect(coord.acceptEvent(validEvt, dedupe: true), true);
    expect(coord.acceptEvent(validEvt, dedupe: true), false);
  });

  test('ServerCapabilities and SessionInitState map runtime capability flags cleanly (BUG-046/047)', () {
    final caps = ServerCapabilities.fromJson({
      'scheduledVisitsEnabled': false,
      'openMarketplaceEnabled': true,
      'ordersAccepting': true,
    });
    expect(caps.scheduledVisitsEnabled, false);
    expect(caps.openMarketplaceEnabled, true);
    expect(SessionInitState.values, contains(SessionInitState.partial));
  });

  test('CallManager keeps phase at connecting on server CONNECTED until local ICE connects (BUG-040)', () async {
    final bus = RealtimeEventBus();
    final api = TamreedyApi(appType: 'PATIENT_APP');
    final cm = CallManager(api: api, eventBus: bus);
    addTearDown(() {
      cm.dispose();
      bus.dispose();
    });

    bus.emit(
      eventId: 'evt-in-1',
      type: 'call.incoming',
      payload: {'callId': 'call-1', 'requestId': 'req-1', 'callerRole': 'NURSE', 'sessionVersion':1},
    );
    await Future<void>.delayed(Duration.zero);
    expect(cm.callId, 'call-1');
    expect(cm.phase, CallPhase.ringing);

    // Server broadcasts call.connected before local WebRTC ICE is established -> must stay connecting (0s elapsed)
    bus.emit(
      eventId: 'evt-conn-1',
      type: 'call.connected',
      payload: {'callId': 'call-1', 'sessionVersion':2},
    );
    await Future<void>.delayed(Duration.zero);
    expect(cm.phase, CallPhase.connecting);
    expect(cm.elapsedSeconds, 0);
  });
}
