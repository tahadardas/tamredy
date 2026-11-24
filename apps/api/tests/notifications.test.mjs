import test from 'node:test';
import assert from 'node:assert/strict';

test('Notification payload scrubbing masks sensitive fields', () => {
  const scrubPayload = (data = {}) => {
    const scrubbed = { ...data };
    const sensitiveKeys = ['password', 'token', 'refreshtoken', 'secret', 'authcode', 'credit_card'];
    for (const key of Object.keys(scrubbed)) {
      if (sensitiveKeys.some(s => key.toLowerCase().includes(s))) {
        scrubbed[key] = '[REDACTED]';
      }
    }
    return scrubbed;
  };

  const rawData = {
    requestId: '123e4567-e89b-12d3-a456-426614174000',
    visitType: 'INJECTION',
    patientToken: 'super-secret-jwt-token-12345',
    userPasswordHash: 'md5orbcryptsecret',
    details: 'Nurse assigned to your care request',
  };

  const clean = scrubPayload(rawData);
  assert.equal(clean.requestId, '123e4567-e89b-12d3-a456-426614174000');
  assert.equal(clean.visitType, 'INJECTION');
  assert.equal(clean.details, 'Nurse assigned to your care request');
  assert.equal(clean.patientToken, '[REDACTED]');
  assert.equal(clean.userPasswordHash, '[REDACTED]');
});

test('Notification preferences filtering suppresses muted or disabled categories', () => {
  const shouldDeliverInApp = (prefs, category) => {
    if (!prefs.enableInApp) return false;
    if (prefs.mutedCategories?.includes(category)) return false;
    return true;
  };

  const userPrefs = {
    enablePush: true,
    enableInApp: true,
    mutedCategories: ['MARKETING_PROMO', 'SYSTEM_ANNOUNCEMENT'],
  };

  assert.equal(shouldDeliverInApp(userPrefs, 'VISIT_STATUS_CHANGED'), true);
  assert.equal(shouldDeliverInApp(userPrefs, 'MARKETING_PROMO'), false);
  assert.equal(shouldDeliverInApp(userPrefs, 'SYSTEM_ANNOUNCEMENT'), false);

  const disabledPrefs = {
    enablePush: true,
    enableInApp: false,
    mutedCategories: [],
  };
  assert.equal(shouldDeliverInApp(disabledPrefs, 'VISIT_STATUS_CHANGED'), false);
});

test('Notification read-all batching and unread counters', () => {
  let notifications = [
    { id: '1', title: 'Visit Scheduled', is_read: false },
    { id: '2', title: 'Nurse Arrived', is_read: false },
    { id: '3', title: 'Payment Confirmed', is_read: true },
  ];

  const getCounts = (list) => ({
    total: list.length,
    unread: list.filter(n => !n.is_read).length,
  });

  assert.deepEqual(getCounts(notifications), { total: 3, unread: 2 });

  // Mark single as read
  const notif1 = notifications.find(n => n.id === '1');
  if (notif1) notif1.is_read = true;
  assert.deepEqual(getCounts(notifications), { total: 3, unread: 1 });

  // Mark all as read
  notifications = notifications.map(n => ({ ...n, is_read: true }));
  assert.deepEqual(getCounts(notifications), { total: 3, unread: 0 });
});
