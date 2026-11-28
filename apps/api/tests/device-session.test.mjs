import assert from 'node:assert/strict';
import test from 'node:test';
import { buildNotificationPayload } from '../dist/notifications/notification-routing.js';
import { requireActiveDeviceSession } from '../dist/auth/auth.guard.js';

const session = '081cea3b-7f75-4863-94e1-b1950a6155e5';
const owner = '019d403b-e778-42af-8813-e65b7cf590e4';

test('device-bound token requires a matching active session for its owner', async () => {
  const db = {
    async query(sql, parameters) {
      assert.match(sql, /user_id=\$2 AND revoked_at IS NULL/);
      return { rows: parameters[1] === owner ? [{}] : [] };
    },
  };
  await requireActiveDeviceSession(db, owner, session);
  await assert.rejects(requireActiveDeviceSession(db, 'another-user', session), {
    status: 401,
  });
});

test('device session lookup failure prevents authentication', async () => {
  const unavailable = new Error('database unavailable');
  const db = { async query() { throw unavailable; } };
  await assert.rejects(requireActiveDeviceSession(db, owner, session), unavailable);
});

test('connected sockets stop receiving private events after device revocation', async () => {
  const { LiveGateway } = await import('../dist/realtime/live.gateway.js');
  let revoked = false;
  const gateway = new LiveGateway({
    async query(sql) {
      if (sql.includes('FROM users')) return { rowCount: 1, rows: [{ auth_version: null,role:'PATIENT' }] };
      return { rows: revoked ? [] : [{}] };
    },
  }, {}, {}, {increment(){}}, {});
  let delivered = 0;
  let disconnected = false;
  const socket = {
    data: { role:'PATIENT',appType:'PATIENT_APP',auth: { sub: owner, dsi: session, exp: Math.floor(Date.now() / 1000) + 60 } },
    emit() { delivered++; },
    disconnect() { disconnected = true; },
  };
  gateway.io = {
    sockets: new Map([['socket', socket]]),
    adapter: { rooms: new Map([['user:' + owner, new Set(['socket'])]]) },
  };
  const envelope=buildNotificationPayload({eventType:'request.updated',recipientUserId:owner,recipientRole:'PATIENT'});
  await gateway.deliverPrivateEvent(owner, 'request.updated', envelope);
  revoked = true;
  await gateway.deliverPrivateEvent(owner, 'request.updated', envelope);
  assert.equal(delivered, 1);
  assert.equal(disconnected, true);
});
