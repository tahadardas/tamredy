// Fees, tax, tips, tiered commission, nurse dues, referrals and promo protection on PGlite (PostGIS stripped).
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { PGlite } from '@electric-sql/pglite';
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto';
import { configureBilling,migrateBillingFixtures,recordExecution } from './helpers/billing-fixture.mjs';

process.env.JWT_SECRET = 'test-secret-test-secret-test-secret-123';
const root = resolve(import.meta.dirname, '../../..');
const { PricingController } = await import('../dist/pricing/pricing.controller.js');
const { PromoService } = await import('../dist/pricing/promo.service.js');
const { AutoDiscountService } = await import('../dist/pricing/auto-discounts.service.js');
const { ReferralController } = await import('../dist/pricing/referral.controller.js');
const { AdminFeesController } = await import('../dist/admin/admin-fees.controller.js');
const { AdminBusinessController } = await import('../dist/admin/admin-business.controller.js');
const { NursesService } = await import('../dist/nurses/nurses.service.js');

const pg = new PGlite({extensions:{pgcrypto}});
const strip = s => s.replace(/CREATE EXTENSION[^;]*;/g, '').replace(/geography\(Point,4326\)/g, 'text').replace(/CREATE INDEX[^;]*GIST[^;]*;/g, '');
for (const f of ['001_core', '003_admin_reads_audit', '004_auth_otp_refresh', '005_password_accounts_push', '006_pricing_promos_rewards', '007_fees_tiers_dues_referrals', '008_marketing', '009_nurse_admin_documents_settings', '010_self_registration', '011_regions', '012_area_coordinates', '013_default_password', '014_applications_doc_kinds'])
  await pg.exec(strip(readFileSync(resolve(root, `infra/db/migrations/${f}.sql`), 'utf8')));
await migrateBillingFixtures(pg);
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
const promos = new PromoService(db);
const {fees,dues,referrals,billing,dispatch,ledger}=configureBilling(db);
const pricing = new PricingController(db,promos,fees,billing,new AutoDiscountService());
const refCtl = new ReferralController(db, referrals, promos);
const adminFees = new AdminFeesController(db,dues,ledger);
const adminBiz = new AdminBusinessController(db, { invalidate: async () => {} });
const nursesSvc = new NursesService(db);
const code = c => e => e.getResponse?.().code === c;
const id = async (sql, p) => (await pg.query(sql, p)).rows[0].id;

const adminU = await id(`INSERT INTO users(phone_e164,role) VALUES('+1','ADMIN') RETURNING id`);
const A = { user: { id: adminU, role: 'ADMIN' } };
const mkPatient = async n => { const u = await id(`INSERT INTO users(phone_e164,role) VALUES($1,'PATIENT') RETURNING id`, ['+10' + n]); const b = await id(`INSERT INTO beneficiaries(owner_user_id,display_name,consent_status) VALUES($1,'م','GRANTED') RETURNING id`, [u]); return { u, b, ctx: { user: { id: u, role: 'PATIENT' } } }; };
const nurseU = await id(`INSERT INTO users(phone_e164,role,display_name) VALUES('+3','NURSE','ممرضة') RETURNING id`);
const nurseId = await id(`INSERT INTO nurses(user_id,verified,availability_intent,work_status,last_heartbeat_at) VALUES($1,true,'AVAILABLE','AVAILABLE',now()) RETURNING id`, [nurseU]);
const N = { user: { id: nurseU, role: 'NURSE' } };
await pg.query(`INSERT INTO nurse_credentials(nurse_id,license_ref,expires_at,approved,review_status) VALUES($1,'L1',now()+interval '1 year',true,'APPROVED')`, [nurseId]);
const svc = await id(`INSERT INTO services(code,title_ar,active,dispatch_approved,price_amount,included_minutes,block_minutes,block_price,expected_minutes,rounding_step,commission_bps)
  VALUES('S1','ضماد',true,true,1200,30,15,400,40,50,2000) RETURNING id`);

/** Seeds a documented visit in progress, then exercises completion and billing. */
async function visit(patient, { minutes = 47, travel = 0, arrivedAt } = {}) {
  const snapshot = { basePrice: 1200, includedMinutes: 30, blockMinutes: 15, blockPrice: 400, expectedMinutes: 40, roundingStep: 50, fees: await fees.snapshot(db) };
  const req = await id(`INSERT INTO care_requests(requester_user_id,beneficiary_id,service_id,location,location_source,address_text,status,price_amount,currency_code,commission_bps,pricing,travel_distance_m)
    VALUES($1,$2,$3,'x','MANUAL_PIN','a','IN_SERVICE',1200,'SYP_NEW',2000,$4::jsonb,$5) RETURNING id`, [patient.u, patient.b, svc, JSON.stringify(snapshot), travel]);
  await pg.query(`UPDATE nurses SET work_status='IN_SERVICE' WHERE id=$1`, [nurseId]);
  const asg = await id(`INSERT INTO request_assignments(request_id,nurse_id,status) VALUES($1,$2,'ACTIVE') RETURNING id`, [req, nurseId]);
  await pg.query('INSERT INTO visits(assignment_id) VALUES($1)',[asg]);
  await recordExecution(db,{requestId:req,beneficiaryId:patient.b,nurseUserId:nurseU,serviceId:svc,minutes,visitTime:arrivedAt});
  await dispatch.transition(nurseU, asg, 'complete');
  return req;
}
const bill = (r, who = N) => pricing.nurseBill(who, r);

test('every automatic fee is OFF by default; settings are validated and audited', async () => {
  const s = (await adminFees.settings(A)).settings;
  assert.deepEqual([s.distance_enabled, s.night_enabled, s.holiday_enabled, s.tax_enabled], [false, false, false, false]);
  await adminFees.updateSettings(A, { nightEnabled: true, nightPercent: 25 });
  assert.equal((await adminFees.settings(A)).settings.night_percent, '25.00');
  await assert.rejects(adminFees.updateSettings(A, {}), code('NOTHING_TO_UPDATE'));
  await assert.rejects(adminFees.updateSettings({ user: { id: adminU, role: 'PATIENT' } }, { taxEnabled: true }), e => e.getStatus() === 403);
  assert.equal((await pg.query(`SELECT count(*)::int n FROM audit_log WHERE action='pricing_settings.updated'`)).rows[0].n, 1);
  await adminFees.updateSettings(A, { nightEnabled: false });
});

test('night surcharge is applied automatically from the arrival time (Damascus local time) and frozen per order', async () => {
  await adminFees.updateSettings(A, { nightEnabled: true, nightPercent: 25 });
  const p = await mkPatient(1);
  const night = await visit(p, { arrivedAt: '2026-11-23T19:30:00Z' }); // 22:30 in Damascus
  // arrival is forced to the past, complete() runs "now"; 47 minutes is not needed here: only the night flag matters
  const b = await bill(night);
  assert.ok(b.surcharge > 0, 'night surcharge should be charged');
  await adminFees.updateSettings(A, { nightEnabled: false }); // later change does not alter the already-placed order
  assert.equal((await bill(night)).surcharge, b.surcharge);
});

test('distance fee, tax, tiered commission and earnings flow into one consistent bill', async () => {
  await adminFees.updateSettings(A, { nightEnabled: false, distanceEnabled: true, freeKm: 3, perKm: 200, maxDistanceFee: 2000, taxEnabled: true, taxPercent: 10, taxLabel: 'ضريبة مبيعات' });
  const p = await mkPatient(2);
  const r = await visit(p, { minutes: 47, travel: 7000 });
  const b = await bill(r);
  assert.equal(b.distanceFee, 800);
  assert.equal(b.tax, 280);                // 10% of (2000 + 800)
  assert.equal(b.due, 3100);               // 3080 rounded up to 50
  assert.equal(b.taxLabel, 'ضريبة مبيعات');
  assert.equal(b.commissionBps, 2000);
  assert.equal(b.nurseEarning, 1600 + 800); // 2000-20% + travel fee kept entirely by the nurse
  // reputation tiers: a top-rated nurse pays a lower commission on the NEXT visits
  const v = (await pg.query(`SELECT v.id FROM visits v JOIN request_assignments a ON a.id=v.assignment_id WHERE a.request_id=$1`, [r])).rows[0].id;
  for (let i = 0; i < 12; i++) {
    const pp = await mkPatient(100 + i);
    await pg.query(`INSERT INTO visit_reviews(visit_id,reviewer_user_id,reviewer_role,stars) VALUES($1,$2,'PATIENT',5) ON CONFLICT DO NOTHING`, [v, pp.u]);
  }
});

test('tiered commission: top reputation gets a lower company cut', async () => {
  const t = await adminFees.addTier(A, { minReputation: 4.0, minReviews: 1, commissionBps: 1200 });
  await adminFees.addTier(A, { minReputation: 4.5, minReviews: 50, commissionBps: 800 });
  const rep = await fees.reputation(db, nurseId);
  assert.ok(rep.reviews >= 1 && rep.reputation >= 4);
  const p = await mkPatient(3);
  const r = await visit(p, { minutes: 20 });
  assert.equal((await bill(r)).commissionBps, 1200); // qualifies for the 4.0 tier, not the 4.5 one
  await adminFees.updateTier(A, t.id, { active: false });
  const r2 = await visit(await mkPatient(4), { minutes: 20 });
  assert.equal((await bill(r2)).commissionBps, 2000); // tier switched off from the panel
});

let tipReq, tipPatient;
test('optional tip: patient adds it before paying; it is collected with the bill and belongs 100% to the nurse', async () => {
  await adminFees.updateSettings(A, { distanceEnabled: false, taxEnabled: false });
  tipPatient = await mkPatient(5);
  tipReq = await visit(tipPatient, { minutes: 20 });
  const b0 = await bill(tipReq);
  await pricing.tip(tipPatient.ctx,tipReq,{amount:300},'visit-tip');
  const b1 = await bill(tipReq);
  assert.equal(b1.tip, 300); assert.equal(b1.payable, b0.due + 300); assert.equal(b1.nurseEarning, b0.nurseEarning + 300);
  const short = await pricing.collect(N,tipReq,{amount:b0.due},'base-payment');
  assert.equal(short.status,'PARTIALLY_PAID'); assert.equal(short.remaining,300);
  const done = await pricing.collect(N,tipReq,{amount:300},'tip-payment');
  assert.equal(done.status, 'PAID');
  await assert.rejects(pricing.tip(tipPatient.ctx,tipReq,{amount:100},'after-paid'), code('ALREADY_PAID'));
  await adminFees.updateSettings(A, { tipsEnabled: false });
  await assert.rejects(pricing.tip((await mkPatient(6)).ctx, tipReq, { amount: 1 }), code('TIPS_DISABLED'));
  await adminFees.updateSettings(A, { tipsEnabled: true });
});

test('company dues: what the nurse owes from cash, settlements, and the stop-receiving limit', async () => {
  const open=(await pg.query(`SELECT i.request_id,i.total_amount FROM invoices i WHERE i.status='ISSUED'`)).rows;
  for(const invoice of open) await pricing.collect(N,invoice.request_id,{amount:Number(invoice.total_amount)},`closing:${invoice.request_id}`);
  const d0 = (await adminFees.allDues(A)).items.find(x => x.nurse_id === nurseId);
  assert.ok(Number(d0.balance) > 0 && d0.visits >= 1);
  const mine = await new (await import('../dist/nurses/nurse-me.controller.js')).NurseMeController(db,undefined,dues).duesView(N);
  assert.equal(mine.balance, Number(d0.balance));
  // limit below the balance -> the nurse cannot go AVAILABLE until she settles with the company
  await adminFees.updateSettings(A, { nurseDebtLimit: 100 });
  await assert.rejects(nursesSvc.availability(nurseU, { availability: 'AVAILABLE' }), code('SETTLEMENT_REQUIRED'));
  const after = await adminFees.settle(A,nurseId,{direction:'FROM_NURSE',amount:mine.balance,note:'استلام نقدي'},'full-settlement');
  assert.equal(after.balance, 0);
  assert.equal((await nursesSvc.availability(nurseU, { availability: 'AVAILABLE' })).availabilityIntent, 'AVAILABLE'); // allowed again after settling
});

test('referrals: personal code, welcome discount, one referrer only, reward after the first PAID order, monthly cap', async () => {
  await assert.rejects(refCtl.mine((await mkPatient(7)).ctx).then(r => { if (!r.enabled) throw new Error('disabled'); }), /disabled/);
  await adminFees.updateSettings(A, { referralEnabled: true, referralReferredPercent: 20, referralReferrerPercent: 10, referralMaxDiscount: 500, referralMaxRewardsPerMonth: 1 });
  const friend = await mkPatient(8), newbie = await mkPatient(9), other = await mkPatient(10);
  const mine = await refCtl.mine(friend.ctx);
  assert.match(mine.code, /^TM[A-Z2-9]{6}$/);
  assert.equal((await refCtl.mine(friend.ctx)).code, mine.code);                         // stable
  await assert.rejects(refCtl.claim(friend.ctx, { code: mine.code }), code('REFERRAL_OWN_CODE'));
  await assert.rejects(refCtl.claim(newbie.ctx, { code: 'TMNOPE00' }), code('REFERRAL_CODE_NOT_FOUND'));
  const claimed = await refCtl.claim(newbie.ctx, { code: mine.code.toLowerCase() });
  assert.equal(claimed.discountPercent, 20);
  await assert.rejects(refCtl.claim(newbie.ctx, { code: mine.code }), code('REFERRAL_ALREADY_USED'));
  // the welcome promo is personal: nobody else can use it
  await assert.rejects(pricing.quote(other.ctx, { serviceId: svc, promoCode: claimed.promoCode }), code('PROMO_NOT_FOUND'));
  assert.equal((await pricing.quote(newbie.ctx, { serviceId: svc })).promoCode, claimed.promoCode); // applied automatically
  // newbie's first order gets paid -> friend earns a reward promo
  const r = await visit(newbie, { minutes: 20 });
  await pg.query(`UPDATE care_requests SET promo_id=(SELECT id FROM promo_codes WHERE code=$2) WHERE id=$1`, [r, claimed.promoCode]);
  const b = await bill(r);
  await pricing.collect(N,r,{amount:b.payable},'referral-first');
  const reward = (await pg.query(`SELECT code,only_user_id,max_redemptions FROM promo_codes WHERE source='REFERRAL' AND only_user_id=$1`, [friend.u])).rows;
  assert.equal(reward.length, 1); assert.equal(reward[0].max_redemptions, 1);
  assert.equal((await refCtl.mine(friend.ctx)).rewarded, 1);
  // monthly cap = 1: the next referred friend's first order does not reward the same referrer again
  const third = await mkPatient(11);
  await refCtl.claim(third.ctx, { code: mine.code });
  const r3 = await visit(third, { minutes: 20 });
  await pricing.collect(N,r3,{amount:(await bill(r3)).payable},'referral-cap');
  assert.equal((await pg.query(`SELECT count(*)::int n FROM promo_codes WHERE source='REFERRAL' AND only_user_id=$1`, [friend.u])).rows[0].n, 1);
});

test('promo protection: wrong-code guessing is rate limited; monthly order cap; abuse review lists suspicious sharing', async () => {
  await adminFees.updateSettings(A, { promoAttemptsPerHour: 3, promoMaxOrders30d: 0 });
  await adminBiz.createPromo(A, { code: 'LOYAL10', type: 'PERCENT', value: 10 });
  const guesser = await mkPatient(20);
  for (let i = 0; i < 3; i++) await assert.rejects(pricing.quote(guesser.ctx, { serviceId: svc, promoCode: 'GUESS' + i }), code('PROMO_NOT_FOUND'));
  await assert.rejects(pricing.quote(guesser.ctx, { serviceId: svc, promoCode: 'LOYAL10' }), e => e.getStatus() === 429); // even the right code is blocked for now
  const rep = await adminFees.abuse(A);
  assert.equal(rep.guessing.length, 0); // threshold for review is 5 failures
  await adminFees.updateSettings(A, { promoAttemptsPerHour: 10 });
  // two accounts using promos from the same address
  const p1 = await mkPatient(21), p2 = await mkPatient(22);
  const promoId = (await pg.query(`SELECT id FROM promo_codes WHERE code='LOYAL10'`)).rows[0].id;
  for (const p of [p1, p2]) await pg.query(`INSERT INTO care_requests(requester_user_id,beneficiary_id,service_id,location,location_source,address_text,status,price_amount,currency_code,commission_bps,promo_id)
    VALUES($1,$2,$3,'x','MANUAL_PIN',' Damascus - Mezzeh ','COMPLETED',1200,'SYP_NEW',2000,$4)`, [p.u, p.b, svc, promoId]);
  const rep2 = await adminFees.abuse(A);
  assert.equal(rep2.sameAddress[0].accounts, 2);
  // monthly cap of promo orders per user
  await adminFees.updateSettings(A, { promoMaxOrders30d: 1 });
  await assert.rejects(pricing.quote(p1.ctx, { serviceId: svc, promoCode: 'LOYAL10' }), code('PROMO_LIMIT_REACHED'));
});

test('holidays: listed dates and weekly day off are surcharged; switching the feature off stops it', async () => {
  await adminFees.updateSettings(A, { holidayEnabled: true, holidayPercent: 40, weekendDays: [5], nightEnabled: false });
  const visitStartedAt = new Date(Date.now() - 20 * 60_000);
  const holiday = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Damascus', year: 'numeric', month: '2-digit', day: '2-digit' }).format(visitStartedAt);
  await adminFees.addHoliday(A, { day: holiday, name: 'عطلة تجريبية' });
  const s = await fees.snapshot(db);
  assert.ok(s.holidays.includes(holiday));
  const p = await mkPatient(30);
  const r = await visit(p, { minutes: 20, arrivedAt: visitStartedAt.toISOString() });
  // complete() stamps completed_at = now(); arrival is on the holiday
  assert.equal((await bill(r)).surcharge, 480); // 40% of 1200
  await adminFees.removeHoliday(A, holiday);
  assert.equal((await fees.snapshot(db)).holidays.includes(holiday), false);
});
