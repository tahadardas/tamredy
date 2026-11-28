import { Injectable } from '@nestjs/common';
import { FeeSettings, Tier } from './pricing.js';

export type Q = { query: (sql: string, p?: unknown[]) => Promise<{ rows: any[]; rowCount: number | null }> };

/** Reads the administrator's pricing settings. The values are snapshotted onto each request at creation,
 *  so changing a fee never alters an order already placed. */
@Injectable()
export class FeesService {
  async row(q: Q) { return (await q.query('SELECT * FROM pricing_settings WHERE id=1')).rows[0]; }

  async snapshot(q: Q): Promise<FeeSettings> {
    const s = await this.row(q);
    const hol = (await q.query(`SELECT to_char(day,'YYYY-MM-DD') AS d FROM holidays WHERE active AND day BETWEEN current_date-1 AND current_date+400`)).rows;
    return {
      tz: s.tz, distanceEnabled: s.distance_enabled, freeKm: Number(s.free_km), perKm: Number(s.per_km), maxDistanceFee: Number(s.max_distance_fee),
      nightEnabled: s.night_enabled, nightStart: s.night_start, nightEnd: s.night_end, nightPercent: Number(s.night_percent),
      holidayEnabled: s.holiday_enabled, holidayPercent: Number(s.holiday_percent), weekendDays: (s.weekend_days ?? []).map(Number),
      holidays: hol.map(h => h.d), stackSurcharges: s.stack_surcharges, taxEnabled: s.tax_enabled, taxPercent: Number(s.tax_percent), taxLabel: s.tax_label,
    };
  }

  async tiers(q: Q): Promise<Tier[]> {
    return (await q.query('SELECT min_reputation,min_reviews,commission_bps FROM commission_tiers WHERE active')).rows
      .map(t => ({ minReputation: Number(t.min_reputation), minReviews: Number(t.min_reviews), commissionBps: Number(t.commission_bps) }));
  }

  /** Bayesian average (prior weight 5) of patient stars, all time: a handful of 5s cannot beat a long good record. */
  async reputation(q: Q, nurseId: string): Promise<{ reputation: number; reviews: number }> {
    const r = (await q.query(`WITH g AS (SELECT coalesce(avg(stars),4)::float8 AS m FROM visit_reviews WHERE reviewer_role='PATIENT'),
      r AS (SELECT count(*)::int AS n,coalesce(sum(vr.stars),0)::float8 AS s FROM visit_reviews vr JOIN visits v ON v.id=vr.visit_id
        JOIN request_assignments a ON a.id=v.assignment_id WHERE a.nurse_id=$1 AND vr.reviewer_role='PATIENT')
      SELECT r.n AS reviews,((5*g.m)+r.s)/(5+r.n) AS reputation FROM g,r`, [nurseId])).rows[0];
    return { reputation: Number(r.reputation), reviews: Number(r.reviews) };
  }
}

/** What each nurse owes the company (or the company owes her) from cash she collected. */
@Injectable()
export class DuesService {
  /** BUG-010: Net settlement position grouped strictly per currency from immutable double-entry accounts. */
  async balance(q: Q, nurseId: string, currencyCode: string) {
    const r = (await q.query(`SELECT
      coalesce(sum(CASE WHEN e.account_id='CASH_HELD_BY_NURSE:'||$1::text
        THEN e.debit_amount-e.credit_amount ELSE 0 END),0) AS cash_held,
      coalesce(sum(CASE WHEN e.account_id='NURSE_PAYABLE:'||$1::text
        THEN e.credit_amount-e.debit_amount ELSE 0 END),0) AS nurse_payable,
      coalesce(sum(CASE WHEN t.transaction_type='NURSE_SETTLEMENT_FROM_NURSE'
        AND e.account_id='CASH_HELD_BY_NURSE:'||$1::text THEN e.credit_amount ELSE 0 END),0) AS from_nurse,
      coalesce(sum(CASE WHEN t.transaction_type='NURSE_SETTLEMENT_TO_NURSE'
        AND e.account_id='NURSE_PAYABLE:'||$1::text THEN e.debit_amount ELSE 0 END),0) AS to_nurse,
      (SELECT credit_limit FROM nurse_financial_currency_accounts WHERE nurse_id=$1::uuid AND currency_code=$2) AS debt_limit,
      (SELECT settlement_required FROM nurse_financial_currency_accounts WHERE nurse_id=$1::uuid AND currency_code=$2) AS settlement_required
      FROM financial_ledger_entries e JOIN financial_transactions t ON t.id=e.transaction_id
      WHERE e.account_id IN ('CASH_HELD_BY_NURSE:'||$1::text,'NURSE_PAYABLE:'||$1::text)
        AND e.currency = $2`, [nurseId, currencyCode])).rows[0];
    const cashHeld = Number(r.cash_held), nursePayable = Number(r.nurse_payable);
    const fromNurse = Number(r.from_nurse), toNurse = Number(r.to_nurse), limit = Number(r.debt_limit);
    const balance = cashHeld - nursePayable;
    const owed = Math.max(0,balance);
    return { currencyCode, owed, settledFromNurse: fromNurse, paidToNurse: toNurse, balance, limit, blocked: r.settlement_required===true || (limit > 0 && balance > limit) };
  }

  async balancesByCurrency(q: Q, nurseId: string) {
    const rows = (await q.query(`SELECT
      k.currency_code,
      coalesce(sum(CASE WHEN e.account_id='CASH_HELD_BY_NURSE:'||$1::text
        THEN e.debit_amount-e.credit_amount ELSE 0 END),0) AS cash_held,
      coalesce(sum(CASE WHEN e.account_id='NURSE_PAYABLE:'||$1::text
        THEN e.credit_amount-e.debit_amount ELSE 0 END),0) AS nurse_payable,
      coalesce(sum(CASE WHEN t.transaction_type='NURSE_SETTLEMENT_FROM_NURSE'
        AND e.account_id='CASH_HELD_BY_NURSE:'||$1::text THEN e.credit_amount ELSE 0 END),0) AS from_nurse,
      coalesce(sum(CASE WHEN t.transaction_type='NURSE_SETTLEMENT_TO_NURSE'
        AND e.account_id='NURSE_PAYABLE:'||$1::text THEN e.debit_amount ELSE 0 END),0) AS to_nurse,
      (SELECT credit_limit FROM nurse_financial_currency_accounts WHERE nurse_id=$1::uuid AND currency_code=k.currency_code) AS debt_limit,
      (SELECT settlement_required FROM nurse_financial_currency_accounts WHERE nurse_id=$1::uuid AND currency_code=k.currency_code) AS settlement_required
      FROM (SELECT currency_code FROM nurse_financial_currency_accounts WHERE nurse_id=$1::uuid
        UNION SELECT currency FROM financial_ledger_entries WHERE account_id IN
          ('CASH_HELD_BY_NURSE:'||$1::text,'NURSE_PAYABLE:'||$1::text)) k
      LEFT JOIN financial_ledger_entries e ON e.currency=k.currency_code AND e.account_id IN
        ('CASH_HELD_BY_NURSE:'||$1::text,'NURSE_PAYABLE:'||$1::text)
      LEFT JOIN financial_transactions t ON t.id=e.transaction_id
      GROUP BY k.currency_code
      ORDER BY k.currency_code`, [nurseId])).rows;
    return rows.map(r => {
      const cashHeld = Number(r.cash_held), nursePayable = Number(r.nurse_payable);
      const balance = cashHeld - nursePayable;
      const limit = Number(r.debt_limit);
      return {
        currencyCode: String(r.currency_code),
        cashHeld,
        nursePayable,
        owed: Math.max(0, balance),
        settledFromNurse: Number(r.from_nurse),
        paidToNurse: Number(r.to_nurse),
        balance,
        limit,
        blocked: r.settlement_required===true || (limit > 0 && balance > limit),
      };
    });
  }

  /** Re-evaluate this currency without changing the nurse's availability intent. */
  async enforce(q: Q, nurseId: string, currencyCode: string): Promise<boolean> {
    await q.query('SELECT recompute_nurse_financial_eligibility($1,$2)',[nurseId,currencyCode]);
    return (await this.balance(q,nurseId,currencyCode)).blocked;
  }
}
