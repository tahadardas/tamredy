/** Pure pricing rules (no I/O) so they are easy to test and identical wherever used.
 *  Money is whole Syrian pounds. Rules are snapshotted on each request at creation. */

export interface PricingRule {
  basePrice: number;        // covers `includedMinutes`
  includedMinutes: number;
  blockMinutes: number;     // every started block after the included time...
  blockPrice: number;       // ...adds this amount
  expectedMinutes: number;  // typical visit length, used for the up-front estimate
  roundingStep: number;     // bill is rounded UP to a multiple of this (eases cash change)
}
export interface PromoRule { code?: string; type: 'PERCENT' | 'FIXED'; value: number; maxDiscount?: number | null; }

const int = (n: unknown) => Math.max(0, Math.round(Number(n) || 0));

export function ruleFromRow(r: Record<string, unknown>): PricingRule {
  return {
    basePrice: int(r.price_amount ?? r.basePrice), includedMinutes: Math.max(1, int(r.included_minutes ?? r.includedMinutes)),
    blockMinutes: Math.max(1, int(r.block_minutes ?? r.blockMinutes)), blockPrice: int(r.block_price ?? r.blockPrice),
    expectedMinutes: Math.max(1, int(r.expected_minutes ?? r.expectedMinutes)), roundingStep: Math.max(1, int(r.rounding_step ?? r.roundingStep) || 1),
  };
}

/** Price of a visit that lasted `minutes` at the patient's home, before any discount. */
export function grossFor(rule: PricingRule, minutes: number): number {
  const extra = Math.max(0, Math.ceil(minutes) - rule.includedMinutes);
  return rule.basePrice + Math.ceil(extra / rule.blockMinutes) * rule.blockPrice;
}

export function discountFor(gross: number, promo?: PromoRule | null): number {
  if (!promo || gross <= 0) return 0;
  let d = promo.type === 'PERCENT' ? Math.round((gross * promo.value) / 100) : Math.round(promo.value);
  if (promo.maxDiscount != null) d = Math.min(d, Math.round(promo.maxDiscount));
  return Math.min(Math.max(d, 0), gross);
}

const roundUp = (n: number, step: number) => (step <= 1 ? n : Math.ceil(n / step) * step);

/** Shown to the patient as soon as they pick a service: "from X, usually about Y". */
export function estimate(rule: PricingRule, promo?: PromoRule | null) {
  const minGross = grossFor(rule, 0);
  const expGross = grossFor(rule, rule.expectedMinutes);
  const dMin = discountFor(minGross, promo), dExp = discountFor(expGross, promo);
  return {
    min: roundUp(minGross - dMin, rule.roundingStep),
    expected: roundUp(expGross - dExp, rule.roundingStep),
    grossMin: minGross, grossExpected: expGross, discountExpected: dExp,
    includedMinutes: rule.includedMinutes, blockMinutes: rule.blockMinutes, blockPrice: rule.blockPrice,
  };
}

/** Final bill from the real time spent at the patient (arrival -> end of visit). */
export function finalBill(rule: PricingRule, secondsAtPatient: number, promo?: PromoRule | null) {
  const minutes = Math.max(1, Math.ceil(Math.max(0, secondsAtPatient) / 60));
  const gross = grossFor(rule, minutes);
  const discount = discountFor(gross, promo);
  return { minutes, gross, discount, due: roundUp(gross - discount, rule.roundingStep) };
}

export type CollectStatus = 'PARTIAL' | 'PAID';
/** Applies one cash entry. A short payment keeps the bill open; an excess becomes change. */
export function applyCollection(due: number, alreadyCollected: number, received: number) {
  if (!Number.isInteger(received) || received <= 0) throw new Error('INVALID_AMOUNT');
  const remainingBefore = Math.max(0, due - alreadyCollected);
  const applied = Math.min(received, remainingBefore);
  const collected = alreadyCollected + applied;
  const remaining = due - collected;
  return { applied, collected, remaining, change: received - applied, status: (remaining === 0 ? 'PAID' : 'PARTIAL') as CollectStatus };
}

// ======================================================================
// Fees, tax, tiered commission and the full bill (v2). All amounts are whole pounds.
// ======================================================================

export interface FeeSettings {
  tz: string;                       // e.g. 'Asia/Damascus'
  distanceEnabled: boolean; freeKm: number; perKm: number; maxDistanceFee: number; // 0 = no cap
  nightEnabled: boolean; nightStart: string; nightEnd: string; nightPercent: number; // 'HH:MM', may wrap midnight
  holidayEnabled: boolean; holidayPercent: number; weekendDays: number[];            // 0=Sunday .. 6=Saturday
  holidays: string[];               // 'YYYY-MM-DD' (snapshot of upcoming dates)
  stackSurcharges: boolean;         // false: the higher of night/holiday applies; true: they add up
  taxEnabled: boolean; taxPercent: number; taxLabel?: string;
}

export const NO_FEES: FeeSettings = {
  tz: 'Asia/Damascus', distanceEnabled: false, freeKm: 0, perKm: 0, maxDistanceFee: 0,
  nightEnabled: false, nightStart: '22:00', nightEnd: '06:00', nightPercent: 0,
  holidayEnabled: false, holidayPercent: 0, weekendDays: [], holidays: [], stackSurcharges: false, taxEnabled: false, taxPercent: 0,
};

/** Local wall-clock parts in the business time zone (so "night" means night in Damascus, not on the server). */
export function localParts(d: Date, tz: string) {
  const parts = new Intl.DateTimeFormat('en-GB', { timeZone: tz, hourCycle: 'h23', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', weekday: 'short' }).formatToParts(d);
  const g = (t: string) => parts.find(p => p.type === t)!.value;
  const dow = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].indexOf(g('weekday'));
  return { date: `${g('year')}-${g('month')}-${g('day')}`, minutes: Number(g('hour')) * 60 + Number(g('minute')), dow };
}
const hm = (s: string) => { const [h, m] = s.split(':').map(Number); return (h ?? 0) * 60 + (m ?? 0); };

export function surchargeFlags(f: FeeSettings, at: Date) {
  const p = localParts(at, f.tz);
  const a = hm(f.nightStart), b = hm(f.nightEnd);
  const night = f.nightEnabled && f.nightPercent > 0 && (a <= b ? p.minutes >= a && p.minutes < b : p.minutes >= a || p.minutes < b);
  const holiday = f.holidayEnabled && f.holidayPercent > 0 && (f.weekendDays.includes(p.dow) || f.holidays.includes(p.date));
  const percent = f.stackSurcharges ? (night ? f.nightPercent : 0) + (holiday ? f.holidayPercent : 0) : Math.max(night ? f.nightPercent : 0, holiday ? f.holidayPercent : 0);
  return { night, holiday, percent };
}

/** Travel fee: automatic from the distance the nurse covered to reach the patient. */
export function distanceFeeFor(f: FeeSettings, meters: number): number {
  if (!f.distanceEnabled || !(meters > 0)) return 0;
  const fee = Math.round(Math.max(0, meters / 1000 - f.freeKm) * f.perKm);
  return f.maxDistanceFee > 0 ? Math.min(fee, Math.round(f.maxDistanceFee)) : fee;
}

/** Commission tiers reward high-reputation nurses with a LOWER company cut (never higher than the service default). */
export interface Tier { minReputation: number; minReviews: number; commissionBps: number; }
export function commissionFor(serviceBps: number, tiers: Tier[], reputation: number, reviews: number): number {
  const hit = [...tiers].sort((x, y) => y.minReputation - x.minReputation).find(t => reputation >= t.minReputation && reviews >= t.minReviews);
  return hit ? Math.min(serviceBps, hit.commissionBps) : serviceBps;
}

export interface BillContext {
  promo?: PromoRule | null; fees?: FeeSettings | null; arrivedAt?: Date; travelMeters?: number; commissionBps: number;
}
/** The complete bill. Commission is taken on the service value (time + surcharges), the travel fee goes entirely to the nurse,
 *  promo discounts are funded by the company, and tax is a separate pass-through line. */
export function computeBill(rule: PricingRule, secondsAtPatient: number, ctx: BillContext) {
  const fees = ctx.fees ?? NO_FEES;
  const minutes = Math.max(1, Math.ceil(Math.max(0, secondsAtPatient) / 60));
  const timeGross = grossFor(rule, minutes);
  const s = surchargeFlags(fees, ctx.arrivedAt ?? new Date());
  const surcharge = Math.round((timeGross * s.percent) / 100);
  const distanceFee = distanceFeeFor(fees, ctx.travelMeters ?? 0);
  const serviceValue = timeGross + surcharge;
  const discount = discountFor(serviceValue, ctx.promo);
  const subtotal = serviceValue - discount + distanceFee;
  const tax = fees.taxEnabled ? Math.round((subtotal * fees.taxPercent) / 100) : 0;
  const due = roundUp(subtotal + tax, rule.roundingStep);
  const commission = Math.round((serviceValue * ctx.commissionBps) / 10000);
  const nurseEarning = serviceValue - commission + distanceFee;
  return {
    minutes, timeGross, nightApplied: s.night, holidayApplied: s.holiday, surchargePercent: s.percent, surcharge, distanceFee,
    gross: serviceValue, discount, tax, due, commissionBps: ctx.commissionBps, commission, nurseEarning,
    /** What the nurse must hand to the company out of the cash collected (negative = company owes the nurse). */
    owedToCompany: due - nurseEarning,
    companyNet: commission - discount,
  };
}

/** Up-front estimate: surcharges that apply RIGHT NOW + tax; the travel fee depends on which nurse accepts. */
export function estimateV2(rule: PricingRule, promo: PromoRule | null | undefined, fees: FeeSettings | null | undefined, now = new Date()) {
  const f = fees ?? NO_FEES;
  const s = surchargeFlags(f, now);
  const one = (minutes: number) => {
    const g = grossFor(rule, minutes), sur = Math.round((g * s.percent) / 100), value = g + sur, d = discountFor(value, promo);
    const sub = value - d, tax = f.taxEnabled ? Math.round((sub * f.taxPercent) / 100) : 0;
    return { total: roundUp(sub + tax, rule.roundingStep), surcharge: sur, tax, discount: d };
  };
  const lo = one(0), ex = one(rule.expectedMinutes);
  return {
    min: lo.total, expected: ex.total, surchargePercent: s.percent, nightApplied: s.night, holidayApplied: s.holiday,
    taxPercent: f.taxEnabled ? f.taxPercent : 0, travelFeeMayApply: f.distanceEnabled, freeKm: f.freeKm, perKm: f.perKm,
    includedMinutes: rule.includedMinutes, blockMinutes: rule.blockMinutes, blockPrice: rule.blockPrice,
  };
}

/** Cash plan: what the patient hands over = bill + optional tip (tip is 100% the nurse's). */
export const payableTotal = (due: number, tip: number) => due + Math.max(0, tip);
