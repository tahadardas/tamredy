import { Injectable } from '@nestjs/common';
import { DbService } from '../db/db.service.js';
import { PoolClient, QueryResult, QueryResultRow } from 'pg';

export interface EligibilityResult {
  eligible: boolean;
  reason?: string;
}

interface Queryable {
  query: <T extends QueryResultRow = any>(sql: string, params?: unknown[]) => Promise<QueryResult<T>>;
}

@Injectable()
export class MarketplaceEligibilityService {
  constructor(private readonly db: DbService) {}

  private getRunner(client?: PoolClient): Queryable {
    return (client as unknown as Queryable) ?? this.db;
  }

  /**
   * Evaluates if a nurse is eligible to browse an open request.
   */
  async checkBrowseEligibility(
    nurseId: string,
    requestId: string,
    client?: PoolClient,
  ): Promise<EligibilityResult> {
    const dbClient = this.getRunner(client);

    // 1. Verify nurse status and verified licence
    const nurseRes = await dbClient.query(
      `SELECT n.id, n.user_id, n.verified, n.work_status
       FROM nurses n
       JOIN users u ON u.id = n.user_id
       WHERE n.id = $1 AND u.status = 'ACTIVE'`,
      [nurseId],
    );
    if (!nurseRes.rowCount || !nurseRes.rows[0].verified) {
      return { eligible: false, reason: 'NURSE_NOT_VERIFIED' };
    }
    const nurseUserId = nurseRes.rows[0].user_id;

    // 2. Fetch request details and requester ID
    const reqRes = await dbClient.query(
      `SELECT cr.id, cr.requester_user_id, cr.status, cr.open_expires_at, cr.booking_mode
       FROM care_requests cr
       WHERE cr.id = $1`,
      [requestId],
    );
    if (!reqRes.rowCount) {
      return { eligible: false, reason: 'REQUEST_NOT_FOUND' };
    }
    const req = reqRes.rows[0];
    if (req.status !== 'OPEN_FOR_PROPOSALS') {
      return { eligible: false, reason: 'REQUEST_NOT_OPEN' };
    }
    if (req.open_expires_at && new Date(req.open_expires_at) <= new Date()) {
      return { eligible: false, reason: 'REQUEST_EXPIRED' };
    }

    // 3. Verify absence of mutual block
    const blockRes = await dbClient.query(
      `SELECT 1 FROM user_blocks
       WHERE ((blocker_user_id = $1 AND blocked_user_id = $2)
          OR (blocker_user_id = $2 AND blocked_user_id = $1))
         AND revoked_at IS NULL
       LIMIT 1`,
      [nurseUserId, req.requester_user_id],
    );
    if (blockRes.rowCount) {
      return { eligible: false, reason: 'USER_BLOCKED' };
    }

    // 4. Verify nurse has approved skills for ALL request services
    const skillsRes = await dbClient.query(
      `SELECT cri.service_id
       FROM care_request_items cri
       WHERE cri.request_id = $1
         AND NOT EXISTS (
           SELECT 1 FROM nurse_skills ns
           WHERE ns.nurse_id = $2
             AND ns.service_id = cri.service_id
             AND ns.approved = true
         )`,
      [requestId, nurseId],
    );
    if (skillsRes.rowCount && skillsRes.rowCount > 0) {
      return { eligible: false, reason: 'MISSING_REQUIRED_SKILLS' };
    }

    return { eligible: true };
  }

  /**
   * Evaluates if a nurse can submit a readiness proposal.
   */
  async checkProposalEligibility(
    nurseId: string,
    requestId: string,
    proposedArrivalAt: Date,
    estimatedMinutes: number,
    client?: PoolClient,
  ): Promise<EligibilityResult> {
    const dbClient = this.getRunner(client);

    // First check browse eligibility
    const browse = await this.checkBrowseEligibility(nurseId, requestId, client);
    if (!browse.eligible) return browse;

    const now = new Date();
    if (proposedArrivalAt.getTime() < now.getTime() - 60000) {
      return { eligible: false, reason: 'ARRIVAL_TIME_IN_PAST' };
    }

    // Check latest acceptable arrival on request
    const reqRes = await dbClient.query(
      `SELECT latest_acceptable_arrival_at FROM care_requests WHERE id = $1`,
      [requestId],
    );
    const latestArrival = reqRes.rows[0]?.latest_acceptable_arrival_at;
    if (latestArrival && proposedArrivalAt.getTime() > new Date(latestArrival).getTime()) {
      return { eligible: false, reason: 'ARRIVAL_TIME_NOT_ACCEPTABLE' };
    }

    // Check concurrent proposals cap (e.g. max 5 active proposals)
    const policy = (await dbClient.query(
      `SELECT value FROM app_settings WHERE key = 'booking_policies'`,
    )).rows[0]?.value;
    const maxConcurrent = Number(policy?.maxConcurrentProposalsPerNurse) || 5;

    const countRes = await dbClient.query(
      `SELECT count(*)::int AS cnt
       FROM marketplace_proposals
       WHERE nurse_id = $1 AND status = 'PENDING' AND expires_at > now()`,
      [nurseId],
    );
    if ((countRes.rows[0]?.cnt ?? 0) >= maxConcurrent) {
      return { eligible: false, reason: 'MAX_CONCURRENT_PROPOSALS_EXCEEDED' };
    }

    // Check schedule overlap with 30-minute travel buffer
    const serviceEnd = new Date(proposedArrivalAt.getTime() + estimatedMinutes * 60000);
    const conflict = await this.hasScheduleConflict(nurseId, proposedArrivalAt, serviceEnd, client);
    if (conflict) {
      return { eligible: false, reason: 'NURSE_SCHEDULE_CONFLICT' };
    }

    // Check financial settlement restriction
    const duesRes = await dbClient.query(
      `SELECT n.dues_ceiling_amount, n.current_dues_amount
       FROM nurses n
       WHERE n.id = $1`,
      [nurseId],
    ).catch(() => ({ rows: [] }));
    if (duesRes.rows.length > 0) {
      const ceiling = Number(duesRes.rows[0].dues_ceiling_amount);
      const dues = Number(duesRes.rows[0].current_dues_amount);
      if (ceiling > 0 && dues >= ceiling) {
        return { eligible: false, reason: 'SETTLEMENT_REQUIRED' };
      }
    }

    return { eligible: true };
  }

  /**
   * Checks if a proposed visit time window conflicts with active visits or calendar blocks.
   * Includes a 30-minute travel buffer before and after.
   */
  async hasScheduleConflict(
    nurseId: string,
    startTime: Date,
    endTime: Date,
    client?: PoolClient,
  ): Promise<boolean> {
    const dbClient = this.getRunner(client);
    const bufferMinutes = 30;
    const windowStart = new Date(startTime.getTime() - bufferMinutes * 60000).toISOString();
    const windowEnd = new Date(endTime.getTime() + bufferMinutes * 60000).toISOString();

    // 1. Check nurse calendar blocks
    const calRes = await dbClient.query(
      `SELECT 1 FROM nurse_calendar_blocks
       WHERE nurse_id = $1
         AND (start_time < $3::timestamptz AND end_time > $2::timestamptz)
       LIMIT 1`,
      [nurseId, windowStart, windowEnd],
    ).catch(() => ({ rowCount: 0 }));
    if (calRes.rowCount && calRes.rowCount > 0) return true;

    // 2. Check active assignments
    const assignRes = await dbClient.query(
      `SELECT 1 FROM request_assignments ra
       JOIN care_requests cr ON cr.id = ra.request_id
       WHERE ra.nurse_id = $1
         AND ra.status = 'ACTIVE'
         AND cr.status IN ('ASSIGNED', 'EN_ROUTE', 'ARRIVED', 'IN_SERVICE')
         AND (
           coalesce(ra.expected_arrival_at, ra.created_at) < $3::timestamptz
           AND coalesce(ra.expected_arrival_at, ra.created_at) + interval '90 minutes' > $2::timestamptz
         )
       LIMIT 1`,
      [nurseId, windowStart, windowEnd],
    ).catch(() => ({ rowCount: 0 }));
    if (assignRes.rowCount && assignRes.rowCount > 0) return true;

    return false;
  }
}
