import { Injectable } from '@nestjs/common';
import type { PoolClient, QueryResult, QueryResultRow } from 'pg';
import { DbService } from '../db/db.service.js';

export type EligibilityContext = 'BROWSE' | 'OFFER' | 'PROPOSAL' | 'ACCEPT' | 'ASSIGN' | 'START';

export interface EligibilityReason {
  code: string;
  messageKey: string;
  details?: Record<string, unknown>;
}

export interface NurseEligibilityResult {
  eligible: boolean;
  reasons: EligibilityReason[];
}

interface Queryable {
  query<T extends QueryResultRow = QueryResultRow>(sql: string, params?: unknown[]): Promise<QueryResult<T>>;
}

interface EligibilityOptions {
  context: EligibilityContext;
  proposedStart?: Date;
  proposedEnd?: Date;
  excludeRequestId?: string;
}

const reason = (code: string, details?: Record<string, unknown>): EligibilityReason => ({
  code,
  messageKey: `eligibility.${code.toLowerCase()}`,
  ...(details ? { details } : {}),
});

@Injectable()
export class NurseEligibilityEngine {
  constructor(private readonly db: DbService) {}

  private runner(client?: PoolClient): Queryable {
    return client ?? this.db;
  }

  async evaluate(
    nurseId: string,
    requestId: string,
    options: EligibilityOptions,
    client?: PoolClient,
  ): Promise<NurseEligibilityResult> {
    const runner = this.runner(client);
    const facts = (await runner.query(`
      SELECT n.id AS nurse_id, n.user_id AS nurse_user_id, n.verified,
        n.work_status, n.availability_intent, n.last_heartbeat_at,
        u.status AS account_status, cr.id AS request_id, cr.requester_user_id,
        cr.status AS request_status, cr.booking_mode, cr.clinical_approval_status, cr.open_expires_at,
        cr.latest_acceptable_arrival_at, cr.search_max_heartbeat_seconds,
        cr.search_max_location_seconds, cr.search_max_accuracy_meters,
        cr.search_radius_meters, nl.recorded_at AS location_recorded_at,
        nl.accuracy_m AS location_accuracy_m,
        CASE WHEN nl.location IS NULL THEN NULL ELSE ST_Distance(nl.location, cr.location) END AS distance_m,
        EXISTS (SELECT 1 FROM nurse_credentials nc WHERE nc.nurse_id=n.id
          AND nc.approved AND nc.expires_at>statement_timestamp()) AS has_valid_credential,
        NOT EXISTS (SELECT 1 FROM care_request_items cri WHERE cri.request_id=cr.id
          AND NOT EXISTS (SELECT 1 FROM nurse_skills ns WHERE ns.nurse_id=n.id
            AND ns.service_id=cri.service_id AND ns.approved)) AS has_all_skills,
        EXISTS (SELECT 1 FROM user_blocks ub
          WHERE ((ub.blocker_user_id=n.user_id AND ub.blocked_user_id=cr.requester_user_id)
             OR (ub.blocker_user_id=cr.requester_user_id AND ub.blocked_user_id=n.user_id))
            AND ub.revoked_at IS NULL) AS mutually_blocked,
        EXISTS (SELECT 1 FROM request_assignments ra
          JOIN care_requests active_request ON active_request.id=ra.request_id
          WHERE ra.nurse_id=n.id AND ra.status='ACTIVE'
            AND active_request.status IN ('ASSIGNED','EN_ROUTE','ARRIVED','IN_SERVICE')
            AND active_request.id<>cr.id) AS has_active_execution,
        coalesce(n.dues_ceiling_amount, 0) AS dues_ceiling_amount,
        greatest(coalesce((SELECT sum(CASE
          WHEN e.account_id='CASH_HELD_BY_NURSE:'||n.id::text THEN e.debit_amount-e.credit_amount
          WHEN e.account_id='NURSE_PAYABLE:'||n.id::text THEN e.debit_amount-e.credit_amount
          ELSE 0 END) FROM financial_ledger_entries e
          WHERE e.account_id IN ('CASH_HELD_BY_NURSE:'||n.id::text,'NURSE_PAYABLE:'||n.id::text)),0),0) AS current_dues_amount,
        nfa.financial_model, nfa.credit_limit, nfa.prepaid_balance, nfa.reserved_balance
      FROM nurses n
      JOIN users u ON u.id=n.user_id
      CROSS JOIN care_requests cr
      LEFT JOIN nurse_locations nl ON nl.nurse_id=n.id
      LEFT JOIN nurse_financial_accounts nfa ON nfa.nurse_id=n.id
      WHERE n.id=$1 AND cr.id=$2
    `, [nurseId, requestId])).rows[0];

    if (!facts) return { eligible: false, reasons: [reason('NURSE_OR_REQUEST_NOT_FOUND')] };

    const reasons: EligibilityReason[] = [];
    if (facts.account_status !== 'ACTIVE') reasons.push(reason('NURSE_ACCOUNT_INACTIVE'));
    if (!facts.verified) reasons.push(reason('NURSE_NOT_VERIFIED'));
    if (!facts.has_valid_credential) reasons.push(reason('LICENSE_MISSING_OR_EXPIRED'));
    if (!facts.has_all_skills) reasons.push(reason('MISSING_REQUIRED_SKILLS'));
    if (facts.mutually_blocked) reasons.push(reason('USER_BLOCKED'));
    if (!['NOT_REQUIRED','APPROVED'].includes(facts.clinical_approval_status)) {
      reasons.push(reason('CLINICAL_APPROVAL_REQUIRED'));
    }

    const expectedStatuses: Record<EligibilityContext, string[]> = {
      BROWSE: ['OPEN_FOR_PROPOSALS'], OFFER: ['OFFERING'], PROPOSAL: ['OPEN_FOR_PROPOSALS'],
      ACCEPT: ['OFFERING', 'OPEN_FOR_PROPOSALS', 'SCHEDULED'],
      ASSIGN: ['OFFERING', 'OPEN_FOR_PROPOSALS', 'SCHEDULED'],
      START: ['ASSIGNED', 'EN_ROUTE', 'ARRIVED'],
    };
    if (!expectedStatuses[options.context].includes(facts.request_status)) {
      reasons.push(reason('REQUEST_NOT_ELIGIBLE_FOR_CONTEXT', {
        context: options.context, requestStatus: facts.request_status,
      }));
    }
    if (facts.open_expires_at && ['BROWSE', 'PROPOSAL', 'ACCEPT'].includes(options.context)
      && new Date(facts.open_expires_at) <= new Date()) reasons.push(reason('REQUEST_EXPIRED'));

    const requiresLiveReadiness = options.context === 'OFFER' || options.context === 'START'
      || (facts.booking_mode === 'INSTANT' && ['ACCEPT', 'ASSIGN'].includes(options.context));
    if (requiresLiveReadiness) {
      const permittedWorkStatuses = options.context === 'START' ? ['EN_ROUTE', 'IN_SERVICE'] : ['AVAILABLE'];
      if (facts.availability_intent !== 'AVAILABLE' || !permittedWorkStatuses.includes(facts.work_status)) {
        reasons.push(reason('NURSE_NOT_AVAILABLE'));
      }
      if (!facts.last_heartbeat_at || Date.now() - new Date(facts.last_heartbeat_at).getTime()
        > Number(facts.search_max_heartbeat_seconds ?? 120) * 1000) reasons.push(reason('HEARTBEAT_STALE'));
      if (!facts.location_recorded_at) {
        reasons.push(reason('LOCATION_REQUIRED'));
      } else {
        if (Date.now() - new Date(facts.location_recorded_at).getTime()
          > Number(facts.search_max_location_seconds ?? 120) * 1000) reasons.push(reason('LOCATION_STALE'));
        if (Number(facts.location_accuracy_m) > Number(facts.search_max_accuracy_meters ?? 100)) {
          reasons.push(reason('LOCATION_INACCURATE'));
        }
        if (facts.distance_m !== null && facts.search_radius_meters !== null
          && Number(facts.distance_m) > Number(facts.search_radius_meters)) {
          reasons.push(reason('OUTSIDE_SERVICE_RADIUS', {
            distanceMeters: Math.round(Number(facts.distance_m)), radiusMeters: Number(facts.search_radius_meters),
          }));
        }
      }
    }
    if (facts.has_active_execution && options.context !== 'BROWSE') reasons.push(reason('NURSE_HAS_ACTIVE_EXECUTION'));
    if (Number(facts.dues_ceiling_amount) > 0
      && Number(facts.current_dues_amount) >= Number(facts.dues_ceiling_amount)) reasons.push(reason('SETTLEMENT_REQUIRED'));
    if (facts.financial_model === 'PREPAID'
      && Number(facts.prepaid_balance) - Number(facts.reserved_balance) <= 0) reasons.push(reason('INSUFFICIENT_PREPAID_BALANCE'));
    if (facts.financial_model === 'HYBRID'
      && Number(facts.prepaid_balance) + Number(facts.credit_limit) - Number(facts.reserved_balance) <= 0) {
      reasons.push(reason('FINANCIAL_LIMIT_REACHED'));
    }

    if (options.proposedStart && options.proposedEnd) {
      if (options.proposedEnd <= options.proposedStart) reasons.push(reason('INVALID_PROPOSED_WINDOW'));
      if (facts.latest_acceptable_arrival_at
        && options.proposedStart > new Date(facts.latest_acceptable_arrival_at)) reasons.push(reason('ARRIVAL_TIME_NOT_ACCEPTABLE'));
      if (await this.hasScheduleConflict(nurseId, options.proposedStart, options.proposedEnd,
        options.excludeRequestId ?? requestId, client)) reasons.push(reason('NURSE_SCHEDULE_CONFLICT'));
    }

    if (process.env.GUARDIAN_NIGHT_POLICY_ENABLED === 'true'
      && ['OFFER', 'PROPOSAL', 'ACCEPT', 'ASSIGN', 'START'].includes(options.context)) {
      const denial = (await runner.query<{ denial: string | null }>(
        'SELECT guardian_dispatch_denial($1,$2,statement_timestamp()) AS denial', [nurseId, requestId],
      )).rows[0]?.denial;
      if (denial) reasons.push(reason('SAFETY_POLICY_RESTRICTED', { policyReason: denial }));
    }
    return { eligible: reasons.length === 0, reasons };
  }

  async hasScheduleConflict(
    nurseId: string, start: Date, end: Date, excludeRequestId?: string, client?: PoolClient,
  ): Promise<boolean> {
    const result = await this.runner(client).query<{ conflict: boolean }>(
      'SELECT nurse_has_schedule_conflict($1,$2,$3,$4) AS conflict',
      [nurseId, start.toISOString(), end.toISOString(), excludeRequestId ?? null],
    );
    return result.rows[0]?.conflict === true;
  }
}
