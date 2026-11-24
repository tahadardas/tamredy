// Runs against the compiled service (pnpm --filter @tamreedy/api build) and an
// in-process Postgres (PGlite). PostGIS tables are stripped: auth does not use them.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { PGlite } from '@electric-sql/pglite';

process.env.JWT_SECRET = 'test-secret-test-secret-test-secret-123';
process.env.NODE_ENV = 'development';
process.env.AUTH_MODE = 'otp';
const root = resolve(import.meta.dirname, '../../..');
const { AuthService, hashCode, SmsProvider } = await import('../dist/auth/auth.service.js');

const pg = new PGlite();
const strip = s => s.replace(/CREATE EXTENSION[^;]*;/g, '').replace(/geography\(Point,4326\)/g, 'text').replace(/CREATE INDEX[^;]*GIST[^;]*;/g, '');
await pg.exec(strip(readFileSync(resolve(root, 'infra/db/migrations/001_core.sql'), 'utf8')));
await pg.exec(readFileSync(resolve(root, 'infra/db/migrations/004_auth_otp_refresh.sql'), 'utf8'));
await pg.exec(readFileSync(resolve(root, 'infra/db/migrations/019_device_sessions_and_persistent_auth.sql'), 'utf8'));
await pg.exec(readFileSync(resolve(root, 'infra/db/migrations/025_manual_password_recovery.sql'), 'utf8'));

// Minimal DbService stand-in: one connection, serialised transactions.
let chain = Promise.resolve();
const db = {
  query: (sql, p = []) => pg.query(sql, p),
  transaction: run => {
    const result = chain.then(async () => {
      await pg.query('BEGIN');
      try { const r = await run({ query: (s, p = []) => pg.query(s, p) }); await pg.query('COMMIT'); return r; }
      catch (e) { await pg.query('ROLLBACK'); throw e; }
    });
    chain = result.catch(() => {});
    return result;
  },
};
let lastCode = '';
const sms = { send: async (_p, text) => { lastCode = text.match(/\d{6}/)[0]; } };
const auth = new AuthService(db, sms);
const phone = '+963911111111';
const codeIs = c => e => e.getResponse?.().code === c;
const code = async p => { await auth.requestOtp(p); return lastCode; };

test('login issues tokens and creates a PATIENT', async () => {
  const t = await auth.verifyOtp(phone, await code(phone));
  assert.equal(t.role, 'PATIENT');
  assert.ok(t.accessToken && t.refreshToken);
});

test('wrong code is rejected and counts attempts; correct code after lockout fails', async () => {
  const p = '+963922222222';
  const good = await code(p);
  const bad = good === '000000' ? '111111' : '000000';
  for (let i = 0; i < 5; i++) await assert.rejects(auth.verifyOtp(p, bad), /OTP_INVALID|Unauthorized/);
  await assert.rejects(auth.verifyOtp(p, good), /OTP_INVALID|Unauthorized/);
});

test('a code cannot be used twice', async () => {
  const p = '+963933333333';
  const c = await code(p);
  await auth.verifyOtp(p, c);
  await assert.rejects(auth.verifyOtp(p, c));
});

test('OTP requests are rate limited per phone', async () => {
  const p = '+963944444444';
  await auth.requestOtp(p); await auth.requestOtp(p); await auth.requestOtp(p);
  await assert.rejects(auth.requestOtp(p), e => e.getStatus?.() === 429);
});

test('refresh rotates; replaying an old token revokes the whole family', async () => {
  const p = '+963955555555';
  const t1 = await auth.verifyOtp(p, await code(p));
  const t2 = await auth.refresh(t1.refreshToken);
  assert.notEqual(t2.refreshToken, t1.refreshToken);
  await assert.rejects(auth.refresh(t1.refreshToken), codeIs('REFRESH_REUSED'));
  await assert.rejects(auth.refresh(t2.refreshToken), codeIs('REFRESH_REUSED')); // family revoked
});

test('logout revokes the family; admin accounts need MFA', async () => {
  const p = '+963966666666';
  const t = await auth.verifyOtp(p, await code(p));
  await auth.logout(t.refreshToken);
  await assert.rejects(auth.refresh(t.refreshToken));
  await pg.query(`INSERT INTO users(phone_e164,role) VALUES('+963977777777','ADMIN')`);
  await assert.rejects(auth.verifyOtp('+963977777777', await code('+963977777777')), codeIs('MFA_REQUIRED'));
});

test('code hash is bound to the phone number', () => {
  assert.notEqual(hashCode('+1', '123456'), hashCode('+2', '123456'));
  assert.ok(SmsProvider);
});

test('trusted device sessions persist and can be revoked', async () => {
  const p = '+963988888888';
  const deviceMeta = { deviceId: 'test-device-uuid-1', deviceName: 'Pixel 8 Pro', platform: 'android' };
  const t1 = await auth.verifyOtp(p, await code(p), deviceMeta);
  assert.ok(t1.accessToken && t1.refreshToken);

  // Check device session recorded
  const sessions = await pg.query('SELECT * FROM device_sessions WHERE device_id=$1', [deviceMeta.deviceId]);
  assert.equal(sessions.rowCount, 1);
  assert.equal(sessions.rows[0].device_name, 'Pixel 8 Pro');

  // Refresh with device ID updates last_seen_at
  const t2 = await auth.refresh(t1.refreshToken, deviceMeta.deviceId);
  assert.ok(t2.accessToken && t2.refreshToken);

  // Revoke device session
  await pg.query('UPDATE device_sessions SET revoked_at=now() WHERE device_id=$1', [deviceMeta.deviceId]);
  await assert.rejects(auth.refresh(t2.refreshToken, deviceMeta.deviceId), codeIs('SESSION_REVOKED'));
});
