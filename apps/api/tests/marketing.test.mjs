// Marketing features on PGlite (PostGIS stripped): switches, automatic discounts, packs, broadcasts, consent.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { PGlite } from '@electric-sql/pglite';

process.env.JWT_SECRET = 'test-secret-test-secret-test-secret-123';
const root = resolve(import.meta.dirname, '../../..');
const { MarketingController, sanitizeConfig } = await import('../dist/admin/marketing.controller.js');
const { AutoDiscountService } = await import('../dist/pricing/auto-discounts.service.js');
const { MeController } = await import('../dist/auth/me.controller.js');
const { PricingController } = await import('../dist/pricing/pricing.controller.js');
const { PromoService } = await import('../dist/pricing/promo.service.js');

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
const mkt = new MarketingController(db), autos = new AutoDiscountService(), me = new MeController(db);
const { FeesService } = await import('../dist/pricing/fees.service.js');
const pricing = new PricingController(db,new PromoService(db),new FeesService(),undefined,autos);
const code = c => e => e.getResponse?.().code === c;
const id = async (sql, p) => (await pg.query(sql, p)).rows[0].id;

const adminU = await id(`INSERT INTO users(phone_e164,role) VALUES('+1','ADMIN') RETURNING id`);
const A = { user: { id: adminU, role: 'ADMIN' } };
const patient = await id(`INSERT INTO users(phone_e164,role) VALUES('+2','PATIENT') RETURNING id`);
const P = { user: { id: patient, role: 'PATIENT' } };
const benef = await id(`INSERT INTO beneficiaries(owner_user_id,display_name,consent_status) VALUES($1,'م','GRANTED') RETURNING id`, [patient]);
const svc = await id(`INSERT INTO services(code,title_ar,active,dispatch_approved,price_amount,included_minutes,block_minutes,block_price,expected_minutes,rounding_step,commission_bps)
  VALUES('S','ضماد',true,true,1000,30,15,400,30,50,2000) RETURNING id`);
// 2026-11-23 is a Monday; 10:00Z = 13:00 Damascus
const at = iso => new Date(iso);

test('every marketing feature starts OFF; nothing applies until the admin switches it on', async () => {
  const { features } = await mkt.overview(A);
  assert.deepEqual(Object.fromEntries(features.map(f => [f.key, f.enabled])), { alarm: true, badge: false, broadcasts: false, loyalty: false, offpeak: false, packs: false, winback: false }); // only the operational alarm is on
  assert.equal(await autos.pick(db, patient, at('2026-11-23T10:00:00Z')), null);
});

test('config is validated: bad values are rejected and a broken feature cannot be switched on', async () => {
  await assert.rejects(mkt.setFeature(A, 'offpeak', { config: { percent: 15, days: [9], start: '13:00', end: '16:00' } }), code('INVALID_DAYS'));
  await assert.rejects(mkt.setFeature(A, 'offpeak', { config: { percent: 500, days: [1], start: '13:00', end: '16:00' } }), code('INVALID_PERCENT'));
  await assert.rejects(mkt.setFeature(A, 'loyalty', { config: { everyN: 1, percent: 10 } }), code('INVALID_EVERY_N'));
  await assert.rejects(mkt.setFeature(A, 'nope', { enabled: true }), e => e.getStatus() === 404);
  await assert.rejects(mkt.setFeature({ user: { id: adminU, role: 'PATIENT' } }, 'badge', { enabled: true }), e => e.getStatus() === 403);
  assert.deepEqual(sanitizeConfig('badge', { minReputation: '4.5', minReviews: 10 }), { minReputation: 4.5, minReviews: 10 });
});

test('off-peak discount applies automatically inside the window (Damascus time) and only when enabled', async () => {
  await mkt.setFeature(A, 'offpeak', { enabled: true, config: { percent: 15, days: [1], start: '13:00', end: '16:00', maxDiscount: 1000 } });
  const hit = await autos.pick(db, patient, at('2026-11-23T10:00:00Z'));     // Monday 13:00 local
  assert.deepEqual([hit.kind, hit.value], ['OFFPEAK', 15]);
  assert.equal(await autos.pick(db, patient, at('2026-11-23T14:00:00Z')), null); // 17:00 local: outside
  assert.equal(await autos.pick(db, patient, at('2026-11-24T10:00:00Z')), null); // Tuesday: not in the days list
  await mkt.setFeature(A, 'offpeak', { enabled: false });
  assert.equal(await autos.pick(db, patient, at('2026-11-23T10:00:00Z')), null); // switched off again
});

test('loyalty: every Nth paid order gets the discount', async () => {
  await mkt.setFeature(A, 'loyalty', { enabled: true, config: { everyN: 3, percent: 20, maxDiscount: 1500 } });
  const order = async (paid) => id(`INSERT INTO care_requests(requester_user_id,beneficiary_id,service_id,location,location_source,address_text,status,price_amount,currency_code,commission_bps,payment_status)
    VALUES($1,$2,$3,'x','MANUAL_PIN','a','COMPLETED',1000,'SYP_NEW',2000,$4) RETURNING id`, [patient, benef, svc, paid ? 'PAID' : 'DUE']);
  assert.equal(await autos.pick(db, patient), null);            // 1st order
  await order(true);
  assert.equal(await autos.pick(db, patient), null);            // 2nd order
  await order(true);
  const third = await autos.pick(db, patient);                  // 3rd order
  assert.deepEqual([third.kind, third.value], ['LOYALTY', 20]);
  await order(false);                                           // unpaid orders do not count
  assert.equal((await autos.pick(db, patient)).kind, 'LOYALTY');
  await order(true);
  assert.equal(await autos.pick(db, patient), null);            // 4th order: no discount
});

test('visit packs: granted by the admin, limited by visits and expiry, the biggest discount wins', async () => {
  await mkt.setFeature(A, 'packs', { enabled: true });
  await assert.rejects(mkt.grant(A, { phone: '+999', name: 'x', visits: 2, percent: 10, validDays: 10 }), e => e.getStatus() === 404);
  const g = await mkt.grant(A, { phone: '+2', name: 'باقة 4 زيارات', visits: 2, percent: 30, validDays: 30 });
  const first = await autos.pick(db, patient);
  assert.deepEqual([first.kind, first.value, first.packGrantId], ['PACK', 30, g.id]); // 30% beats loyalty 20% (the 4th order has none anyway)
  // consume both visits (non-cancelled orders carrying the pack snapshot)
  for (let i = 0; i < 2; i++) await pg.query(`INSERT INTO care_requests(requester_user_id,beneficiary_id,service_id,location,location_source,address_text,status,price_amount,currency_code,commission_bps,promo_snapshot)
    VALUES($1,$2,$3,'x','MANUAL_PIN','a',$4,1000,'SYP_NEW',2000,$5::jsonb)`, [patient, benef, svc, i === 0 ? 'COMPLETED' : 'CANCELLED', JSON.stringify({ packGrantId: g.id, auto: true })]);
  assert.equal((await autos.pick(db, patient)).kind, 'PACK'); // cancelled visit is not consumed: 1 of 2 left
  await pg.query(`UPDATE care_requests SET status='COMPLETED' WHERE promo_snapshot->>'packGrantId'=$1`, [g.id]);
  assert.notEqual((await autos.pick(db, patient))?.kind, 'PACK'); // used up
  assert.equal((await mkt.packs(A)).items[0].used, 2);
  assert.ok((await pg.query(`SELECT 1 FROM outbox_events WHERE event_type='pack.granted'`)).rowCount);
});

test('the quote shows the automatic discount to the patient', async () => {
  await mkt.setFeature(A, 'offpeak', { enabled: true, config: { percent: 50, days: [0, 1, 2, 3, 4, 5, 6], start: '00:00', end: '23:59' } });
  const q = await pricing.quote(P, { serviceId: svc });
  assert.equal(q.autoDiscount, 'OFFPEAK');
  assert.ok(q.expected < 1000 && /الأوقات الهادئة/.test(q.promoCode));
  await mkt.setFeature(A, 'offpeak', { enabled: false });
});

test('broadcasts: need the switch, count only reachable opted-in devices, and are queued for the worker', async () => {
  await assert.rejects(mkt.broadcast(A, { audience: 'ALL_PATIENTS', title: 'عرض', body: 'خصم اليوم' }), code('BROADCASTS_DISABLED'));
  await mkt.setFeature(A, 'broadcasts', { enabled: true });
  await pg.query(`INSERT INTO device_tokens(user_id,token,platform) VALUES($1,'tok-patient-aaaaaaaaaaaaaaaa','android')`, [patient]);
  assert.deepEqual(await mkt.preview(A, 'ALL_PATIENTS'), { users: 0, devices: 0 });            // patient has not opted in
  await assert.rejects(mkt.broadcast(A, { audience: 'ALL_PATIENTS', title: 'عرض', body: 'خصم اليوم' }), code('NO_REACHABLE_DEVICES'));
  await me.set(P, { optIn: true });
  assert.deepEqual(await me.get(P), { optIn: true });
  assert.deepEqual(await mkt.preview(A, 'ALL_PATIENTS'), { users: 1, devices: 1 });
  const nurseU = await id(`INSERT INTO users(phone_e164,role) VALUES('+3','NURSE') RETURNING id`);
  await pg.query(`INSERT INTO nurses(user_id,verified,work_status) VALUES($1,true,'AVAILABLE')`, [nurseU]);
  await pg.query(`INSERT INTO device_tokens(user_id,token,platform) VALUES($1,'tok-nurse-bbbbbbbbbbbbbbbbbb','android')`, [nurseU]);
  assert.equal((await mkt.preview(A, 'ALL_NURSES')).devices, 1);          // operational message: no consent needed
  assert.equal((await mkt.preview(A, 'AVAILABLE_NURSES')).devices, 1);
  const b = await mkt.broadcast(A, { audience: 'ALL_NURSES', title: 'تنبيه', body: 'ازدحام في المزة', promoCode: 'x1' });
  assert.equal(b.queuedFor, 1);
  const row = (await mkt.history(A)).items[0];
  assert.deepEqual([row.status, row.total, row.promo_code], ['QUEUED', 1, 'X1']);
  await assert.rejects(mkt.preview(A, 'EVERYONE'), code('INVALID_AUDIENCE'));
  assert.equal((await pg.query(`SELECT count(*)::int n FROM audit_log WHERE action='broadcast.queued'`)).rows[0].n, 1);
});

test('overview reports consent and activity counters', async () => {
  const o = await mkt.overview(A);
  assert.equal(o.stats.opted_in, 1); assert.equal(o.stats.broadcasts_30d, 1);
});
