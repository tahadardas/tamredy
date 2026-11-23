// Nurse join applications: public submit (no account), staff review, interview, approve (creates the account) or reject.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, readdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { PGlite } from '@electric-sql/pglite';

process.env.JWT_SECRET = 'test-secret-test-secret-test-secret-123';
process.env.NODE_ENV = 'development';
const uploads = mkdtempSync(join(tmpdir(), 'tamreedy-app-'));
process.env.UPLOADS_DIR = uploads;
delete process.env.AUTH_MODE;
const root = resolve(import.meta.dirname, '../../..');
const { ApplicationsPublicController, AdminApplicationsController } = await import('../dist/auth/applications.controller.js');
const { AuthService, hashPassword } = await import('../dist/auth/auth.service.js');
const { DocStore } = await import('../dist/admin/doc-store.js');

const pg = new PGlite();
const strip = s => s.replace(/CREATE EXTENSION[^;]*;/g, '').replace(/geography\(Point,4326\)/g, 'text').replace(/CREATE INDEX[^;]*GIST[^;]*;/g, '');
for (const f of ['001_core', '003_admin_reads_audit', '004_auth_otp_refresh', '005_password_accounts_push', '006_pricing_promos_rewards', '009_nurse_admin_documents_settings', '010_self_registration', '011_regions', '013_default_password', '014_applications_doc_kinds', '019_device_sessions_and_persistent_auth'])
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
const docs = new DocStore();
const auth = new AuthService(db, { send: async () => {} });
const pub = new ApplicationsPublicController(db, docs);
const admin = new AdminApplicationsController(db, docs);
const code = c => e => e.getResponse?.().code === c;
const adminId = (await pg.query(`INSERT INTO users(phone_e164,role,password_hash) VALUES('+963900000000','ADMIN',$1) RETURNING id`, [hashPassword('admin-password-123')])).rows[0].id;
const asAdmin = { user: { id: adminId, role: 'ADMIN' } };
const png = Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), Buffer.from('z'.repeat(40))]);
const pdf = Buffer.concat([Buffer.from('%PDF-1.4\n'), Buffer.from('p'.repeat(40))]);
const up = (buffer, name = 'x') => ({ buffer, originalname: name, size: buffer.length });
const gov = (await pg.query(`SELECT id FROM governorates WHERE name_ar='دمشق'`)).rows[0].id;
const area = (await pg.query(`SELECT id FROM areas WHERE governorate_id=$1 AND name_ar='المزة'`, [gov])).rows[0].id;
const body = (over = {}) => ({ phone: '+963922000001', displayName: 'ليلى خالد', governorateId: gov, areaId: area, docKind: 'LICENSE', licenseRef: 'LIC-77', expiresAt: '2032-06-01', acceptTerms: 'true', specialty: 'عناية منزلية', nationalId: '01010101010', ...over });
const files = (over = {}) => ({ idPhoto: [up(png, 'IMG_001.png')], document: [up(pdf, 'scan.pdf')], ...over });
let appId;

test('an application stores two encrypted files by category, creates NO account and no nurse', async () => {
  const r = await pub.apply({ ip: '9.9.9.9' }, files(), body());
  appId = r.id;
  assert.equal(r.status, 'PENDING');
  assert.equal((await pg.query(`SELECT count(*)::int n FROM users WHERE phone_e164='+963922000001'`)).rows[0].n, 0);
  assert.equal((await pg.query('SELECT count(*)::int n FROM nurses')).rows[0].n, 0);
  await assert.rejects(auth.login('+963922000001', '123456'), e => e.getResponse?.().code === 'LOGIN_INVALID');
  const names = (await pg.query('SELECT kind,original_name,storage_key FROM application_documents ORDER BY kind')).rows;
  assert.deepEqual(names.map(n => n.original_name), ['ليلى خالد - هوية.png', 'ليلى خالد - رخصة.pdf']);
  assert.ok(names.find(n => n.kind === 'ID').storage_key.startsWith('ids/'));
  assert.ok(names.find(n => n.kind === 'LICENSE').storage_key.startsWith('licenses/'));
  assert.deepEqual(readdirSync(uploads).sort(), ['ids', 'licenses']);                 // one folder per category
  const raw = (await pg.query('SELECT national_id_enc FROM nurse_applications')).rows[0].national_id_enc;
  assert.ok(!raw.includes('0101010'));                                                // national id encrypted
});

test('a certificate goes to its own folder; duplicates, bad files, missing consent and expired documents are rejected', async () => {
  await pub.apply({ ip: '9.9.9.8' }, files(), body({ phone: '+963922000002', docKind: 'PRACTICE_CERT', displayName: 'نور علي' }));
  assert.ok(readdirSync(uploads).includes('practice-certificates'));
  await assert.rejects(pub.apply({ ip: '9.9.9.7' }, files(), body()), code('APPLICATION_ALREADY_OPEN'));
  await assert.rejects(pub.apply({ ip: '9.9.9.7' }, { idPhoto: [up(png)] }, body({ phone: '+963922000003' })), code('FILE_REQUIRED'));
  await assert.rejects(pub.apply({ ip: '9.9.9.7' }, files({ idPhoto: [up(Buffer.from('<html>'))] }), body({ phone: '+963922000003' })), code('FILE_TYPE_NOT_ALLOWED'));
  await assert.rejects(pub.apply({ ip: '9.9.9.7' }, files(), body({ phone: '+963922000003', expiresAt: '2020-01-01' })), code('LICENSE_EXPIRED'));
  await assert.rejects(pub.apply({ ip: '9.9.9.7' }, files(), body({ phone: '+963922000003', areaId: (await pg.query(`SELECT id FROM areas WHERE name_ar='دوما'`)).rows[0].id })), code('REGION_INVALID'));
  assert.equal((await pg.query(`SELECT count(*)::int n FROM nurse_applications WHERE phone_e164='+963922000003'`)).rows[0].n, 0);
});

test('staff see the application with names and region, can open files (audited), and schedule the interview', async () => {
  const list = (await admin.list(asAdmin, 'PENDING')).items;
  const a = list.find(x => x.id === appId);
  assert.deepEqual([a.display_name, a.governorate, a.area, a.docKindLabel], ['ليلى خالد', 'دمشق', 'المزة', 'رخصة']);
  const headers = {};
  await admin.download(asAdmin, a.documents[0].id, { set: h => Object.assign(headers, h) });
  assert.equal(headers['Cache-Control'], 'no-store');
  assert.equal((await pg.query(`SELECT count(*)::int n FROM audit_log WHERE action='application.document_viewed'`)).rows[0].n, 1);
  await admin.interview(asAdmin, appId, { interviewAt: '2030-01-01T10:00:00Z', note: 'مقابلة هاتفية' });
  assert.equal((await pg.query('SELECT status FROM nurse_applications WHERE id=$1', [appId])).rows[0].status, 'INTERVIEW');
  await assert.rejects(admin.interview({ user: { id: adminId, role: 'CLINICAL_REVIEWER' } }, appId, { interviewAt: '2030-01-01T10:00:00Z' }), e => e.getStatus?.() === 403);
});

test('approval creates the account with the initial password, a verified nurse, her documents and an approved licence', async () => {
  const r = await admin.approve(asAdmin, appId);
  assert.deepEqual([r.account.phone, r.account.defaultPassword], ['+963922000001', '123456']);
  const t = await auth.login('+963922000001', '123456');
  assert.deepEqual([t.role, t.mustChangePassword], ['NURSE', true]);
  const n = (await pg.query('SELECT verified,governorate_id,area_id,specialty FROM nurses WHERE id=$1', [r.nurseId])).rows[0];
  assert.deepEqual([n.verified, n.governorate_id, n.area_id, n.specialty], [true, gov, area, 'عناية منزلية']);
  const cred = (await pg.query('SELECT approved,review_status,doc_kind,license_ref FROM nurse_credentials WHERE nurse_id=$1', [r.nurseId])).rows[0];
  assert.deepEqual([cred.approved, cred.review_status, cred.doc_kind, cred.license_ref], [true, 'APPROVED', 'LICENSE', 'LIC-77']);
  assert.deepEqual((await pg.query('SELECT original_name FROM nurse_documents WHERE nurse_id=$1 ORDER BY kind', [r.nurseId])).rows.map(x => x.original_name), ['ليلى خالد - هوية.png', 'ليلى خالد - رخصة.pdf']);
  await assert.rejects(admin.approve(asAdmin, appId), code('APPLICATION_ALREADY_DECIDED'));
  await assert.rejects(admin.reject(asAdmin, appId, { reason: 'x1' }), code('APPLICATION_ALREADY_DECIDED'));
});

test('rejection records the reason, creates no account, and frees the phone for a new application', async () => {
  const id2 = (await pg.query(`SELECT id FROM nurse_applications WHERE phone_e164='+963922000002'`)).rows[0].id;
  await admin.reject(asAdmin, id2, { reason: 'الوثيقة غير واضحة' });
  assert.equal((await pg.query(`SELECT count(*)::int n FROM users WHERE phone_e164='+963922000002'`)).rows[0].n, 0);
  assert.equal((await pub.apply({ ip: '9.9.9.6' }, files(), body({ phone: '+963922000002', displayName: 'نور علي' }))).status, 'PENDING');
});

test('registration can be closed, and each IP is throttled', async () => {
  await pg.query(`UPDATE app_settings SET value='{"patients":true,"nurses":false}' WHERE key='registration'`);
  await assert.rejects(pub.apply({ ip: '8.8.8.8' }, files(), body({ phone: '+963922000050' })), code('REGISTRATION_CLOSED'));
  await pg.query(`UPDATE app_settings SET value='{"patients":true,"nurses":true}' WHERE key='registration'`);
  for (let i = 0; i < 6; i++) await pub.apply({ ip: '7.7.7.7' }, files(), body({ phone: `+96392200010${i}`, displayName: 'م' + i }));
  await assert.rejects(pub.apply({ ip: '7.7.7.7' }, files(), body({ phone: '+963922000199' })), code('TOO_MANY_REGISTRATIONS'));
});
