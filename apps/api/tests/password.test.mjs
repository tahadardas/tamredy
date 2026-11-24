// Default password, forced first-login change, recovery, and the licence queue, on PGlite (PostGIS stripped).
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { PGlite } from '@electric-sql/pglite';
import jwt from 'jsonwebtoken';

process.env.JWT_SECRET = 'test-secret-test-secret-test-secret-123';
process.env.NODE_ENV = 'development';
process.env.UPLOADS_DIR = mkdtempSync(join(tmpdir(), 'tamreedy-pw-'));
delete process.env.AUTH_MODE;
const root = resolve(import.meta.dirname, '../../..');
const { AdminNursesController } = await import('../dist/admin/admin-nurses.controller.js');
const { AdminUsersController } = await import('../dist/admin/admin-users.controller.js');
const { AdminSettingsController } = await import('../dist/admin/admin-settings.controller.js');
const { AdminReportsController } = await import('../dist/admin/admin-reports.controller.js');
const { AccountController } = await import('../dist/auth/account.controller.js');
const { AuthGuard } = await import('../dist/auth/auth.guard.js');
const { AuthService, hashPassword } = await import('../dist/auth/auth.service.js');
const { DocStore } = await import('../dist/admin/doc-store.js');

const pg = new PGlite();
const strip = s => s.replace(/CREATE EXTENSION[^;]*;/g, '').replace(/geography\(Point,4326\)/g, 'text').replace(/CREATE INDEX[^;]*GIST[^;]*;/g, '');
for (const f of ['001_core', '003_admin_reads_audit', '004_auth_otp_refresh', '005_password_accounts_push', '006_pricing_promos_rewards', '009_nurse_admin_documents_settings', '011_regions', '013_default_password', '014_applications_doc_kinds', '019_device_sessions_and_persistent_auth', '025_manual_password_recovery'])
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
const nurses = new AdminNursesController(db, new DocStore());
const users = new AdminUsersController(db);
const settings = new AdminSettingsController(db);
const reports = new AdminReportsController(db);
const account = new AccountController(db, auth);
const guard = new AuthGuard(db);
const code = c => e => e.getResponse?.().code === c;
const adminId = (await pg.query(`INSERT INTO users(phone_e164,role,password_hash) VALUES('+963900000000','ADMIN',$1) RETURNING id`, [hashPassword('admin-password-123')])).rows[0].id;
const asAdmin = { user: { id: adminId, role: 'ADMIN' } };
const png = Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), Buffer.from('y'.repeat(40))]);
const ctx = (token, url) => ({ switchToHttp: () => ({ getRequest: () => ({ headers: { authorization: `Bearer ${token}` }, url }) }) });
let nurseId, phone = '+963911200001';

test('a nurse added by staff gets the default password and must change it at first login', async () => {
  const made = await nurses.create(asAdmin, { phone, displayName: 'ممرض افتراضي' });
  nurseId = made.id;
  assert.equal(made.temporaryPassword, '123456');
  const t = await auth.login(phone, '123456');
  assert.equal(t.role, 'NURSE'); assert.equal(t.mustChangePassword, true);
  // until the password is changed, only the auth routes work
  await assert.rejects(guard.canActivate(ctx(t.accessToken, '/v1/nurse/me/summary')), code('PASSWORD_CHANGE_REQUIRED'));
  assert.equal(await guard.canActivate(ctx(t.accessToken, '/v1/auth/me')), true);
});

test('change password: rejects weak/default/wrong values, then unlocks the account and ends old sessions', async () => {
  const t = await auth.login(phone, '123456');
  const uid = jwt.decode(t.accessToken).sub;
  const me = { user: { id: uid, role: 'NURSE' } };
  await assert.rejects(account.change(me, { currentPassword: 'wrong-password', newPassword: 'a-good-new-pass' }), code('WRONG_PASSWORD'));
  await assert.rejects(account.change(me, { currentPassword: '123456', newPassword: '123456' }), code('WEAK_PASSWORD'));
  await assert.rejects(account.change(me, { currentPassword: '123456', newPassword: '12345' }), code('WEAK_PASSWORD'));
  await assert.rejects(account.change(me, { currentPassword: '123456', newPassword: '11111111' }), code('WEAK_PASSWORD'));
  const fresh = await account.change(me, { currentPassword: '123456', newPassword: 'my-new-password' });
  assert.ok(fresh.accessToken);
  await assert.rejects(guard.canActivate(ctx(t.accessToken, '/v1/auth/me')), code('SESSION_REVOKED'));
  assert.equal(await guard.canActivate(ctx(fresh.accessToken, '/v1/nurse/me/summary')), true);   // now unrestricted
  await assert.rejects(auth.login(phone, '123456'), code('LOGIN_INVALID'));
  assert.equal((await auth.login(phone, 'my-new-password')).mustChangePassword, false);
  await assert.rejects(auth.refresh(t.refreshToken), e => true);                                  // the old session was revoked
});

test('recovery from the dashboard: reset issues an expiring random password, forces a change, ends sessions', async () => {
  const old = await auth.login(phone, 'my-new-password');
  const r = await nurses.resetPassword(asAdmin, nurseId);
  assert.equal(r.temporaryPassword.length, 20);
  assert.equal((await auth.login(phone, r.temporaryPassword)).mustChangePassword, true);
  await assert.rejects(guard.canActivate(ctx(old.accessToken, '/v1/auth/me')), code('SESSION_REVOKED'));
  await assert.rejects(auth.refresh(old.refreshToken));
  await pg.query("UPDATE users SET temporary_password_expires_at=now()-interval '1 minute' WHERE phone_e164=$1", [phone]);
  await assert.rejects(auth.login(phone, r.temporaryPassword), code('LOGIN_INVALID'));
  await assert.rejects(nurses.resetPassword({ user: { id: adminId, role: 'CLINICAL_REVIEWER' } }, nurseId), e => e.getStatus?.() === 403);
  // The same unique credential policy applies to both patient and staff.
  const pid = (await pg.query(`INSERT INTO users(phone_e164,role,password_hash) VALUES('+963911200009','PATIENT','x') RETURNING id`)).rows[0].id;
  assert.equal((await users.reset(asAdmin, pid)).temporaryPassword.length, 20);
  const sid = (await pg.query(`INSERT INTO users(phone_e164,role,password_hash) VALUES('+963900000005','ADMIN','x') RETURNING id`)).rows[0].id;
  assert.notEqual((await users.reset(asAdmin, sid)).temporaryPassword, '123456');
});

test('the default password is editable and validated', async () => {
  await assert.rejects(settings.save(asAdmin, 'security', { idleMinutes: 20, passwordMinLength: 12, defaultPassword: '123' }), code('BAD_DEFAULT_PW'));
  await settings.save(asAdmin, 'security', { idleMinutes: 20, passwordMinLength: 12, defaultPassword: '654321' });
  assert.equal((await nurses.create(asAdmin, { phone: '+963911200002', displayName: 'ثانٍ' })).temporaryPassword, '654321');
  await settings.save(asAdmin, 'security', { idleMinutes: 20, passwordMinLength: 12, defaultPassword: '123456' });
});

test('licence queue: a licence upload always reaches the approval list with the nurse name; approval is immediate', async () => {
  await assert.rejects(nurses.upload(asAdmin, nurseId, { buffer: png, originalname: 'l.png', size: png.length }, { kind: 'LICENSE' }), code('LICENSE_FIELDS_TOGETHER'));
  await assert.rejects(nurses.upload(asAdmin, nurseId, { buffer: png, originalname: 'l.png', size: png.length }, { kind: 'LICENSE', licenseRef: 'R-1' }), code('LICENSE_FIELDS_TOGETHER'));
  const up = await nurses.upload(asAdmin, nurseId, { buffer: png, originalname: 'l.png', size: png.length }, { kind: 'LICENSE', licenseRef: 'R-1', expiresAt: '2032-01-01' });
  assert.ok(up.credentialId);
  const pending = (await reports.pending(asAdmin)).items;
  assert.equal(pending.length, 1);
  assert.equal(pending[0].nurse_name, 'ممرض افتراضي'); assert.equal(pending[0].document_id, up.id);
  const done = await reports.decide(asAdmin, up.credentialId, { decision: 'APPROVE' });
  // Approval must not advertise the shared default after a manual reset.
  assert.deepEqual([done.account.phone, done.account.usingDefaultPassword, done.account.defaultPassword], [phone, false, undefined]);
  assert.equal((await reports.pending(asAdmin)).items.length, 0);
  assert.equal((await pg.query('SELECT verified FROM nurses WHERE id=$1', [nurseId])).rows[0].verified, true);
});
