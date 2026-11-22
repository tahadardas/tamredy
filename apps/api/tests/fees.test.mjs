import test from 'node:test';
import assert from 'node:assert/strict';
const P = await import('../dist/pricing/pricing.js');
const rule = { basePrice: 1200, includedMinutes: 30, blockMinutes: 15, blockPrice: 400, expectedMinutes: 40, roundingStep: 50 };
const fees = { ...P.NO_FEES, distanceEnabled: true, freeKm: 3, perKm: 200, maxDistanceFee: 2000,
  nightEnabled: true, nightStart: '22:00', nightEnd: '06:00', nightPercent: 25,
  holidayEnabled: true, holidayPercent: 40, weekendDays: [5], holidays: ['2026-12-25'], taxEnabled: false, taxPercent: 0 };
// Damascus is UTC+3 (no DST). 2026-11-23 is a Monday.
const at = (iso) => new Date(iso);

test('night window wraps midnight and uses LOCAL (Damascus) time', () => {
  assert.equal(P.surchargeFlags(fees, at('2026-11-23T19:30:00Z')).night, true);  // 22:30 local
  assert.equal(P.surchargeFlags(fees, at('2026-11-23T01:00:00Z')).night, true);  // 04:00 local
  assert.equal(P.surchargeFlags(fees, at('2026-11-23T10:00:00Z')).night, false); // 13:00 local
  assert.equal(P.surchargeFlags(fees, at('2026-11-23T03:00:00Z')).night, false); // 06:00 local = end, exclusive
});

test('holiday: weekly day off (Friday) and listed dates; higher surcharge wins unless stacking is on', () => {
  assert.equal(P.surchargeFlags(fees, at('2026-11-27T10:00:00Z')).holiday, true);  // Friday
  assert.equal(P.surchargeFlags(fees, at('2026-12-25T10:00:00Z')).holiday, true);  // listed
  const both = at('2026-11-27T19:30:00Z'); // Friday 22:30 local: night AND holiday
  assert.equal(P.surchargeFlags(fees, both).percent, 40);
  assert.equal(P.surchargeFlags({ ...fees, stackSurcharges: true }, both).percent, 65);
  assert.equal(P.surchargeFlags({ ...fees, holidayEnabled: false }, at('2026-11-27T10:00:00Z')).holiday, false); // admin switched it off
});

test('distance fee: free radius, per-km, cap, disabled', () => {
  assert.equal(P.distanceFeeFor(fees, 2500), 0);
  assert.equal(P.distanceFeeFor(fees, 7000), 800);        // 4 km chargeable x 200
  assert.equal(P.distanceFeeFor(fees, 40000), 2000);      // capped
  assert.equal(P.distanceFeeFor({ ...fees, distanceEnabled: false }, 7000), 0);
});

test('tiered commission lowers the company cut for top-rated nurses only', () => {
  const tiers = [{ minReputation: 4.8, minReviews: 20, commissionBps: 1200 }, { minReputation: 4.5, minReviews: 5, commissionBps: 1600 }];
  assert.equal(P.commissionFor(2000, tiers, 4.9, 30), 1200);
  assert.equal(P.commissionFor(2000, tiers, 4.9, 10), 1600);   // not enough reviews for the top tier
  assert.equal(P.commissionFor(2000, tiers, 4.2, 50), 2000);
  assert.equal(P.commissionFor(1000, tiers, 4.9, 30), 1000);   // a tier never raises the cut above the service default
});

test('full bill: night + distance + promo + tax, nurse earning and what she owes the company', () => {
  const f = { ...fees, taxEnabled: true, taxPercent: 10 };
  const b = P.computeBill(rule, 47 * 60, { fees: f, arrivedAt: at('2026-11-23T19:30:00Z'), travelMeters: 7000, commissionBps: 2000,
    promo: { type: 'PERCENT', value: 20, maxDiscount: 500 } });
  assert.equal(b.timeGross, 2000);                 // 47 min
  assert.equal(b.surcharge, 500);                  // night 25%
  assert.equal(b.distanceFee, 800);
  assert.equal(b.gross, 2500);
  assert.equal(b.discount, 500);                   // 20% = 500 (cap 500) of the service value only
  assert.equal(b.tax, 280);                        // 10% of (2500-500+800)=2800
  assert.equal(b.due, 3100);                       // 3080 -> rounded up to 50
  assert.equal(b.commission, 500);                 // 20% of 2500 (not of the travel fee)
  assert.equal(b.nurseEarning, 2800);              // 2500-500(commission)+800(travel)
  assert.equal(b.owedToCompany, 300);              // 3100 - 2800
});

test('simple case equals the old algorithm; fees default to off', () => {
  const b = P.computeBill(rule, 47 * 60, { commissionBps: 2000 });
  assert.deepEqual([b.due, b.surcharge, b.distanceFee, b.tax], [2000, 0, 0, 0]);
});

test('estimate shows surcharges that apply right now and the tax; travel fee is flagged, not guessed', () => {
  const e = P.estimateV2(rule, null, { ...fees, taxEnabled: true, taxPercent: 10 }, at('2026-11-23T19:30:00Z'));
  assert.equal(e.nightApplied, true); assert.equal(e.travelFeeMayApply, true);
  assert.equal(e.min, 1650);       // 1200 +25% = 1500, +10% = 1650
  assert.equal(e.expected, 2200);  // 1600 +25% = 2000, +10% = 2200
  assert.equal(P.estimateV2(rule, null, null).min, 1200);
});

test('tip is added to the cash the patient hands over, never negative', () => {
  assert.equal(P.payableTotal(2000, 300), 2300);
  assert.equal(P.payableTotal(2000, -50), 2000);
});
