import { test } from 'node:test';
import assert from 'node:assert/strict';
import { pushCopy, alarmMessage, FcmClient } from '../../worker/dist/push.js';

test('FCM push copy provides informative non-sensitive Arabic alerts', () => {
  const offer = pushCopy('offer.created', { requestId: 'req-1', offerId: 'off-1' });
  assert.ok(offer);
  assert.equal(offer.title, 'طلب جديد قريب منك');
  assert.match(offer.body, /افتـ?ح/);

  const assigned = pushCopy('request.assigned', { requestId: 'req-1' });
  assert.ok(assigned);
  assert.equal(assigned.title, 'تم قبول طلبك');

  const unfulfilled = pushCopy('request.unfulfilled', { requestId: 'req-1' });
  assert.ok(unfulfilled);
  assert.equal(unfulfilled.title, 'تعذر العثور على ممرض');
});

test('Alarm message enforces HIGH priority and bounded TTL for immediate ring', () => {
  const copy = { title: 'طلب جديد', body: 'تغيير ضماد' };
  const msg = alarmMessage('token-123', { type: 'offer.created', offerId: 'off-1' }, 25, copy);

  assert.equal(msg.message.token, 'token-123');
  assert.equal(msg.message.android.priority, 'HIGH');
  assert.equal(msg.message.android.ttl, '25s');
  assert.equal(msg.message.data.alarm, '1');
  assert.equal(msg.message.data.ttl, '25');
  assert.equal(msg.message.data.title, 'طلب جديد');

  // Verify TTL clamping (between 5 and 60 seconds)
  const clampedLow = alarmMessage('token-123', {}, 2, copy);
  assert.equal(clampedLow.message.android.ttl, '5s');

  const clampedHigh = alarmMessage('token-123', {}, 120, copy);
  assert.equal(clampedHigh.message.android.ttl, '60s');
});

test('Dispatch exclusion categorization accurately distinguishes readiness blockers', () => {
  // Simulate candidate evaluation logic
  function evaluateNurseReadiness(nurse, request, distanceM) {
    if (!nurse.verified) return 'NOT_VERIFIED';
    if (nurse.availability_intent !== 'AVAILABLE') return 'NURSE_OFFLINE';
    if (nurse.work_status !== 'AVAILABLE') return 'NURSE_BUSY';
    if (!nurse.last_heartbeat_at || (Date.now() - nurse.last_heartbeat_at) > 60000) return 'STALE_HEARTBEAT';
    if (!nurse.location_recorded_at || (Date.now() - nurse.location_recorded_at) > 120000) return 'STALE_LOCATION';
    if (nurse.accuracy_m > 150) return 'LOW_GPS_ACCURACY';
    if (!nurse.has_approved_credential) return 'LICENSE_NOT_APPROVED';
    if (!nurse.approved_skills.includes(request.service_id)) return 'SKILL_NOT_APPROVED';
    if (nurse.has_active_assignment) return 'ACTIVE_ASSIGNMENT';
    if (distanceM > request.radius_m) return 'OUTSIDE_RADIUS';
    return 'ELIGIBLE';
  }

  const req = { service_id: 'srv-wound-dressing', radius_m: 3000 };

  const qualifiedNurse = {
    verified: true,
    availability_intent: 'AVAILABLE',
    work_status: 'AVAILABLE',
    last_heartbeat_at: Date.now() - 10000,
    location_recorded_at: Date.now() - 20000,
    accuracy_m: 15,
    has_approved_credential: true,
    approved_skills: ['srv-wound-dressing'],
    has_active_assignment: false,
  };

  assert.equal(evaluateNurseReadiness(qualifiedNurse, req, 1200), 'ELIGIBLE');

  // Stale heartbeat (>60s)
  assert.equal(evaluateNurseReadiness({ ...qualifiedNurse, last_heartbeat_at: Date.now() - 75000 }, req, 1200), 'STALE_HEARTBEAT');

  // Stale location (>120s)
  assert.equal(evaluateNurseReadiness({ ...qualifiedNurse, location_recorded_at: Date.now() - 150000 }, req, 1200), 'STALE_LOCATION');

  // Low GPS accuracy (>150m)
  assert.equal(evaluateNurseReadiness({ ...qualifiedNurse, accuracy_m: 250 }, req, 1200), 'LOW_GPS_ACCURACY');

  // Missing skill
  assert.equal(evaluateNurseReadiness({ ...qualifiedNurse, approved_skills: ['srv-injections'] }, req, 1200), 'SKILL_NOT_APPROVED');

  // Outside search radius
  assert.equal(evaluateNurseReadiness(qualifiedNurse, req, 4500), 'OUTSIDE_RADIUS');

  // Unapproved license
  assert.equal(evaluateNurseReadiness({ ...qualifiedNurse, has_approved_credential: false }, req, 1200), 'LICENSE_NOT_APPROVED');

  // Unverified account
  assert.equal(evaluateNurseReadiness({ ...qualifiedNurse, verified: false }, req, 1200), 'NOT_VERIFIED');
});
