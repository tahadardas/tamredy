import assert from 'node:assert/strict';
import test from 'node:test';
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
