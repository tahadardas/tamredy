import { Controller, Get, Request, UseGuards } from '@nestjs/common';
import { AuthGuard, AuthRequest, requireRole } from '../auth/auth.guard.js';
import { DbService } from '../db/db.service.js';
import { missing } from '../common/errors.js';
import { DuesService } from '../pricing/fees.service.js';

/** Read-only nurse views used by N01, N06, N07 and N09. Amounts are computed
 *  from completed requests; no real balance exists until a licensed provider
 *  and a balanced ledger are in place. */
@Controller('v1/nurse/me') @UseGuards(AuthGuard)
export class NurseMeController {
  constructor(private readonly db: DbService, private readonly dues: DuesService = new DuesService()) {}

  @Get('summary') async summary(@Request() r: AuthRequest) {
    requireRole(r.user!, 'NURSE');
    const q = await this.db.query(`SELECT n.id,n.availability_intent,n.work_status,
      (SELECT count(*)::int FROM request_offers o WHERE o.nurse_id=n.id AND o.created_at>=date_trunc('day',now())) AS requests_today,
      (SELECT count(*)::int FROM request_assignments a JOIN visits v ON v.assignment_id=a.id
         WHERE a.nurse_id=n.id AND v.completed_at>=date_trunc('day',now())) AS completed_today,
      (SELECT count(*)::int FROM request_assignments a JOIN visits v ON v.assignment_id=a.id
         WHERE a.nurse_id=n.id AND v.completed_at>=date_trunc('month',now())) AS completed_month,
      (SELECT round(avg(vr.stars)::numeric,1) FROM visit_reviews vr JOIN visits v ON v.id=vr.visit_id
         JOIN request_assignments a ON a.id=v.assignment_id WHERE a.nurse_id=n.id AND vr.reviewer_role='PATIENT') AS avg_rating,
      (SELECT CASE WHEN count(*)=0 THEN NULL ELSE round(100.0*count(*) FILTER (WHERE cr.status='COMPLETED')/count(*)) END
         FROM request_assignments a JOIN care_requests cr ON cr.id=a.request_id WHERE a.nurse_id=n.id) AS completion_rate
      FROM nurses n WHERE n.user_id=$1`, [r.user!.id]);
    if (!q.rowCount) missing();
    return q.rows[0];
  }

  @Get('earnings') async earnings(@Request() r: AuthRequest) {
    requireRole(r.user!, 'NURSE');
    const n = await this.db.query('SELECT id FROM nurses WHERE user_id=$1', [r.user!.id]);
    if (!n.rowCount) missing();
    const nurseId = n.rows[0].id;
    const totals = await this.db.query(`SELECT count(*)::int AS visits,
        coalesce(sum(cr.price_amount),0) AS gross,
        coalesce(sum(cr.price_amount*cr.commission_bps/10000),0) AS commission,
        coalesce(sum(cr.price_amount-cr.price_amount*cr.commission_bps/10000),0) AS net_due,
        cr.currency_code
      FROM request_assignments a JOIN visits v ON v.assignment_id=a.id
      JOIN care_requests cr ON cr.id=a.request_id
      WHERE a.nurse_id=$1 AND v.completed_at>=date_trunc('month',now()) AND cr.status='COMPLETED'
      GROUP BY cr.currency_code`, [nurseId]);
    const recent = await this.db.query(`SELECT s.title_ar AS title,v.completed_at,
        (cr.price_amount-cr.price_amount*cr.commission_bps/10000) AS nurse_share,cc.status AS cash_status
      FROM request_assignments a JOIN visits v ON v.assignment_id=a.id
      JOIN care_requests cr ON cr.id=a.request_id JOIN services s ON s.id=cr.service_id
      LEFT JOIN cash_collections cc ON cc.visit_id=v.id
      WHERE a.nurse_id=$1 AND v.completed_at IS NOT NULL
      ORDER BY v.completed_at DESC LIMIT 10`, [nurseId]);
    return {month: totals.rows[0] ?? {visits: 0, gross: '0', commission: '0', net_due: '0'}, recent: recent.rows, settlementMode: 'ESTIMATE_ONLY'};
  }

  /** What the nurse owes the company (or is owed) from cash collected, and the settlement history. */
  @Get('dues') async duesView(@Request() r: AuthRequest) {
    requireRole(r.user!, 'NURSE');
    const n = await this.db.query('SELECT id FROM nurses WHERE user_id=$1', [r.user!.id]);
    if (!n.rowCount) missing();
    const history = await this.db.query(`SELECT direction,amount,note,created_at FROM nurse_settlements WHERE nurse_id=$1 ORDER BY created_at DESC LIMIT 20`, [n.rows[0].id]);
    return { ...(await this.dues.balance(this.db, n.rows[0].id)), history: history.rows };
  }

  @Get('profile') async profile(@Request() r: AuthRequest) {
    requireRole(r.user!, 'NURSE');
    const n = await this.db.query('SELECT id,verified FROM nurses WHERE user_id=$1', [r.user!.id]);
    if (!n.rowCount) missing();
    const id = n.rows[0].id;
    const [creds, skills] = await Promise.all([
      this.db.query(`SELECT id,approved,review_status,expires_at FROM nurse_credentials WHERE nurse_id=$1 ORDER BY submitted_at DESC`, [id]),
      this.db.query(`SELECT s.id,s.title_ar FROM nurse_skills k JOIN services s ON s.id=k.service_id WHERE k.nurse_id=$1 AND k.approved=true AND s.active=true`, [id]),
    ]);
    return {verified: n.rows[0].verified, credentials: creds.rows, skills: skills.rows};
  }
}
