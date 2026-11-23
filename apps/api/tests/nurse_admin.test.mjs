// Nurse administration, encrypted documents and system settings, on PGlite (PostGIS stripped).
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, readdirSync, readFileSync as rf } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { PGlite } from '@electric-sql/pglite';

process.env.JWT_SECRET = 'test-secret-test-secret-test-secret-123';
process.env.NODE_ENV = 'development';
process.env.UPLOADS_DIR = mkdtempSync(join(tmpdir(), 'tamreedy-up-'));
const root = resolve(import.meta.dirname, '../../..');
const { AdminNursesController } = await import('../dist/admin/admin-nurses.controller.js');
const { AdminSettingsController } = await import('../dist/admin/admin-settings.controller.js');
const { DocStore } = await import('../dist/admin/doc-store.js');
const { RegionsPublicController, AdminRegionsController } = await import('../dist/admin/regions.controller.js');
const { hashPassword, AuthService } = await import('../dist/auth/auth.service.js');

const pg = new PGlite();
const strip = s => s.replace(/CREATE EXTENSION[^;]*;/g, '').replace(/geography\(Point,4326\)/g, 'text').replace(/CREATE INDEX[^;]*GIST[^;]*;/g, '');
for (const f of ['001_core', '003_admin_reads_audit', '004_auth_otp_refresh', '005_password_accounts_push', '006_pricing_promos_rewards', '009_nurse_admin_documents_settings', '010_self_registration', '011_regions', '012_area_coordinates', '013_default_password', '014_applications_doc_kinds', '019_device_sessions_and_persistent_auth'])
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
const nurses = new AdminNursesController(db, docs);
const settings = new AdminSettingsController(db);
const regions = new AdminRegionsController(db);
const publicRegions = new RegionsPublicController(db);
const auth = new AuthService(db, { send: async () => {} });
const code = c => e => e.getResponse?.().code === c;
const adminId = (await pg.query(`INSERT INTO users(phone_e164,role,password_hash) VALUES('+963900000000','ADMIN',$1) RETURNING id`, [hashPassword('admin-password-123')])).rows[0].id;
const asAdmin = { user: { id: adminId, role: 'ADMIN' } };
const asReviewer = { user: { id: adminId, role: 'CLINICAL_REVIEWER' } };
const asPatient = { user: { id: adminId, role: 'PATIENT' } };
const png = Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), Buffer.from('fake-image-body-for-test')]);
let nurseId, docId;
const dam = {};
dam.id = (await pg.query(`SELECT id FROM governorates WHERE name_ar='دمشق'`)).rows[0].id;
dam.mazzeh = (await pg.query(`SELECT id FROM areas WHERE name_ar='المزة'`)).rows[0].id;

test('admin adds a nurse: gets an auto number and a one-time password that works', async () => {
  const a = await nurses.create(asAdmin, { phone: '+963911000001', displayName: 'ممرضة أولى', governorateId: dam.id, areaId: dam.mazzeh, nationalId: '01234567890' });
  const b = await nurses.create(asAdmin, { phone: '+963911000002', displayName: 'ممرض ثانٍ', nurseNo: 5000 });
  nurseId = a.id;
  assert.equal(a.nurseNo, 1001); assert.equal(b.nurseNo, 5000);
  assert.equal((await auth.login('+963911000001', a.temporaryPassword)).role, 'NURSE');
  await assert.rejects(nurses.create(asAdmin, { phone: '+963911000001', displayName: 'x' }), code('PHONE_ALREADY_REGISTERED'));
  await assert.rejects(nurses.create(asAdmin, { phone: '+963911000003', displayName: 'x', nurseNo: 5000 }), code('NURSE_NO_TAKEN'));
});

test('national id is encrypted in the database and only its tail is shown', async () => {
  const raw = (await pg.query('SELECT national_id_enc FROM nurses WHERE id=$1', [nurseId])).rows[0].national_id_enc;
  assert.ok(!raw.includes('0123456'));
  const p = await nurses.profile(asAdmin, nurseId);
  assert.equal(p.nationalIdMasked, '••••890');
  assert.equal(p.national_id_enc, undefined);
});

test('edit changes number, phone and notes; list can search by number', async () => {
  await nurses.update(asAdmin, nurseId, { displayName: 'ممرضة معدّلة', nurseNo: 2001, notes: 'ملاحظة' });
  const l = await nurses.list(asAdmin, '2001');
  assert.equal(l.items.length, 1); assert.equal(l.items[0].display_name, 'ممرضة معدّلة');
});

test('skills can be assigned', async () => {
  const s = (await pg.query(`INSERT INTO services(code,title_ar,price_amount) VALUES('X','حقن',100) RETURNING id`)).rows[0].id;
  assert.equal((await nurses.skills(asAdmin, nurseId, { serviceIds: [s] })).skills, 1);
  assert.equal((await nurses.profile(asAdmin, nurseId)).skills.find(x => x.id === s).approved, true);
});

test('document upload: stored encrypted, real type checked, licence enters approval queue', async () => {
  await assert.rejects(nurses.upload(asAdmin, nurseId, { buffer: Buffer.from('<script>alert(1)</script>'), originalname: 'evil.png', size: 10 }, { kind: 'ID' }), code('FILE_TYPE_NOT_ALLOWED'));
  await assert.rejects(nurses.upload(asAdmin, nurseId, { buffer: png, originalname: 'a.png', size: png.length }, { kind: 'LICENSE', licenseRef: 'L-1' }), code('LICENSE_FIELDS_TOGETHER'));
  const up = await nurses.upload(asAdmin, nurseId, { buffer: png, originalname: 'licence.png', size: png.length }, { kind: 'LICENSE', licenseRef: 'L-1', expiresAt: '2030-01-01' });
  docId = up.id;
  assert.equal(up.queuedForApproval, true);
  const cred = (await pg.query('SELECT approved,review_status,document_id FROM nurse_credentials WHERE nurse_id=$1', [nurseId])).rows[0];
  assert.deepEqual([cred.approved, cred.review_status, cred.document_id], [false, 'PENDING', docId]);
  const key = (await pg.query('SELECT storage_key FROM nurse_documents WHERE id=$1', [docId])).rows[0].storage_key;
  const onDisk = rf(join(process.env.UPLOADS_DIR, key));
  assert.ok(!onDisk.includes(Buffer.from('fake-image-body')));      // ciphertext, not the original
  assert.ok(png.equals(docs.decryptBuffer(onDisk)));                  // decrypts back exactly
  const tampered = Buffer.from(onDisk); tampered[tampered.length - 1] ^= 1;
  assert.throws(() => docs.decryptBuffer(tampered));                  // GCM detects tampering
});

test('download is audited, restricted to staff, and returns the original bytes', async () => {
  const headers = {};
  const f = await nurses.download(asReviewer, docId, { set: h => Object.assign(headers, h) });
  assert.ok(f);
  assert.equal(headers['Content-Type'], 'image/png');
  assert.equal(headers['Cache-Control'], 'no-store');
  assert.equal((await pg.query(`SELECT count(*)::int n FROM audit_log WHERE action='nurse.document_viewed'`)).rows[0].n, 1);
  await assert.rejects(nurses.download(asPatient, docId, { set() {} }), e => e.getStatus?.() === 403);
});

test('a document behind an approved licence cannot be deleted; others can', async () => {
  await pg.query('UPDATE nurse_credentials SET approved=true WHERE nurse_id=$1', [nurseId]);
  await assert.rejects(nurses.removeDoc(asAdmin, docId), code('DOCUMENT_BACKS_APPROVED_LICENSE'));
  const o = await nurses.upload(asAdmin, nurseId, { buffer: png, originalname: 'id.png', size: png.length }, { kind: 'ID' });
  await nurses.removeDoc(asAdmin, o.id);
  assert.equal((await nurses.profile(asAdmin, nurseId)).documents.length, 1);
});

test('suspend blocks login; delete keeps records, frees the phone and hides the nurse', async () => {
  await nurses.status(asAdmin, nurseId, { status: 'SUSPENDED' });
  await assert.rejects(auth.login('+963911000001', 'whatever-password'), code('LOGIN_INVALID'));
  await nurses.remove(asAdmin, nurseId);
  assert.equal((await nurses.list(asAdmin)).items.some(x => x.id === nurseId), false);
  assert.equal((await pg.query('SELECT count(*)::int n FROM nurses WHERE id=$1', [nurseId])).rows[0].n, 1); // record kept
  await nurses.create(asAdmin, { phone: '+963911000001', displayName: 'نفس الرقم' }); // phone reusable
  assert.ok((await pg.query(`SELECT count(*)::int n FROM audit_log WHERE action='nurse.deleted'`)).rows[0].n === 1);
});

test('writes are admin-only; reviewers may read and upload', async () => {
  await assert.rejects(nurses.create(asReviewer, { phone: '+963911000009', displayName: 'x' }), e => e.getStatus?.() === 403);
  await assert.rejects(nurses.remove(asReviewer, nurseId), e => e.getStatus?.() === 403);
  assert.ok((await nurses.list(asReviewer)).items);
});

test('settings validate their shape and are audited', async () => {
  const all = await settings.all(asAdmin);
  assert.equal(all.settings.dispatch.waves.length, 3);
  await settings.save(asAdmin, 'dispatch', { waves: [{ radiusM: 2000, seconds: 10, limit: 5 }, { radiusM: 8000, seconds: 20, limit: 10 }] });
  assert.equal((await settings.all(asAdmin)).settings.dispatch.waves.length, 2);
  const waves = (await settings.all(asAdmin)).settings.dispatch.waves;
  await settings.save(asAdmin, 'dispatch', { waves, openEnabled: true, offerDurationSeconds: 45 });
  const policy = (await settings.all(asAdmin)).settings.dispatch;
  assert.equal(policy.openEnabled, true);
  assert.equal(policy.offerDurationSeconds, 45);
  assert.equal(policy.radiusMeters, 10000);
  await assert.rejects(settings.save(asAdmin, 'dispatch', { waves, offerDurationSeconds: 0 }), code('BAD_OFFER_DURATION'));
  await assert.rejects(settings.save(asAdmin, 'dispatch', { waves: [{ radiusM: 5000, seconds: 10, limit: 5 }, { radiusM: 3000, seconds: 10, limit: 5 }] }), code('WAVES_MUST_GROW'));
  await assert.rejects(settings.save(asAdmin, 'security', { idleMinutes: 1, passwordMinLength: 12 }), code('BAD_IDLE'));
  await assert.rejects(settings.save(asAdmin, 'nonsense', {}), e => e.getStatus?.() === 404);
  await settings.save(asAdmin, 'orders', { accepting: false, pausedMessage: 'صيانة', extra: 'dropped' });
  assert.deepEqual((await settings.all(asAdmin)).settings.orders, { accepting: false, pausedMessage: 'صيانة' });
  assert.equal((await settings.audit(asAdmin)).items.filter(x => x.action === 'settings.changed').length, 3);
});

test('staff accounts: cannot delete self or the last admin; role change revokes sessions', async () => {
  await assert.rejects(settings.deleteStaff(asAdmin, adminId), code('CANNOT_DELETE_SELF'));
  const rid = (await pg.query(`INSERT INTO users(phone_e164,role,password_hash) VALUES('+963900000001','CLINICAL_REVIEWER','x') RETURNING id`)).rows[0].id;
  await settings.updateStaff(asAdmin, rid, { displayName: 'مراجع', role: 'ADMIN' });
  await settings.deleteStaff(asAdmin, rid);
  assert.equal((await settings.staff(asAdmin)).items.length, 1);
});

test('regions: seeded with Damascus and Rif Dimashq; admin can add, rename and deactivate; list filters by region', async () => {
  const pub = await publicRegions.list();
  assert.deepEqual(pub.governorates.map(g => g.name), ['دمشق', 'ريف دمشق']);
  assert.ok(pub.governorates[0].areas.length >= 15);
  assert.ok(pub.governorates.every(g => g.areas.every(a => typeof a.lat === 'number' && a.lat > 33 && a.lng > 36)));
  const g = await regions.addGov(asAdmin, { nameAr: 'حمص' });
  await regions.addArea(asAdmin, { nameAr: 'الوعر', governorateId: g.id });
  await assert.rejects(regions.addGov(asAdmin, { nameAr: 'حمص' }), code('REGION_EXISTS'));
  assert.equal((await publicRegions.list()).governorates.length, 3);
  await regions.editGov(asAdmin, g.id, { active: false });
  assert.equal((await publicRegions.list()).governorates.length, 2);          // hidden from sign-up, kept in the database
  const n = await nurses.create(asAdmin, { phone: '+963911000077', displayName: 'ممرض المزة', governorateId: dam.id, areaId: dam.mazzeh });
  assert.equal((await nurses.list(asAdmin, undefined, undefined, dam.id, dam.mazzeh)).items.some(x => x.id === n.id && x.area === 'المزة' && x.governorate === 'دمشق'), true);
  await assert.rejects(nurses.create(asAdmin, { phone: '+963911000078', displayName: 'x', governorateId: g.id }), code('REGION_INVALID')); // inactive governorate
  await assert.rejects(nurses.create(asAdmin, { phone: '+963911000079', displayName: 'x', areaId: dam.mazzeh }), code('REGION_INVALID'));      // area without governorate
  await assert.rejects(regions.addGov(asReviewer, { nameAr: 'x' }), e => e.getStatus?.() === 403);
});
