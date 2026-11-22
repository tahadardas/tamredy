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

  @Get('readiness') async readiness(@Request() r: AuthRequest) {
    requireRole(r.user!, 'NURSE');
    const n = await this.db.query(`SELECT n.id, n.verified, n.availability_intent, n.work_status, n.last_heartbeat_at,
        EXTRACT(EPOCH FROM (now() - n.last_heartbeat_at))::int AS heartbeat_age_s,
        nl.accuracy_m, EXTRACT(EPOCH FROM (now() - nl.recorded_at))::int AS location_age_s
      FROM nurses n
      LEFT JOIN nurse_locations nl ON nl.nurse_id = n.id
      WHERE n.user_id = $1`, [r.user!.id]);
    if (!n.rowCount) missing();
    const row = n.rows[0];
    const nurseId = row.id;

    // Check credentials
    const creds = await this.db.query(`SELECT 1 FROM nurse_credentials WHERE nurse_id=$1 AND approved=true AND expires_at>now()`, [nurseId]);
    const credentialsApproved = (creds.rowCount ?? 0) > 0;

    // Check skills
    const skills = await this.db.query(`SELECT s.id, s.title_ar FROM nurse_skills ns JOIN services s ON s.id=ns.service_id WHERE ns.nurse_id=$1 AND ns.approved=true AND s.active=true`, [nurseId]);
    const skillsCount = skills.rowCount ?? 0;

    // Check settlement dues
    const dues = await this.dues.balance(this.db, nurseId);
    const settlementBlocked = dues.blocked === true;

    // Check active assignment
    const active = await this.db.query(`SELECT 1 FROM request_assignments a JOIN care_requests cr ON cr.id=a.request_id WHERE a.nurse_id=$1 AND a.status='ACTIVE' AND cr.status IN ('ASSIGNED','EN_ROUTE','ARRIVED','IN_SERVICE')`, [nurseId]);
    const hasActiveAssignment = (active.rowCount ?? 0) > 0;

    const isHeartbeatFresh = row.heartbeat_age_s !== null && row.heartbeat_age_s <= 60;
    const isLocationFresh = row.location_age_s !== null && row.location_age_s <= 120 && (row.accuracy_m ?? 999) <= 150;

    const unmet: string[] = [];
    let calculatedStatus = 'READY';

    if (hasActiveAssignment || ['RESERVED', 'EN_ROUTE', 'ARRIVED', 'IN_SERVICE'].includes(row.work_status)) {
      calculatedStatus = 'BUSY';
    } else if (row.availability_intent !== 'AVAILABLE') {
      calculatedStatus = 'OFFLINE';
    } else if (!row.verified) {
      calculatedStatus = 'VERIFICATION_REQUIRED';
      unmet.push('الحساب بانتظار الاعتماد الإداري النهائي');
    } else if (!credentialsApproved) {
      calculatedStatus = 'VERIFICATION_REQUIRED';
      unmet.push('الترخيص المهني بحاجة إلى اعتماد أو منتهي الصلاحية');
    } else if (skillsCount === 0) {
      calculatedStatus = 'SKILLS_REQUIRED';
      unmet.push('لم يتم اعتماد أي خدمات تمريضية مؤهل لتنفيذها');
    } else if (settlementBlocked) {
      calculatedStatus = 'SETTLEMENT_BLOCKED';
      unmet.push('استقبال الطلبات موقوف لتجاوز سقف المستحقات النقدية');
    } else if (row.location_age_s === null) {
      calculatedStatus = 'LOCATION_REQUIRED';
      unmet.push('يرجى تمكين أذونات وخدمة الموقع الجغرافي');
    } else if (!isLocationFresh) {
      calculatedStatus = 'LOCATION_STALE';
      unmet.push(row.accuracy_m > 150 ? 'دقة الموقع الحالية منخفضة جداً (> 150م)' : 'إحداثيات الموقع قديمة وغير متزامنة');
    } else if (!isHeartbeatFresh) {
      calculatedStatus = 'CONNECTION_LOST';
      unmet.push('الاتصال بالخادم غير مستقر أو انقطع نبض الاتصال');
    }

    const canReceiveOffers = calculatedStatus === 'READY';

    return {
      status: calculatedStatus,
      canReceiveOffers,
      availabilityIntent: row.availability_intent,
      workStatus: row.work_status,
      verified: row.verified,
      credentialsApproved,
      skillsCount,
      approvedSkills: skills.rows.map(s => s.title_ar),
      settlementBlocked,
      hasActiveAssignment,
      lastHeartbeatSecondsAgo: row.heartbeat_age_s,
      lastLocationSecondsAgo: row.location_age_s,
      locationAccuracyMeters: row.accuracy_m,
      isLocationFresh,
      isHeartbeatFresh,
      unmetRequirements: unmet,
    };
  }

  @Get('active-assignment') async activeAssignment(@Request() r: AuthRequest) {
    requireRole(r.user!, 'NURSE');
    const n = await this.db.query('SELECT id,verified,availability_intent,work_status FROM nurses WHERE user_id=$1', [r.user!.id]);
    if (!n.rowCount) missing();
    const nurse = n.rows[0];
    const q = await this.db.query(`
      SELECT a.id AS assignment_id, a.status AS assignment_status, a.accepted_at AS assigned_at,
        cr.id AS request_id, cr.status AS request_status, cr.address_text, cr.price_amount, cr.currency_code, cr.commission_bps,
        ST_Y(cr.location::geometry) AS patient_lat, ST_X(cr.location::geometry) AS patient_lng,
        s.id AS service_id, s.title_ar AS service_title, s.code AS service_code, s.requires_prescription,
        b.display_name AS beneficiary_name,
        u.display_name AS patient_name, u.phone_e164 AS patient_phone
      FROM request_assignments a
      JOIN care_requests cr ON cr.id = a.request_id
      JOIN services s ON s.id = cr.service_id
      JOIN beneficiaries b ON b.id = cr.beneficiary_id
      JOIN users u ON u.id = cr.requester_user_id
      WHERE a.nurse_id = $1 AND a.status = 'ACTIVE'
        AND cr.status IN ('ASSIGNED', 'EN_ROUTE', 'ARRIVED', 'IN_SERVICE')
      ORDER BY a.accepted_at DESC LIMIT 1
    `, [nurse.id]);

    if (!q.rowCount) {
      return {
        hasActive: false,
        verified: nurse.verified,
        availability: nurse.availability_intent,
        workStatus: nurse.work_status,
        assignment: null,
      };
    }
    return {
      hasActive: true,
      verified: nurse.verified,
      availability: nurse.availability_intent,
      workStatus: nurse.work_status,
      assignment: q.rows[0],
    };
  }
}
