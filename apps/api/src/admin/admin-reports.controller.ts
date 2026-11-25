import { BadRequestException, Body, Controller, Get, Param, Post, Request, UseGuards } from '@nestjs/common';
import { IsIn, IsOptional, IsString, MaxLength } from 'class-validator';
import { AuthGuard, AuthRequest, requireAnyRole, requireRole } from '../auth/auth.guard.js';
import { DbService } from '../db/db.service.js';
import { conflict, missing } from '../common/errors.js';
import { nextWave } from '../common/states.js';
import { generatePassword, hashPassword } from '../auth/auth.service.js';

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

  @Get('bi/telemetry') async biTelemetry(@Request() r: AuthRequest) {
    requireRole(r.user!, 'ADMIN');

    // Financials & request completion
    const fin = (await this.db.query(`
      SELECT coalesce(sum(price_amount), 0)::bigint AS gmv,
             coalesce(sum(price_amount * commission_bps / 10000), 0)::bigint AS net_revenue,
             count(*) FILTER (WHERE status = 'COMPLETED')::int AS completed_count,
             count(*) FILTER (WHERE status IN ('COMPLETED', 'CANCELLED', 'UNFULFILLED', 'EXPIRED'))::int AS finished_count,
             count(*)::int AS total_requests
      FROM care_requests
    `)).rows[0];

    const gmv = Number(fin.gmv || 0);
    const netRevenue = Number(fin.net_revenue || 0);
    const completedCount = Number(fin.completed_count || 0);
    const finishedCount = Number(fin.finished_count || 0);
    const fulfillmentPct = finishedCount > 0 ? Math.round((completedCount / finishedCount) * 1000) / 10 : (completedCount > 0 ? 100 : 0);

    // Rebooking rate
    const rebooking = (await this.db.query(`
      WITH p AS (
        SELECT requester_user_id, count(*)::int AS cnt
        FROM care_requests
        GROUP BY requester_user_id
      )
      SELECT count(*) FILTER (WHERE cnt > 1)::int AS repeat_users,
             count(*)::int AS total_users
      FROM p
    `)).rows[0];
    const totalUsers = Number(rebooking.total_users || 0);
    const repeatUsers = Number(rebooking.repeat_users || 0);
    const rebookingPct = totalUsers > 0 ? Math.round((repeatUsers / totalUsers) * 1000) / 10 : 0;

    // Request distribution by booking mode
    const modes = (await this.db.query(`
      SELECT coalesce(booking_mode, 'INSTANT') AS mode, count(*)::int AS count
      FROM care_requests
      GROUP BY coalesce(booking_mode, 'INSTANT')
    `)).rows;

    let instantCount = 0;
    let scheduledCount = 0;
    let openCount = 0;
    for (const m of modes) {
      if (m.mode === 'INSTANT') instantCount += Number(m.count);
      else if (m.mode === 'SCHEDULED') scheduledCount += Number(m.count);
      else if (m.mode === 'OPEN') openCount += Number(m.count);
    }
    const modeSum = instantCount + scheduledCount + openCount;
    const instantPct = modeSum > 0 ? Math.round((instantCount / modeSum) * 100) : 0;
    const scheduledPct = modeSum > 0 ? Math.round((scheduledCount / modeSum) * 100) : 0;
    const openPct = modeSum > 0 ? Math.round((openCount / modeSum) * 100) : 0;

    // Retention: favorites and packages
    const favCount = Number((await this.db.query(`SELECT count(*)::int AS cnt FROM patient_favorite_nurses`).catch(() => ({ rows: [{ cnt: 0 }] }))).rows[0].cnt);
    const activePlans = Number((await this.db.query(`SELECT count(*)::int AS cnt FROM care_plans WHERE status = 'ACTIVE'`).catch(() => ({ rows: [{ cnt: 0 }] }))).rows[0].cnt);
    const activePackages = Number((await this.db.query(`SELECT count(*)::int AS cnt FROM user_package_grants WHERE remaining_visits > 0`).catch(() => ({ rows: [{ cnt: 0 }] }))).rows[0].cnt);

    // Direct nurse request acceptance rate
    const directReqs = (await this.db.query(`
      SELECT count(*)::int AS total_direct,
             count(*) FILTER (WHERE status IN ('ASSIGNED', 'EN_ROUTE', 'ARRIVED', 'IN_SERVICE', 'COMPLETED'))::int AS accepted_direct
      FROM care_requests
      WHERE dispatch_mode = 'DIRECT_NURSE'
    `).catch(() => ({ rows: [{ total_direct: 0, accepted_direct: 0 }] }))).rows[0];
    const totalDirect = Number(directReqs.total_direct || 0);
    const acceptedDirect = Number(directReqs.accepted_direct || 0);
    const directAcceptPct = totalDirect > 0 ? Math.round((acceptedDirect / totalDirect) * 1000) / 10 : 0;

    const voiceQuality = (await this.db.query(`SELECT
      count(*) FILTER (WHERE call_status='CONNECTED')::int AS connected_calls,
      count(*) FILTER (WHERE call_status IN ('FAILED','MISSED'))::int AS failed_or_missed_calls,
      round(avg(extract(epoch FROM (connected_at-ringing_at))) FILTER (WHERE connected_at IS NOT NULL)::numeric,2) AS avg_setup_seconds,
      round((SELECT avg(rtt_ms) FROM voice_call_quality_samples WHERE created_at>now()-interval '30 days')::numeric,2) AS avg_rtt_ms,
      round((SELECT avg(jitter_ms) FROM voice_call_quality_samples WHERE created_at>now()-interval '30 days')::numeric,2) AS avg_jitter_ms,
      round((SELECT avg(packet_loss_percent) FROM voice_call_quality_samples WHERE created_at>now()-interval '30 days')::numeric,2) AS avg_packet_loss_percent,
      (SELECT count(*)::int FROM voice_call_quality_samples WHERE turn_used AND created_at>now()-interval '30 days') AS turn_samples
      FROM voice_call_sessions WHERE created_at>now()-interval '30 days'`)).rows[0];

    return {
      gmv,
      netRevenue,
      fulfillmentPct,
      rebookingPct,
      totalRequests: Number(fin.total_requests || 0),
      distribution: {
        instantPct,
        scheduledPct,
        openPct,
        instantCount,
        scheduledCount,
        openCount,
      },
      retention: {
        favoritesCount: favCount,
        directAcceptPct,
        activePlansCount: activePlans,
        activePackagesCount: activePackages,
      },
      voiceQuality,
    };
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
          let temporaryPassword: string | undefined;
          if (!u.password_hash) {
            temporaryPassword = generatePassword(20);
            await c.query(`UPDATE users SET password_hash=$2,must_change_password=true,
              temporary_password_expires_at=statement_timestamp()+interval '30 minutes' WHERE id=$1`,
            [u.id,hashPassword(temporaryPassword)]);
          }
          account = { phone: u.phone_e164, name: u.display_name, usingDefaultPassword: !!temporaryPassword,
            ...(temporaryPassword ? { defaultPassword: temporaryPassword } : {}) };
        }
      }
      return {id, reviewStatus: status, account};
    });
  }

  @Get('finance/summary') async finance(@Request() r: AuthRequest) {
    requireRole(r.user!, 'ADMIN');
    const q = await this.db.query(`SELECT
      coalesce(sum(i.total_amount),0) AS visits_value,
      coalesce((SELECT sum(e.credit_amount-e.debit_amount) FROM financial_ledger_entries e
        JOIN financial_transactions t ON t.id=e.transaction_id
        WHERE e.account_id='COMMISSION_REVENUE' AND t.posted_at>=date_trunc('month',now())),0) AS commission,
      coalesce((SELECT sum(e.credit_amount-e.debit_amount) FROM financial_ledger_entries e
        JOIN financial_transactions t ON t.id=e.transaction_id
        WHERE e.account_id LIKE 'NURSE_PAYABLE:%' AND t.posted_at>=date_trunc('month',now())),0) AS nurse_due,
      (SELECT coalesce(sum(i2.total_amount+i2.tip_amount-i2.paid_amount),0) FROM invoices i2
        WHERE i2.status IN ('ISSUED','PARTIALLY_PAID')) AS pending_settlements
      FROM invoices i WHERE i.issued_at>=date_trunc('month',now())`);
    return {...q.rows[0], period: 'MONTH_TO_DATE', source: 'FINANCIAL_LEDGER'};
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

  @Get('reviews/items') async reviewsItems(@Request() r: AuthRequest) {
    requireRole(r.user!, 'ADMIN');
    const items = await this.db.query(`
      SELECT vr.id, vr.visit_id, vr.reviewer_role, vr.stars, vr.behavior_notes, vr.created_at,
        cr.id AS request_id, s.title_ar AS service_title,
        patient_u.display_name AS patient_name, '***'||right(patient_u.phone_e164,4) AS patient_phone,
        nurse_u.display_name AS nurse_name, '***'||right(nurse_u.phone_e164,4) AS nurse_phone
      FROM visit_reviews vr
      JOIN visits v ON v.id = vr.visit_id
      JOIN request_assignments a ON a.id = v.assignment_id
      JOIN care_requests cr ON cr.id = a.request_id
      JOIN services s ON s.id = cr.service_id
      JOIN users patient_u ON patient_u.id = cr.requester_user_id
      JOIN nurses n ON n.id = a.nurse_id
      JOIN users nurse_u ON nurse_u.id = n.user_id
      ORDER BY vr.created_at DESC LIMIT 50
    `);
    return { items: items.rows };
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
