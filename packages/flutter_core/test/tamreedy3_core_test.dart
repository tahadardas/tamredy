import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tamreedy_core/tamreedy_core.dart';

void main() {
  group('NotificationCoordinator role & app isolation + dedupe', () {
    test('Patient coordinator accepts PATIENT/PATIENT_APP and rejects NURSE/NURSE_APP', () {
      final coord = NotificationCoordinator(
        expectedRole: 'PATIENT',
        expectedApp: 'PATIENT_APP',
      );
      addTearDown(coord.dispose);

      final nurseEvent = AppNotificationEvent.fromMap({
        'eventId': 'ev-nurse-1',
        'eventType': 'offer.created',
        'recipientUserId': 'u1',
        'recipientRole': 'NURSE',
        'targetApp': 'NURSE_APP',
        'requestId': 'req-1',
        'offerId': 'off-1',
      });
      expect(coord.acceptEvent(nurseEvent), isFalse);

      final patientEvent = AppNotificationEvent.fromMap({
        'eventId': 'ev-pat-1',
        'eventType': 'marketplace.proposal.created',
        'recipientUserId': 'u1',
        'recipientRole': 'PATIENT',
        'targetApp': 'PATIENT_APP',
        'requestId': 'req-1',
        'proposalId': 'prop-1',
      });
      expect(coord.acceptEvent(patientEvent), isTrue);
      // Deduplicate same eventId
      expect(coord.acceptEvent(patientEvent), isFalse);

      final target = coord.routeFromTap({
        'eventId': 'ev-pat-tap',
        'eventType': 'marketplace.proposal.created',
        'recipientRole': 'PATIENT',
        'targetApp': 'PATIENT_APP',
        'requestId': 'req-1',
        'proposalId': 'prop-1',
      });
      expect(target?.kind, NotificationRouteKind.requestProposals);
      expect(target?.requestId, 'req-1');
    });

    test('Nurse coordinator rejects expired offers and patient events', () {
      final coord = NotificationCoordinator(
        expectedRole: 'NURSE',
        expectedApp: 'NURSE_APP',
      );
      addTearDown(coord.dispose);

      final expiredOffer = AppNotificationEvent.fromMap({
        'eventId': 'ev-exp-1',
        'eventType': 'offer.created',
        'recipientRole': 'NURSE',
        'targetApp': 'NURSE_APP',
        'offerId': 'off-expired',
        'expiresAt': DateTime.now().subtract(const Duration(minutes: 2)).toIso8601String(),
      });
      expect(coord.acceptEvent(expiredOffer), isFalse);

      final patientProposal = AppNotificationEvent.fromMap({
        'eventId': 'ev-p-2',
        'eventType': 'marketplace.proposal.created',
        'recipientRole': 'PATIENT',
        'targetApp': 'PATIENT_APP',
      });
      expect(coord.acceptEvent(patientProposal), isFalse);

      final callTarget = coord.routeFromTap({
        'eventId': 'ev-call-1',
        'eventType': 'call.incoming',
        'recipientRole': 'NURSE',
        'targetApp': 'NURSE_APP',
        'callId': 'call-123',
        'requestId': 'req-9',
      });
      expect(callTarget?.kind, NotificationRouteKind.incomingCall);
      expect(callTarget?.callId, 'call-123');
    });
  });

  group('RealtimeEventBus deduplication', () {
    test('drops duplicate eventId while forwarding distinct types', () async {
      final bus = RealtimeEventBus();
      addTearDown(bus.dispose);

      final received = <RealtimeEvent>[];
      final sub = bus.whereType(const {'visit.depart'}).listen(received.add);
      addTearDown(sub.cancel);

      expect(bus.emit(eventId: 'e1', type: 'visit.depart', payload: {'requestId': 'r1'}), isTrue);
      expect(bus.emit(eventId: 'e1', type: 'visit.depart', payload: {'requestId': 'r1'}), isFalse);
      expect(bus.emit(eventId: 'e2', type: 'tracking.updated', payload: {'requestId': 'r1'}), isTrue);

      await Future<void>.delayed(Duration.zero);
      expect(received.length, 1);
      expect(received.first.eventId, 'e1');
    });
  });

  group('ApiFailure mapping & categorization', () {
    DioException makeDio(int status, {dynamic data}) => DioException(
          requestOptions: RequestOptions(path: '/v1/test'),
          response: Response(
            requestOptions: RequestOptions(path: '/v1/test'),
            statusCode: status,
            data: data,
          ),
          type: DioExceptionType.badResponse,
        );

    test('accurately categorizes status codes and offline vs server errors', () {
      expect(mapApiFailure(makeDio(401)).kind, ApiErrorKind.sessionExpired);
      expect(mapApiFailure(makeDio(403)).kind, ApiErrorKind.forbidden);
      expect(mapApiFailure(makeDio(409)).kind, ApiErrorKind.conflict);
      expect(mapApiFailure(makeDio(422)).kind, ApiErrorKind.validation);
      expect(mapApiFailure(makeDio(429)).kind, ApiErrorKind.rateLimited);
      expect(mapApiFailure(makeDio(500)).kind, ApiErrorKind.internalError);
      expect(mapApiFailure(makeDio(501)).kind, ApiErrorKind.featureUnavailable);
      expect(mapApiFailure(makeDio(503)).kind, ApiErrorKind.serverUnavailable);
      expect(
        mapApiFailure(
          DioException(
            requestOptions: RequestOptions(path: '/v1/test'),
            type: DioExceptionType.connectionTimeout,
          ),
        ).kind,
        ApiErrorKind.timeout,
      );
      expect(
        explainError(makeDio(503)),
        isNot(contains('Exception')),
      );
    });
  });
}
