// Pricing, promo codes, billing, cash collection and leaderboard on PGlite (PostGIS columns stripped).
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { PGlite } from '@electric-sql/pglite';

process.env.JWT_SECRET = 'test-secret-test-secret-test-secret-123';
const root = resolve(import.meta.dirname, '../../..');
const { PricingController } = await import('../dist/pricing/pricing.controller.js');
const { PromoService } = await import('../dist/pricing/promo.service.js');
const { AdminBusinessController } = await import('../dist/admin/admin-business.controller.js');
const { finalBill, ruleFromRow } = await import('../dist/pricing/pricing.js');

const pg = new PGlite();
const strip = s => s.replace(/CREATE EXTENSION[^;]*;/g, '').replace(/geography\(Point,4326\)/g, 'text').replace(/CREATE INDEX[^;]*GIST[^;]*;/g, '');
for (const f of ['001_core', '003_admin_reads_audit', '004_auth_otp_refresh', '005_password_accounts_push', '006_pricing_promos_rewards', '007_fees_tiers_dues_referrals', '008_marketing', '009_nurse_admin_documents_settings', '010_self_registration', '011_regions', '012_area_coordinates', '013_default_password', '014_applications_doc_kinds'])
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
const promos = new PromoService();
const pricing = new PricingController(db, promos);
const admin = new AdminBusinessController(db, { invalidate: async () => {} });
const code = c => e => e.getResponse?.().code === c;

const id = async (sql, p) => (await pg.query(sql, p)).rows[0].id;
const adminU = await id(`INSERT INTO users(phone_e164,role) VALUES('+1','ADMIN') RETURNING id`);
const patient = await id(`INSERT INTO users(phone_e164,role) VALUES('+2','PATIENT') RETURNING id`);
const nurseU = await id(`INSERT INTO users(phone_e164,role,display_name) VALUES('+3','NURSE','ممرضة نور') RETURNING id`);
const nurseId = await id(`INSERT INTO nurses(user_id,verified) VALUES($1,true) RETURNING id`, [nurseU]);
const benef = await id(`INSERT INTO beneficiaries(owner_user_id,display_name,consent_status) VALUES($1,'أمي','GRANTED') RETURNING id`, [patient]);
const A = { user: { id: adminU, role: 'ADMIN' } }, P = { user: { id: patient, role: 'PATIENT' } }, N = { user: { id: nurseU, role: 'NURSE' } };

let svc;
test('admin adds a service with a time-based price; it stays hidden until approved', async () => {
  const { id: sid } = await admin.createService(A, { code: 'DRESSING', titleAr: 'تغيير ضماد', price: 1200, includedMinutes: 30, blockMinutes: 15, blockPrice: 400, expectedMinutes: 40, roundingStep: 50 });
  svc = sid;
  await assert.rejects(pricing.quote(P, { serviceId: svc }), e => e.getStatus() === 404); // inactive -> invisible
  await admin.updateService(A, svc, { active: true, dispatchApproved: true });
  const q = await pricing.quote(P, { serviceId: svc });
  assert.equal(q.min, 1200); assert.equal(q.expected, 1600);
  await assert.rejects(admin.createService(A, { code: 'DRESSING', titleAr: 'x', price: 1 }), code('SERVICE_CODE_EXISTS'));
  // The change is queued for every app + audit trail.
  assert.ok((await pg.query(`SELECT 1 FROM outbox_events WHERE event_type='cache.invalidate'`)).rowCount >= 2);
});

test('price edit is applied to new quotes immediately; deactivating hides the service', async () => {
  await admin.updateService(A, svc, { price: 1500 });
  assert.equal((await pricing.quote(P, { serviceId: svc })).min, 1500);
  await admin.updateService(A, svc, { price: 1200 });
  const list = (await admin.services(A)).items;
  assert.equal(list.length, 1);
});

let welcome;
test('promo codes: create, validate, claim, usage rules', async () => {
  welcome = (await admin.createPromo(A, { code: 'WELCOME20', type: 'PERCENT', value: 20, maxDiscount: 500, perUserLimit: 1, firstOrderOnly: true })).id;
  await assert.rejects(admin.createPromo(A, { code: 'welcome20', type: 'FIXED', value: 5 }), code('PROMO_CODE_EXISTS')); // case-insensitive
  const q = await pricing.quote(P, { serviceId: svc, promoCode: 'welcome20' });
  assert.equal(q.promoCode, 'WELCOME20'); assert.equal(q.expected, 1300); // 1600 - min(20%=320, cap 500)=1280 -> step 50 => 1300
  await assert.rejects(pricing.quote(P, { serviceId: svc, promoCode: 'NOPE' }), code('PROMO_NOT_FOUND'));
  await admin.createPromo(A, { code: 'OLD', type: 'FIXED', value: 100, validTo: '2020-01-01T00:00:00Z' });
  await assert.rejects(pricing.quote(P, { serviceId: svc, promoCode: 'OLD' }), code('PROMO_EXPIRED'));
  // claim = "I installed the app and entered the company code": applies automatically without typing it again
  assert.equal((await pricing.claim(P, { code: 'WELCOME20' })).claimed, true);
  assert.equal((await pricing.quote(P, { serviceId: svc })).promoCode, 'WELCOME20');
  await admin.updatePromo(A, welcome, { active: false });
  assert.equal((await pricing.quote(P, { serviceId: svc })).promoCode, null); // disabled from the panel -> gone
  await assert.rejects(pricing.quote(P, { serviceId: svc, promoCode: 'WELCOME20' }), code('PROMO_INACTIVE'));
  await admin.updatePromo(A, welcome, { active: true });
});

// A visit: nurse stayed 47 min at the patient's home with the welcome code applied.
let req, visit;
test('bill is computed from time at the patient + promo snapshot, and shown to both sides', async () => {
  const rule = { basePrice: 1200, includedMinutes: 30, blockMinutes: 15, blockPrice: 400, expectedMinutes: 40, roundingStep: 50 };
  const promo = { code: 'WELCOME20', type: 'PERCENT', value: 20, maxDiscount: 500 };
  req = await id(`INSERT INTO care_requests(requester_user_id,beneficiary_id,service_id,location,location_source,address_text,status,price_amount,currency_code,commission_bps,pricing,promo_id,promo_snapshot)
    VALUES($1,$2,$3,'x','MANUAL_PIN','a','COMPLETED',1200,'SYP_NEW',2000,$4::jsonb,$5,$6::jsonb) RETURNING id`, [patient, benef, svc, JSON.stringify(rule), welcome, JSON.stringify(promo)]);
  const asg = await id(`INSERT INTO request_assignments(request_id,nurse_id,status) VALUES($1,$2,'RELEASED') RETURNING id`, [req, nurseId]);
  visit = await id(`INSERT INTO visits(assignment_id,arrived_at,started_at,completed_at,outcome) VALUES($1,now()-interval '47 minutes',now()-interval '46 minutes',now(),'COMPLETED') RETURNING id`, [asg]);
  // what dispatch.complete does:
  const b = finalBill(ruleFromRow(rule), 47 * 60, promo);
  assert.deepEqual(b, { minutes: 47, gross: 2000, discount: 400, due: 1600 });
  await pg.query(`UPDATE care_requests SET service_minutes=$2,gross_amount=$3,discount_amount=$4,amount_due=$5,payment_status='DUE',billed_at=now() WHERE id=$1`, [req, b.minutes, b.gross, b.discount, b.due]);
  const bp = await pricing.patientBill(P, req), bn = await pricing.nurseBill(N, req);
  assert.deepEqual([bp.due, bp.remaining, bp.paymentStatus, bp.promoCode], [1600, 1600, 'DUE', 'WELCOME20']);
  assert.deepEqual([bn.due, bn.minutes, bn.discount], [1600, 47, 400]);
});

test('short payment is flagged and keeps the bill open; the remainder completes it; change is reported', async () => {
  const a = await pricing.collect(N, req, { amount: 1000 });
  assert.deepEqual([a.status, a.remaining, a.change], ['PARTIAL', 600, 0]);
  assert.match(a.message, /ناقص/);
  assert.equal((await pricing.patientBill(P, req)).paymentStatus, 'PARTIAL');
  const b = await pricing.collect(N, req, { amount: 1000 }); // pays more than the remaining 600
  assert.deepEqual([b.status, b.applied, b.change], ['PAID', 600, 400]);
  assert.match(b.message, /فكة/);
  await assert.rejects(pricing.collect(N, req, { amount: 100 }), code('ALREADY_PAID'));
  assert.equal(Number((await pg.query(`SELECT sum(amount) s FROM cash_collections WHERE visit_id=$1`, [visit])).rows[0].s), 1600); // books match the bill
});

test('only the nurse of the visit can collect; invalid amounts rejected', async () => {
  const other = await id(`INSERT INTO users(phone_e164,role) VALUES('+4','NURSE') RETURNING id`);
  await pg.query(`INSERT INTO nurses(user_id,verified) VALUES($1,true)`, [other]);
  await assert.rejects(pricing.collect({ user: { id: other, role: 'NURSE' } }, req, { amount: 100 }), e => e.getStatus() === 403);
  await assert.rejects(pricing.patientBill({ user: { id: other, role: 'PATIENT' } }, req), e => e.getStatus() === 403 || e.getStatus() === 404);
});

test('promo usage is counted from real orders (per-user limit + first order only)', async () => {
  await admin.updatePromo(A, welcome, { active: true });
  await assert.rejects(pricing.quote(P, { serviceId: svc, promoCode: 'WELCOME20' }), code('PROMO_ALREADY_USED'));
  const row = (await admin.promos(A)).items.find(p => p.code === 'WELCOME20');
  assert.equal(row.used, 1); assert.equal(Number(row.discount_given), 400); assert.equal(row.claimed, 1);
});

test('leaderboard ranks reputation, work and company revenue; rewards are recorded and audited', async () => {
  await pg.query(`INSERT INTO visit_reviews(visit_id,reviewer_user_id,reviewer_role,stars) VALUES($1,$2,'PATIENT',5)`, [visit, patient]);
  const lb = await admin.leaderboard(A, 'month');
  assert.equal(lb.byReputation[0].name, 'ممرضة نور');
  assert.equal(lb.byWork[0].visits, 1);
  assert.equal(Number(lb.byCompanyRevenue[0].commission), 320); // 20% of 1600
  await assert.rejects(admin.leaderboard(A, 'year'));
  await admin.reward(A, { nurseId, kind: 'REPUTATION', amount: 5000, period: '2026-11', note: 'أفضل سمعة' });
  assert.equal((await admin.rewards(A)).items[0].amount, '5000.00');
  assert.equal((await pg.query(`SELECT count(*)::int n FROM audit_log WHERE action='reward.granted'`)).rows[0].n, 1);
});

test('non-admins cannot touch prices, promos or rewards', async () => {
  for (const f of [() => admin.services(P), () => admin.createPromo(N, { code: 'XXX', type: 'FIXED', value: 5 }), () => admin.reward(P, {})])
    await assert.rejects(f(), e => e.getStatus() === 403);
});

// ---- the real dispatch state machine: complete() must produce the bill ----
test('dispatch.complete bills from arrival->end using the request snapshot, and the nurse is then released', async () => {
  const { DispatchService } = await import('../dist/dispatch/dispatch.service.js');
  const dispatch = new DispatchService(db);
  const rule = { basePrice: 1200, includedMinutes: 30, blockMinutes: 15, blockPrice: 400, expectedMinutes: 40, roundingStep: 50 };
  const r2 = await id(`INSERT INTO care_requests(requester_user_id,beneficiary_id,service_id,location,location_source,address_text,status,price_amount,currency_code,commission_bps,pricing,promo_snapshot)
    VALUES($1,$2,$3,'x','MANUAL_PIN','a','EN_ROUTE',1200,'SYP_NEW',2000,$4::jsonb,$5::jsonb) RETURNING id`,
    [patient, benef, svc, JSON.stringify(rule), JSON.stringify({ code: 'X', type: 'FIXED', value: 200 })]);
  await pg.query(`UPDATE nurses SET work_status='EN_ROUTE',availability_intent='AVAILABLE' WHERE id=$1`, [nurseId]);
  const a2 = await id(`INSERT INTO request_assignments(request_id,nurse_id,status) VALUES($1,$2,'ACTIVE') RETURNING id`, [r2, nurseId]);
  await dispatch.transition(nurseU, a2, 'arrive');
  await pg.query(`UPDATE visits SET arrived_at=now()-interval '50 minutes' WHERE assignment_id=$1`, [a2]); // simulate 50 minutes at the patient
  await dispatch.transition(nurseU, a2, 'start');
  const done = await dispatch.transition(nurseU, a2, 'complete');
  assert.equal(done.status, 'COMPLETED');
  const row = (await pg.query(`SELECT service_minutes,gross_amount,discount_amount,amount_due,payment_status FROM care_requests WHERE id=$1`, [r2])).rows[0];
  assert.deepEqual([row.service_minutes, Number(row.gross_amount), Number(row.discount_amount), Number(row.amount_due), row.payment_status], [51, 2000, 200, 1800, 'DUE']); // 50 min + a few ms = 51 started minutes -> 2 extra blocks
  assert.equal((await pricing.patientBill(P, r2)).due, 1800);
  assert.equal((await pricing.nurseBill(N, r2)).remaining, 1800);
});
