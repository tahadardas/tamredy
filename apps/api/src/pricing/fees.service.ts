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
  /** balance > 0: the nurse must hand money to the company; balance < 0: the company owes the nurse. Only fully paid visits count. */
  async balance(q: Q, nurseId: string) {
    const r = (await q.query(`SELECT
      (SELECT coalesce(sum(cr.owed_to_company),0) FROM care_requests cr JOIN request_assignments a ON a.request_id=cr.id
         JOIN visits v ON v.assignment_id=a.id AND v.completed_at IS NOT NULL WHERE a.nurse_id=$1 AND cr.payment_status='PAID') AS owed,
      (SELECT coalesce(sum(amount),0) FROM nurse_settlements WHERE nurse_id=$1 AND direction='FROM_NURSE') AS from_nurse,
      (SELECT coalesce(sum(amount),0) FROM nurse_settlements WHERE nurse_id=$1 AND direction='TO_NURSE') AS to_nurse,
      (SELECT debt FROM (SELECT nurse_debt_limit AS debt FROM pricing_settings WHERE id=1) x) AS debt_limit`, [nurseId])).rows[0];
    const owed = Number(r.owed), fromNurse = Number(r.from_nurse), toNurse = Number(r.to_nurse), limit = Number(r.debt_limit);
    const balance = owed - fromNurse + toNurse;
    return { owed, settledFromNurse: fromNurse, paidToNurse: toNurse, balance, limit, blocked: limit > 0 && balance > limit };
  }

  /** Over the limit -> the nurse stops receiving requests until she settles with the company. */
  async enforce(q: Q, nurseId: string): Promise<boolean> {
    const b = await this.balance(q, nurseId);
    if (!b.blocked) return false;
    await q.query(`UPDATE nurses SET availability_intent='OFFLINE',work_status=CASE WHEN work_status IN ('AVAILABLE','PAUSED') THEN 'OFFLINE' ELSE work_status END,updated_at=now() WHERE id=$1`, [nurseId]);
    return true;
  }
}
