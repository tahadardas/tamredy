// Interim password auth + admin-provisioned accounts, on PGlite (PostGIS stripped).
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { PGlite } from '@electric-sql/pglite';

process.env.JWT_SECRET = 'test-secret-test-secret-test-secret-123';
process.env.NODE_ENV = 'development';
delete process.env.AUTH_MODE; // default = password mode
const root = resolve(import.meta.dirname, '../../..');
const { AuthService, hashPassword, verifyPassword } = await import('../dist/auth/auth.service.js');
const { AdminUsersController } = await import('../dist/admin/admin-users.controller.js');

const pg = new PGlite();
const strip = s => s.replace(/CREATE EXTENSION[^;]*;/g, '').replace(/geography\(Point,4326\)/g, 'text').replace(/CREATE INDEX[^;]*GIST[^;]*;/g, '');
for (const f of ['001_core', '003_admin_reads_audit', '004_auth_otp_refresh', '005_password_accounts_push'])
  await pg.exec(strip(readFileSync(resolve(root, `infra/db/migrations/${f}.sql`), 'utf8')));
let chain = Promise.resolve();
const db = {
  query: (s, p = []) => pg.query(s, p),
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
const auth = new AuthService(db, { send: async () => {} });
const users = new AdminUsersController(db);
const code = c => e => e.getResponse?.().code === c;
const adminId = (await pg.query(`INSERT INTO users(phone_e164,role,password_hash) VALUES('+963900000000','ADMIN',$1) RETURNING id`, [hashPassword('admin-password-123')])).rows[0].id;
const asAdmin = { user: { id: adminId, role: 'ADMIN' } };

test('password hashing round-trips and rejects wrong passwords', () => {
  const h = hashPassword('correct horse');
  assert.ok(verifyPassword('correct horse', h));
  assert.ok(!verifyPassword('wrong', h));
  assert.ok(!verifyPassword('x', null));
});

test('admin creates a nurse (pending licence) who can then log in', async () => {
  const made = await users.create(asAdmin, { phone: '+963911000001', role: 'NURSE', displayName: 'ممرض تجريبي', licenseRef: 'LIC-1', licenseExpiresAt: '2030-01-01' });
  assert.equal(made.temporaryPassword, '123456');
  const t = await auth.login('+963911000001', made.temporaryPassword);
  assert.equal(t.role, 'NURSE');
  const cred = (await pg.query(`SELECT review_status,approved FROM nurse_credentials`)).rows[0];
  assert.deepEqual([cred.review_status, cred.approved], ['PENDING', false]); // never auto-approved
  assert.equal((await pg.query(`SELECT count(*)::int n FROM audit_log WHERE action='user.created'`)).rows[0].n, 1);
});

test('patient is created with a staff-confirmed beneficiary; duplicate phone rejected', async () => {
  await users.create(asAdmin, { phone: '+963911000002', role: 'PATIENT', displayName: 'مريض', beneficiaryName: 'والدي', password: 'my-own-password' });
  assert.equal((await pg.query(`SELECT count(*)::int n FROM beneficiaries WHERE consent_status='GRANTED'`)).rows[0].n, 1);
  await assert.rejects(users.create(asAdmin, { phone: '+963911000002', role: 'PATIENT', displayName: 'x' }), codeIs('PHONE_ALREADY_REGISTERED'));
  assert.equal((await auth.login('+963911000002', 'my-own-password')).role, 'PATIENT');
});
function codeIs(c) { return code(c); }

test('wrong passwords lock the account after 5 failures', async () => {
  for (let i = 0; i < 5; i++) await assert.rejects(auth.login('+963911000002', 'bad-password-1'), code('LOGIN_INVALID'));
  await assert.rejects(auth.login('+963911000002', 'my-own-password'), code('ACCOUNT_LOCKED'));
});

test('reset-password unlocks and invalidates sessions; suspend blocks login', async () => {
  const id = (await pg.query(`SELECT id FROM users WHERE phone_e164='+963911000002'`)).rows[0].id;
  const r = await users.reset(asAdmin, id);
  assert.ok((await auth.login('+963911000002', r.temporaryPassword)).accessToken);
  await users.status(asAdmin, id, { status: 'SUSPENDED' });
  await assert.rejects(auth.login('+963911000002', r.temporaryPassword), code('LOGIN_INVALID'));
  await assert.rejects(users.status(asAdmin, adminId, { status: 'SUSPENDED' }), code('CANNOT_CHANGE_OWN_STATUS'));
});

test('OTP endpoints are off in password mode', async () => {
  await assert.rejects(auth.requestOtp('+963911000003'), code('OTP_DISABLED_PASSWORD_MODE'));
});

test('non-admins cannot provision accounts', async () => {
  await assert.rejects(() => users.create({ user: { id: adminId, role: 'PATIENT' } }, {}), e => e.getStatus?.() === 403);
});
