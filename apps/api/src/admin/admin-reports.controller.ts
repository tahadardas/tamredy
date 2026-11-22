import { BadRequestException, Body, Controller, Get, Param, Post, Request, UseGuards } from '@nestjs/common';
import { IsIn, IsOptional, IsString, MaxLength } from 'class-validator';
import { AuthGuard, AuthRequest, requireAnyRole, requireRole } from '../auth/auth.guard.js';
import { DbService } from '../db/db.service.js';
import { conflict, missing } from '../common/errors.js';
import { nextWave } from '../common/states.js';
import { defaultPasswordFor, hashPassword } from '../auth/auth.service.js';

class CredentialDecisionDto {
  @IsIn(['APPROVE', 'REJECT', 'NEEDS_INFO']) decision!: 'APPROVE' | 'REJECT' | 'NEEDS_INFO';
  @IsOptional() @IsString() @MaxLength(500) reason?: string;
}

/** Admin console reads (A02, A04–A09) plus the credential decision workflow.
 *  All sensitive decisions write to audit_log in the same transaction. */
@Controller('v1/admin') @UseGuards(AuthGuard)
export class AdminReportsController {
  constructor(private readonly db: DbService) {}

  @Get('live') async live(@Request() r: AuthRequest) {
    requireRole(r.user!, 'ADMIN');
    const counts = await this.db.query(`SELECT
      (SELECT count(*)::int FROM nurses WHERE work_status='AVAILABLE' AND last_heartbeat_at>now()-interval '60 seconds') AS available,
      (SELECT count(*)::int FROM care_requests WHERE status='EN_ROUTE') AS en_route,
      (SELECT count(*)::int FROM care_requests WHERE status IN ('ARRIVED','IN_SERVICE')) AS in_visit,
      (SELECT count(*)::int FROM nurses WHERE availability_intent='AVAILABLE' AND (last_heartbeat_at IS NULL OR last_heartbeat_at<=now()-interval '60 seconds')) AS unresponsive`);
    const cases = await this.db.query(`SELECT cr.id,cr.status,cr.created_at,s.title_ar AS service_title
      FROM care_requests cr JOIN services s ON s.id=cr.service_id
      WHERE cr.status IN ('OFFERING','ASSIGNED','EN_ROUTE','ARRIVED','IN_SERVICE','ESCALATED')
      ORDER BY cr.created_at ASC LIMIT 20`);
    return {...counts.rows[0], cases: cases.rows};
  }

  @Get('dashboard/extras') async extras(@Request() r: AuthRequest) {
    requireRole(r.user!, 'ADMIN');
    const rev = await this.db.query(`SELECT coalesce(sum(price_amount),0) AS revenue_today FROM care_requests
      WHERE status='COMPLETED' AND updated_at>=date_trunc('day',now())`);
    const weekly = await this.db.query(`SELECT to_char(d::date,'YYYY-MM-DD') AS day,
      (SELECT count(*)::int FROM care_requests cr WHERE cr.created_at>=d AND cr.created_at<d+interval '1 day') AS bookings
      FROM generate_series(date_trunc('day',now())-interval '6 days',date_trunc('day',now()),interval '1 day') d ORDER BY d`);
    return {revenueToday: rev.rows[0].revenue_today, weekly: weekly.rows};
  }

  @Get('nurses/summary') async nursesSummary(@Request() r: AuthRequest) {
    requireRole(r.user!, 'ADMIN');
    const q = await this.db.query(`SELECT count(*)::int AS total,
      count(*) FILTER (WHERE EXISTS(SELECT 1 FROM nurse_credentials c WHERE c.nurse_id=n.id AND c.approved AND c.expires_at>now()))::int AS approved,
      count(*) FILTER (WHERE EXISTS(SELECT 1 FROM nurse_credentials c WHERE c.nurse_id=n.id AND c.review_status IN ('PENDING','NEEDS_INFO')))::int AS pending,
      count(*) FILTER (WHERE n.work_status='SUSPENDED')::int AS suspended FROM nurses n`);
    return q.rows[0];
  }

  @Get('credentials/pending') async pending(@Request() r: AuthRequest) {
    requireAnyRole(r.user!, ['ADMIN', 'CLINICAL_REVIEWER']);
    const q = await this.db.query(`SELECT c.id,c.nurse_id,c.license_ref,c.expires_at,c.review_status,c.submitted_at,c.document_id,c.doc_kind,n.nurse_no,u.display_name AS nurse_name,u.phone_e164,
      (SELECT array_agg(s.title_ar) FROM nurse_skills k JOIN services s ON s.id=k.service_id WHERE k.nurse_id=c.nurse_id) AS requested_skills
      FROM nurse_credentials c JOIN nurses n ON n.id=c.nurse_id JOIN users u ON u.id=n.user_id WHERE c.review_status IN ('PENDING','NEEDS_INFO') AND u.status<>'DELETED'
      ORDER BY c.submitted_at ASC LIMIT 50`);
    return {items: q.rows};
  }

  @Post('credentials/:id/decision') async decide(@Request() r: AuthRequest, @Param('id') id: string, @Body() dto: CredentialDecisionDto) {
    requireAnyRole(r.user!, ['ADMIN', 'CLINICAL_REVIEWER']);
    if (dto.decision !== 'APPROVE' && !dto.reason?.trim()) throw new BadRequestException({code: 'REASON_REQUIRED'});
    return this.db.transaction(async c => {
      const cur = await c.query('SELECT id,nurse_id,review_status,expires_at FROM nurse_credentials WHERE id=$1 FOR UPDATE', [id]);
      if (!cur.rowCount) missing();
      const row = cur.rows[0];
      if (!['PENDING', 'NEEDS_INFO'].includes(row.review_status)) conflict('CREDENTIAL_ALREADY_DECIDED');
      if (dto.decision === 'APPROVE' && new Date(row.expires_at) <= new Date()) conflict('LICENSE_EXPIRED');
      const status = dto.decision === 'APPROVE' ? 'APPROVED' : dto.decision === 'REJECT' ? 'REJECTED' : 'NEEDS_INFO';
      await c.query(`UPDATE nurse_credentials SET review_status=$2,review_reason=$3,approved=$4,
        verified_at=CASE WHEN $4 THEN now() END,verified_by=CASE WHEN $4 THEN $5::uuid END WHERE id=$1`,
        [id, status, dto.reason ?? null, dto.decision === 'APPROVE', r.user!.id]);
      if (dto.decision === 'APPROVE') await c.query('UPDATE nurses SET verified=true,updated_at=now() WHERE id=$1', [row.nurse_id]);
      await c.query(`INSERT INTO audit_log(actor_user_id,action,target_type,target_id,detail) VALUES($1,$2,'nurse_credential',$3,$4::jsonb)`,
        [r.user!.id, `credential.${status.toLowerCase()}`, id, JSON.stringify({reason: dto.reason ?? null, nurseId: row.nurse_id})]);
      // Approval makes the nurse's login ready: make sure the account has a password (initial one, to be changed at first login).
      let account: { phone: string; name: string | null; usingDefaultPassword: boolean; defaultPassword?: string } | null = null;
      if (dto.decision === 'APPROVE') {
        const u = (await c.query(`SELECT u.id,u.phone_e164,u.display_name,u.password_hash,u.must_change_password,u.status FROM nurses n JOIN users u ON u.id=n.user_id WHERE n.id=$1 FOR UPDATE OF u`, [row.nurse_id])).rows[0];
        if (u && u.status === 'ACTIVE') {
          let initial = !!u.must_change_password;
          const def = await defaultPasswordFor(this.db);
          if (!u.password_hash) {
            await c.query('UPDATE users SET password_hash=$2,must_change_password=true WHERE id=$1', [u.id, hashPassword(def)]);
            initial = true;
          }
          account = { phone: u.phone_e164, name: u.display_name, usingDefaultPassword: initial, ...(initial ? { defaultPassword: def } : {}) };
        }
      }
      return {id, reviewStatus: status, account};
    });
  }

  @Get('finance/summary') async finance(@Request() r: AuthRequest) {
    requireRole(r.user!, 'ADMIN');
    const q = await this.db.query(`SELECT
      coalesce(sum(cr.price_amount),0) AS visits_value,
      coalesce(sum(cr.price_amount*cr.commission_bps/10000),0) AS commission,
      coalesce(sum(cr.price_amount-cr.price_amount*cr.commission_bps/10000),0) AS nurse_due,
      (SELECT coalesce(sum(amount),0) FROM cash_collections WHERE status<>'CONFIRMED') AS pending_settlements
      FROM care_requests cr WHERE cr.status='COMPLETED' AND cr.updated_at>=date_trunc('month',now())`);
    return {...q.rows[0], period: 'MONTH_TO_DATE', source: 'ESTIMATE_NOT_LEDGER'};
  }

  @Get('finance/settlements') async settlements(@Request() r: AuthRequest) {
    requireRole(r.user!, 'ADMIN');
    const q = await this.db.query(`SELECT cc.id,cc.amount,cc.status,cc.created_at,'CASH' AS type,s.title_ar AS service_title
      FROM cash_collections cc JOIN visits v ON v.id=cc.visit_id
      JOIN request_assignments a ON a.id=v.assignment_id JOIN care_requests cr ON cr.id=a.request_id
      JOIN services s ON s.id=cr.service_id ORDER BY cc.created_at DESC LIMIT 50`);
    return {items: q.rows};
  }

  @Get('wallet/reconciliation') async wallet(@Request() r: AuthRequest) {
    requireRole(r.user!, 'ADMIN');
    // Wallet is a licensed-provider integration (ADR-006); nothing is stored here.
    return {providerConnected: false, mode: 'DISABLED', reason: 'LICENSED_PAYMENT_PROVIDER_REQUIRED', items: [], mismatches: 0};
  }

  @Get('reviews/summary') async reviews(@Request() r: AuthRequest) {
    requireRole(r.user!, 'ADMIN');
    const q = await this.db.query(`SELECT
      (SELECT round(avg(stars)::numeric,1) FROM visit_reviews WHERE reviewer_role='PATIENT') AS avg_rating,
      (SELECT count(*)::int FROM incidents WHERE status='OPEN') AS new_complaints,
      (SELECT count(*)::int FROM incidents WHERE status<>'RESOLVED' AND severity IN ('HIGH','CRITICAL')) AS safety_reports,
      (SELECT count(*)::int FROM incidents WHERE status='RESOLVED') AS resolved`);
    const items = await this.db.query(`SELECT id,request_id,severity,description,status,created_at FROM incidents ORDER BY created_at DESC LIMIT 20`);
    return {...q.rows[0], items: items.rows};
  }

  @Get('settings') settings(@Request() r: AuthRequest) {
    requireRole(r.user!, 'ADMIN');
    // Read-only view of compiled policy; editing requires RBAC + second approval (not built yet).
    return {
      editable: false,
      searchWaves: [1, 2, 3].map(n => ({wave: n, ...nextWave(n)})),
      currency: 'SYP_NEW', defaultCommissionBps: 2000, nurseVerificationRequired: true,
    };
  }
}
