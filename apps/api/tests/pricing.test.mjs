import test from 'node:test';
import assert from 'node:assert/strict';
const P = await import('../dist/pricing/pricing.js');
// Dressing: 1200 covers 30 min; each started 15 min after adds 400; typical visit 40 min.
const rule = { basePrice: 1200, includedMinutes: 30, blockMinutes: 15, blockPrice: 400, expectedMinutes: 40, roundingStep: 50 };

test('time-based gross: base inside included time, then per started block', () => {
  assert.equal(P.grossFor(rule, 5), 1200);
  assert.equal(P.grossFor(rule, 30), 1200);
  assert.equal(P.grossFor(rule, 31), 1600);   // 1 minute over -> a full block
  assert.equal(P.grossFor(rule, 45), 1600);
  assert.equal(P.grossFor(rule, 46), 2000);
});

test('estimate is available instantly: minimum and expected', () => {
  const e = P.estimate(rule);
  assert.equal(e.min, 1200); assert.equal(e.expected, 1600);
});

test('final bill uses real time at the patient and rounds up to the step', () => {
  assert.deepEqual(P.finalBill(rule, 20 * 60), { minutes: 20, gross: 1200, discount: 0, due: 1200 });
  const b = P.finalBill(rule, 47 * 60 + 5); // 48 minutes started
  assert.equal(b.minutes, 48); assert.equal(b.gross, 2000);
  assert.equal(P.finalBill({ ...rule, blockPrice: 330, roundingStep: 100 }, 40 * 60).due, 1600); // 1530 -> 1600
});

test('promo: percent with cap, fixed, never below zero, applied to estimate and bill', () => {
  assert.equal(P.discountFor(2000, { type: 'PERCENT', value: 10 }), 200);
  assert.equal(P.discountFor(2000, { type: 'PERCENT', value: 50, maxDiscount: 300 }), 300);
  assert.equal(P.discountFor(500, { type: 'FIXED', value: 900 }), 500);
  assert.equal(P.estimate(rule, { type: 'PERCENT', value: 25 }).expected, 1200);
  assert.equal(P.finalBill(rule, 47 * 60, { type: 'FIXED', value: 500 }).due, 1500);
});

test('collection: a short payment is flagged, keeps the bill open, and can be completed', () => {
  const a = P.applyCollection(1600, 0, 1000);
  assert.deepEqual([a.status, a.remaining, a.change], ['PARTIAL', 600, 0]);
  const b = P.applyCollection(1600, a.collected, 600);
  assert.deepEqual([b.status, b.remaining], ['PAID', 0]);
});

test('collection: overpayment becomes change and only the due part is applied', () => {
  const r = P.applyCollection(1600, 0, 2000);
  assert.deepEqual([r.status, r.applied, r.change], ['PAID', 1600, 400]);
  assert.throws(() => P.applyCollection(1600, 0, 0));
  assert.throws(() => P.applyCollection(1600, 0, 10.5));
});
