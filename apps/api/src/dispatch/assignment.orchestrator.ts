import { Injectable } from '@nestjs/common';
import type { PoolClient } from 'pg';
import { conflict } from '../common/errors.js';
import { transitionRequest, type RequestStatus, type RequestTransitionActor } from '../requests/request-lifecycle.js';
import { FeesService } from '../pricing/fees.service.js';
import { commissionFor } from '../pricing/pricing.js';
import { closeOpenOffers } from './offer-outbox.js';
import { NurseEligibilityEngine } from './nurse-eligibility.engine.js';

interface AssignmentRequestSnapshot {
  id: string;
  status: RequestStatus;
  version: number;
  price_amount: string | number;
  commission_bps: number;
  currency_code: string;
}

interface AssignInput {
  request: AssignmentRequestSnapshot;
  nurseId: string;
  actor: RequestTransitionActor;
  actorUserId: string;
  source: 'INSTANT_OFFER' | 'MARKETPLACE_PROPOSAL' | 'SCHEDULED' | 'ADMIN';
  sourceId?: string;
  plannedStart?: Date;
  plannedEnd?: Date;
  reserveImmediately: boolean;
}

export interface AssignmentOutcome {
  assignmentId: string;
  requestId: string;
  nurseId: string;
  status: 'ASSIGNED';
}

@Injectable()
export class AssignmentOrchestrator {
  constructor(
    private readonly eligibility: NurseEligibilityEngine,
    private readonly fees: FeesService = new FeesService(),
  ) {}

  async assignLocked(client: PoolClient, input: AssignInput): Promise<AssignmentOutcome> {
    const eligibility = await this.eligibility.evaluate(input.nurseId, input.request.id, {
      context: 'ASSIGN',
      proposedStart: input.plannedStart,
      proposedEnd: input.plannedEnd,
      excludeRequestId: input.request.id,
    }, client);
    if (!eligibility.eligible) conflict(eligibility.reasons[0]?.code ?? 'NURSE_NOT_ELIGIBLE');

    const baseCommissionBps = Number(input.request.commission_bps ?? 2000);
    const rep = await this.fees.reputation(client, input.nurseId);
    const tiers = await this.fees.tiers(client);
    const appliedCommissionBps = commissionFor(baseCommissionBps, tiers, rep.reputation, rep.reviews);
    const currencyCode = input.request.currency_code;
    if (!currencyCode) conflict('CURRENCY_CODE_REQUIRED');
    const estimatedCommission = Math.round(Number(input.request.price_amount) * appliedCommissionBps / 10_000);

    const account = (await client.query(`SELECT * FROM nurse_financial_currency_accounts
      WHERE nurse_id=$1 AND currency_code=$2 FOR UPDATE`, [input.nurseId,currencyCode])).rows[0];
    if (estimatedCommission > 0 && !account) {
      conflict('NURSE_FINANCIAL_ACCOUNT_REQUIRED');
    }

    if (account?.settlement_required) conflict('SETTLEMENT_REQUIRED');
    if (account && estimatedCommission > 0) {
      const held = (await client.query(`SELECT coalesce(sum(prepaid_amount),0) AS prepaid,
        coalesce(sum(credit_amount),0) AS credit FROM financial_reservations
        WHERE nurse_id=$1 AND status='HELD' AND currency_code=$2`, [input.nurseId, currencyCode])).rows[0];
      const position = (await client.query(`SELECT greatest(coalesce(sum(CASE
        WHEN account_id=$1 THEN debit_amount-credit_amount
        WHEN account_id=$2 THEN debit_amount-credit_amount ELSE 0 END),0),0) AS dues
        FROM financial_ledger_entries WHERE account_id IN ($1,$2) AND currency=$3`,
      [`CASH_HELD_BY_NURSE:${input.nurseId}`,`NURSE_PAYABLE:${input.nurseId}`, currencyCode])).rows[0];
      const prepaidAvailable = Math.max(0,Number(account.prepaid_balance)-Number(held.prepaid));
      const prepaidAmount = account.financial_model==='RECEIVABLES' ? 0 : Math.min(estimatedCommission,prepaidAvailable);
      const creditAmount = estimatedCommission-prepaidAmount;
      if (account.financial_model === 'PREPAID' && creditAmount > 0) conflict('INSUFFICIENT_PREPAID_BALANCE');
      const creditAvailable = Math.max(0,Number(account.credit_limit)-Number(position.dues)-Number(held.credit));
      if (account.financial_model !== 'PREPAID' && creditAmount > creditAvailable) {
        conflict('FINANCIAL_LIMIT_REACHED');
      }
      const reservation = await client.query(`INSERT INTO financial_reservations(
        account_id,amount,reference_id,status,nurse_id,prepaid_amount,credit_amount,currency_code,currency_account_id
      ) VALUES($1,$2,$3,'HELD',$4,$5,$6,$7,$8)
      ON CONFLICT(account_id,reference_id) DO NOTHING RETURNING id`, [
        `NURSE_FINANCIAL:${input.nurseId}:${currencyCode}`,estimatedCommission,input.request.id,input.nurseId,
        prepaidAmount,creditAmount,currencyCode,account.id,
      ]);
      if (reservation.rowCount) {
        await client.query(`UPDATE nurse_financial_currency_accounts
          SET reserved_balance=reserved_balance+$2,version=version+1,updated_at=statement_timestamp() WHERE id=$1`,
        [account.id,estimatedCommission]);
      }
    }

    const commissionSnapshot = {
      baseCommissionBps,
      appliedCommissionBps,
      tierVersion: 1,
      currencyCode,
      reservationAmount: estimatedCommission,
      pricingSnapshotVersion: input.request.version,
    };

    let assignmentId: string;
    try {
      const durationMinutes = input.plannedStart && input.plannedEnd
        ? Math.max(1, Math.ceil((input.plannedEnd.getTime() - input.plannedStart.getTime()) / 60_000))
        : null;
      const inserted = (await client.query<{ id: string }>(`
        INSERT INTO request_assignments(
          request_id,nurse_id,status,accepted_at,departure_due_at,
          planned_start_at,planned_end_at,service_duration_minutes,commission_policy_snapshot
        )
        SELECT $1,$2,CASE WHEN $3::boolean THEN 'ACTIVE' ELSE 'RESERVED' END,statement_timestamp(),
          CASE WHEN $3::boolean THEN statement_timestamp()+nullif(coalesce(
            (SELECT (value->>'departureReminderSeconds')::integer FROM app_settings WHERE key='dispatch'),0),0)
            * interval '1 second' END,$4,$5,coalesce($6::integer,
          (SELECT sum(expected_minutes)::integer FROM care_request_items WHERE request_id=$1)),$7::jsonb
        RETURNING id
      `, [input.request.id,input.nurseId,input.reserveImmediately,
        input.plannedStart?.toISOString() ?? null,input.plannedEnd?.toISOString() ?? null,durationMinutes,
        JSON.stringify(commissionSnapshot)])).rows[0];
      if (!inserted) conflict('ASSIGNMENT_CONFLICT');
      assignmentId=inserted.id;
    } catch (error) {
      if ((error as { code?: string }).code === '23505') conflict('ASSIGNMENT_CONFLICT');
      if ((error as { code?: string }).code === '23P01') conflict('NURSE_SCHEDULE_CONFLICT');
      throw error;
    }

    if (input.source === 'MARKETPLACE_PROPOSAL') {
      await client.query(`UPDATE marketplace_proposals
        SET status='ACCEPTED',accepted_at=statement_timestamp(),updated_at=statement_timestamp()
        WHERE id=$1 AND request_id=$2 AND nurse_id=$3 AND status='PENDING'`,
      [input.sourceId, input.request.id, input.nurseId]);
      await client.query(`UPDATE marketplace_proposals
        SET status='SUPERSEDED',updated_at=statement_timestamp(),invalidation_reason='ANOTHER_PROPOSAL_ACCEPTED'
        WHERE request_id=$1 AND id<>$2 AND status='PENDING'`, [input.request.id, input.sourceId]);
    }

    await transitionRequest(client, {
      requestId: input.request.id,
      fromStatus: input.request.status,
      toStatus: 'ASSIGNED',
      currentVersion: input.request.version,
      actor: input.actor,
      actorUserId: input.actorUserId,
      reason: `${input.source}_ASSIGNED`,
      metadata: { sourceId: input.sourceId, assignmentId, nurseId: input.nurseId },
    });

    await client.query(`UPDATE care_requests SET marketplace_status='ASSIGNED',
      scheduled_start_at=coalesce($2,scheduled_start_at),scheduled_end_at=coalesce($3,scheduled_end_at),
      closed_at=coalesce(closed_at,statement_timestamp()),close_reason=coalesce(close_reason,'ASSIGNED')
      WHERE id=$1`, [input.request.id, input.plannedStart?.toISOString() ?? null, input.plannedEnd?.toISOString() ?? null]);

    if (input.reserveImmediately) {
      const reserved = await client.query(`UPDATE nurses SET work_status='RESERVED',updated_at=statement_timestamp()
        WHERE id=$1 AND work_status='AVAILABLE'`, [input.nurseId]);
      if (reserved.rowCount !== 1) conflict('NURSE_NOT_AVAILABLE');
    }

    await closeOpenOffers(
      client,
      input.request.id,
      'ASSIGNED',
      input.source === 'INSTANT_OFFER' ? input.sourceId : undefined,
    );
    await client.query('DELETE FROM dispatch_jobs WHERE request_id=$1', [input.request.id]);

    return { assignmentId, requestId: input.request.id, nurseId: input.nurseId, status: 'ASSIGNED' };
  }
}
