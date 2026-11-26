import test from 'node:test';
import assert from 'node:assert/strict';
import {
  buildNotificationPayload,
  deepLinkForEvent,
} from '../src/notifications/notification-routing.ts';

test('buildNotificationPayload emits all 16 required envelope fields for Patient & Nurse', () => {
  const patientEv = buildNotificationPayload({
    eventType: 'marketplace.proposal.created',
    recipientUserId: 'u-patient-1',
    recipientRole: 'PATIENT',
    requestId: 'req-123',
    proposalId: 'prop-456',
    entityVersion: 3,
    priority: 'HIGH',
  });

  assert.ok(patientEv.eventId);
  assert.equal(patientEv.eventType, 'marketplace.proposal.created');
  assert.equal(patientEv.recipientUserId, 'u-patient-1');
  assert.equal(patientEv.recipientRole, 'PATIENT');
  assert.equal(patientEv.targetApp, 'PATIENT_APP');
  assert.equal(patientEv.requestId, 'req-123');
  assert.equal(patientEv.proposalId, 'prop-456');
  assert.equal(patientEv.entityVersion, 3);
  assert.equal(patientEv.priority, 'HIGH');
  assert.ok(patientEv.createdAt);
  assert.equal(patientEv.deepLink, 'tamreedy://patient/requests/req-123/proposals');

  const nurseEv = buildNotificationPayload({
    eventType: 'offer.created',
    recipientUserId: 'u-nurse-1',
    recipientRole: 'NURSE',
    requestId: 'req-123',
    offerId: 'offer-789',
    priority: 'ALARM',
    expiresAt: '2026-11-26T12:00:00.000Z',
  });

  assert.equal(nurseEv.recipientRole, 'NURSE');
  assert.equal(nurseEv.targetApp, 'NURSE_APP');
  assert.equal(nurseEv.offerId, 'offer-789');
  assert.equal(nurseEv.expiresAt, '2026-11-26T12:00:00.000Z');
  assert.equal(nurseEv.deepLink, 'tamreedy://nurse/offers/offer-789');
  assert.equal(
    deepLinkForEvent('call.incoming', 'NURSE', { callId: 'call-9' }),
    'tamreedy://nurse/calls/call-9',
  );
});
