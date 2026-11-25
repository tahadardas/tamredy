import { Injectable } from '@nestjs/common';
import type { PoolClient } from 'pg';
import { NurseEligibilityEngine, type NurseEligibilityResult } from '../dispatch/nurse-eligibility.engine.js';

export interface EligibilityResult extends NurseEligibilityResult {
  reason?: string;
}

@Injectable()
export class MarketplaceEligibilityService {
  constructor(private readonly engine: NurseEligibilityEngine) {}

  private withPrimaryReason(result: NurseEligibilityResult): EligibilityResult {
    return { ...result, reason: result.reasons[0]?.code };
  }

  async checkBrowseEligibility(nurseId: string, requestId: string, client?: PoolClient): Promise<EligibilityResult> {
    return this.withPrimaryReason(await this.engine.evaluate(nurseId, requestId, { context: 'BROWSE' }, client));
  }

  async checkProposalEligibility(
    nurseId: string,
    requestId: string,
    proposedArrivalAt: Date,
    estimatedMinutes: number,
    client?: PoolClient,
  ): Promise<EligibilityResult> {
    if (proposedArrivalAt.getTime() < Date.now() - 60_000) {
      return this.withPrimaryReason({
        eligible: false,
        reasons: [{ code: 'ARRIVAL_TIME_IN_PAST', messageKey: 'eligibility.arrival_time_in_past' }],
      });
    }
    const proposedEnd = new Date(proposedArrivalAt.getTime() + estimatedMinutes * 60_000);
    return this.withPrimaryReason(await this.engine.evaluate(nurseId, requestId, {
      context: 'PROPOSAL', proposedStart: proposedArrivalAt, proposedEnd, excludeRequestId: requestId,
    }, client));
  }

  async checkAcceptanceEligibility(
    nurseId: string,
    requestId: string,
    proposedArrivalAt: Date,
    estimatedMinutes: number,
    client?: PoolClient,
  ): Promise<EligibilityResult> {
    const proposedEnd = new Date(proposedArrivalAt.getTime() + estimatedMinutes * 60_000);
    return this.withPrimaryReason(await this.engine.evaluate(nurseId, requestId, {
      context: 'ACCEPT', proposedStart: proposedArrivalAt, proposedEnd, excludeRequestId: requestId,
    }, client));
  }

  hasScheduleConflict(
    nurseId: string,
    startTime: Date,
    endTime: Date,
    client?: PoolClient,
  ): Promise<boolean> {
    return this.engine.hasScheduleConflict(nurseId, startTime, endTime, undefined, client);
  }
}
