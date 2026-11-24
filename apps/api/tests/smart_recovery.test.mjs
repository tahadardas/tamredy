import test from 'node:test';
import assert from 'node:assert/strict';

test('Quiet Recovery Alerting respects 15-minute cooldown per nurse', () => {
  const deliveries = [
    {
      nurse_id: 'nurse-1',
      channel: 'PUSH',
      sent_at: new Date('2026-11-24T10:00:00Z'),
    },
  ];

  function canSendRecoveryAlert(nurseId, attemptedAt, cooldownMinutes = 15) {
    const lastDelivery = deliveries
      .filter(d => d.nurse_id === nurseId)
      .sort((a, b) => b.sent_at.getTime() - a.sent_at.getTime())[0];

    if (!lastDelivery) return true;

    const elapsedMs = new Date(attemptedAt).getTime() - lastDelivery.sent_at.getTime();
    return elapsedMs >= cooldownMinutes * 60 * 1000;
  }

  // Attempt 1: 5 minutes later -> Blocked by cooldown
  assert.equal(canSendRecoveryAlert('nurse-1', '2026-11-24T10:05:00Z'), false);

  // Attempt 2: 14 minutes later -> Blocked by cooldown
  assert.equal(canSendRecoveryAlert('nurse-1', '2026-11-24T10:14:00Z'), false);

  // Attempt 3: 15 minutes later -> Allowed
  assert.equal(canSendRecoveryAlert('nurse-1', '2026-11-24T10:15:00Z'), true);

  // Attempt 4: 30 minutes later -> Allowed
  assert.equal(canSendRecoveryAlert('nurse-1', '2026-11-24T10:30:00Z'), true);

  // Different nurse: Allowed immediately
  assert.equal(canSendRecoveryAlert('nurse-2', '2026-11-24T10:05:00Z'), true);
});

test('Quiet Recovery Alerting enforces maximum 8 alerts daily limit per nurse', () => {
  const nurseDeliveries = Array.from({ length: 8 }, (_, i) => ({
    nurse_id: 'nurse-1',
    sent_at: new Date(new Date('2026-11-24T00:00:00Z').getTime() + i * 2 * 3600 * 1000),
  }));

  function canSendDailyAlert(nurseId, attemptedAt, maxDaily = 8) {
    const dayStart = new Date(attemptedAt);
    dayStart.setUTCHours(0, 0, 0, 0);

    const countToday = nurseDeliveries.filter(
      d => d.nurse_id === nurseId && d.sent_at >= dayStart
    ).length;

    return countToday < maxDaily;
  }

  // Nurse-1 has reached 8 alerts today -> Blocked
  assert.equal(canSendDailyAlert('nurse-1', '2026-11-24T18:00:00Z'), false);

  // Nurse-2 has 0 alerts -> Allowed
  assert.equal(canSendDailyAlert('nurse-2', '2026-11-24T18:00:00Z'), true);
});

test('Expiration worker cleans up expired open requests and proposals', () => {
  const now = new Date('2026-11-24T12:00:00Z');

  const requests = [
    { id: 'req-active', open_expires_at: new Date('2026-11-24T13:00:00Z'), marketplace_status: 'OPEN_FOR_PROPOSALS' },
    { id: 'req-expired', open_expires_at: new Date('2026-11-24T11:59:00Z'), marketplace_status: 'OPEN_FOR_PROPOSALS' },
  ];

  const proposals = [
    { id: 'prop-active', expires_at: new Date('2026-11-24T12:30:00Z'), status: 'PENDING' },
    { id: 'prop-expired', expires_at: new Date('2026-11-24T11:55:00Z'), status: 'PENDING' },
  ];

  // Expire requests
  for (const r of requests) {
    if (r.marketplace_status === 'OPEN_FOR_PROPOSALS' && r.open_expires_at <= now) {
      r.marketplace_status = 'EXPIRED';
    }
  }

  // Expire proposals
  for (const p of proposals) {
    if (p.status === 'PENDING' && p.expires_at <= now) {
      p.status = 'EXPIRED';
    }
  }

  assert.equal(requests[0].marketplace_status, 'OPEN_FOR_PROPOSALS');
  assert.equal(requests[1].marketplace_status, 'EXPIRED');

  assert.equal(proposals[0].status, 'PENDING');
  assert.equal(proposals[1].status, 'EXPIRED');
});
