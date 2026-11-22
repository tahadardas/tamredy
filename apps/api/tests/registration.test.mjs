// Patient self-registration and the nurse's own document upload (for staff-created nurses), on PGlite (PostGIS stripped).
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { PGlite } from '@electric-sql/pglite';

process.env.JWT_SECRET = 'test-secret-test-secret-test-secret-123';
process.env.NODE_ENV = 'development';
process.env.UPLOADS_DIR = mkdtempSync(join(tmpdir(), 'tamreedy-reg-'));
delete process.env.AUTH_MODE;
const root = resolve(import.meta.dirname, '../../..');
const { RegistrationController, NurseOnboardingController } = await import('../dist/auth/registration.controller.js');
const { AuthService } = await import('../dist/auth/auth.service.js');
const { DocStore } = await import('../dist/admin/doc-store.js');

const pg = new PGlite();
const strip = s => s.replace(/CREATE EXTENSION[^;]*;/g, '').replace(/geography\(Point,4326\)/g, 'text').replace(/CREATE INDEX[^;]*GIST[^;]*;/g, '');
for (const f of ['001_core', '003_admin_reads_audit', '004_auth_otp_refresh', '005_password_accounts_push', '006_pricing_promos_rewards', '009_nurse_admin_documents_settings', '010_self_registration', '011_regions', '014_applications_doc_kinds'])
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
const reg = new RegistrationController(db, auth);
const onboarding = new NurseOnboardingController(db, new DocStore());
const code = c => e => e.getResponse?.().code === c;
const ip = { ip: '1.1.1.1' };
const png = Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), Buffer.from('x'.repeat(40))]);

test('patient registers, is signed in, and has a consenting self-beneficiary', async () => {
  const t = await reg.patient(ip, { phone: '+963911100001', displayName: 'مريض جديد', password: 'password-123' });
  assert.ok(t.accessToken && t.refreshToken);
  assert.equal((await auth.login('+963911100001', 'password-123')).role, 'PATIENT');
  assert.deepEqual((await pg.query(`SELECT display_name,consent_status FROM beneficiaries`)).rows, [{ display_name: 'مريض جديد', consent_status: 'GRANTED' }]);
  await assert.rejects(reg.patient(ip, { phone: '+963911100001', displayName: 'x', password: 'password-123' }), code('PHONE_ALREADY_REGISTERED'));
});

test('patient registration can be closed by the admin and is throttled per IP', async () => {
  await pg.query(`UPDATE app_settings SET value='{"patients":false,"nurses":true}' WHERE key='registration'`);
  await assert.rejects(reg.patient({ ip: '2.2.2.2' }, { phone: '+963911100010', displayName: 'x', password: 'password-123' }), code('REGISTRATION_CLOSED'));
  await pg.query(`UPDATE app_settings SET value='{"patients":true,"nurses":true}' WHERE key='registration'`);
  for (let i = 0; i < 8; i++) await reg.patient({ ip: '3.3.3.3' }, { phone: `+96391110002${i}`, displayName: 'p' + i, password: 'password-123' });
  await assert.rejects(reg.patient({ ip: '3.3.3.3' }, { phone: '+963911100099', displayName: 'x', password: 'password-123' }), code('TOO_MANY_REGISTRATIONS'));
});

test('the public nurse self-registration route no longer exists (accounts come only from approved applications)', () => {
  assert.equal(typeof reg.nurse, 'undefined');
});

test('a staff-created nurse uploads a licence: it is named after them, stored in its category folder, and queued', async () => {
  const uid = (await pg.query(`INSERT INTO users(phone_e164,role,display_name,password_hash) VALUES('+963911100002','NURSE','سارة أحمد','x') RETURNING id`)).rows[0].id;
  await pg.query('INSERT INTO nurses(user_id) VALUES($1)', [uid]);
  const asNurse = { user: { id: uid, role: 'NURSE' } };
  assert.equal((await onboarding.status(asNurse)).verified, false);
  await assert.rejects(onboarding.upload(asNurse, { buffer: png, originalname: 'l.png', size: png.length }, { kind: 'LICENSE' }), code('LICENSE_FIELDS_TOGETHER'));
  await assert.rejects(onboarding.upload(asNurse, { buffer: Buffer.from('not an image'), originalname: 'x.png', size: 5 }, { kind: 'ID' }), code('FILE_TYPE_NOT_ALLOWED'));
  await onboarding.upload(asNurse, { buffer: png, originalname: 'IMG_123.png', size: png.length }, { kind: 'LICENSE', licenseRef: 'L-9', expiresAt: '2031-01-01' });
  await onboarding.upload(asNurse, { buffer: png, originalname: 'IMG_124.png', size: png.length }, { kind: 'PRACTICE_CERT', licenseRef: 'C-1', expiresAt: '2031-01-01' });
  const docs = (await pg.query('SELECT kind,title,original_name,storage_key FROM nurse_documents ORDER BY kind')).rows;
  assert.deepEqual(docs.map(d => d.original_name), ['سارة أحمد - رخصة.png', 'سارة أحمد - شهادة مزاولة المهنة.png']);
  assert.deepEqual(docs.map(d => d.title), ['رخصة', 'شهادة مزاولة المهنة']);
  assert.ok(docs[0].storage_key.startsWith('licenses/'));
  assert.ok(docs[1].storage_key.startsWith('practice-certificates/'));
  assert.equal((await pg.query('SELECT verified FROM nurses')).rows[0].verified, false);   // cannot self-approve
  await assert.rejects(onboarding.status({ user: { id: uid, role: 'PATIENT' } }), e => e.getStatus?.() === 403);
});
