import { Injectable, Optional } from '@nestjs/common';
import type { PoolClient, QueryResult, QueryResultRow } from 'pg';
import { locationPolicyPayload } from '../../../../packages/backend-policy/live-location.mjs';
import { LiveLocationReadService } from '../live-location/live-location-read.service.js';
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
  constructor(private readonly db: DbService,
    @Optional() private readonly locations?: LiveLocationReadService) {}
  private runner(client?: PoolClient): Queryable { return client??this.db; }

  async evaluate(nurseId:string,requestId:string,options:EligibilityOptions,client?:PoolClient):Promise<NurseEligibilityResult> {
    const runner=this.runner(client);
    const request=(await runner.query(`SELECT status,open_expires_at,latest_acceptable_arrival_at,
      booking_mode, (SELECT sum(expected_minutes) FROM care_request_items WHERE request_id=care_requests.id) AS expected_minutes FROM care_requests WHERE id=$1`,[requestId])).rows[0];
    if (!request) return {eligible:false,reasons:[reason('NURSE_OR_REQUEST_NOT_FOUND')]};
    const proposedStart=options.proposedStart ?? (request.booking_mode==='INSTANT' ? new Date() : null);
    const proposedEnd=options.proposedEnd ?? (proposedStart ? new Date(proposedStart.getTime()+Number(request.expected_minutes??30)*60000) : null);
    const live=this.locations ? locationPolicyPayload(await this.locations.getNurseLocation(nurseId,client).catch(()=>null)) : null;
    // An authoritative Redis-first reader returning no usable location is not
    // permission to silently fall back to PostgreSQL inside the SQL policy.
    const liveInput=this.locations ? JSON.stringify(live??{}) : null;
    const result=await runner.query<{reasons:string[]}>(
      `SELECT nurse_eligibility_reasons($1,$2,$3,$4,$5,$6::jsonb,NULL,$7) AS reasons`,
      [nurseId,requestId,options.context,proposedStart?.toISOString()??null,
        proposedEnd?.toISOString()??null,liveInput,
        process.env.GUARDIAN_NIGHT_POLICY_ENABLED==='true']);
    const reasons=(result.rows[0]?.reasons??['NURSE_OR_REQUEST_NOT_FOUND']).map(code=>reason(code));
    const statuses:Record<EligibilityContext,string[]>={BROWSE:['OPEN_FOR_PROPOSALS'],OFFER:['OFFERING'],
      PROPOSAL:['OPEN_FOR_PROPOSALS'],ACCEPT:['OFFERING','OPEN_FOR_PROPOSALS','SCHEDULED'],
      ASSIGN:['OFFERING','OPEN_FOR_PROPOSALS','SCHEDULED'],START:['ASSIGNED','EN_ROUTE','ARRIVED']};
    if (!statuses[options.context].includes(request.status)) reasons.push(reason('REQUEST_NOT_ELIGIBLE_FOR_CONTEXT'));
    if (request.open_expires_at && ['BROWSE','PROPOSAL','ACCEPT'].includes(options.context)
      && new Date(request.open_expires_at).getTime()<=Date.now()) reasons.push(reason('REQUEST_EXPIRED'));
    if (options.proposedStart && options.proposedEnd) {
      if (options.proposedEnd<=options.proposedStart) reasons.push(reason('INVALID_PROPOSED_WINDOW'));
      if (request.latest_acceptable_arrival_at && options.proposedStart>new Date(request.latest_acceptable_arrival_at))
        reasons.push(reason('ARRIVAL_TIME_NOT_ACCEPTABLE'));
    } else if (request.booking_mode!=='INSTANT' && ['ACCEPT','ASSIGN','PROPOSAL'].includes(options.context)) {
      reasons.push(reason('PROPOSED_WINDOW_REQUIRED'));
    }
    return {eligible:reasons.length===0,reasons};
  }
  async hasScheduleConflict(nurseId:string,start:Date,end:Date,excludeRequestId?:string,client?:PoolClient):Promise<boolean> {
    const result=await this.runner(client).query<{conflict:boolean}>(
      'SELECT nurse_has_schedule_conflict($1,$2,$3,$4) AS conflict',
      [nurseId,start.toISOString(),end.toISOString(),excludeRequestId??null]);
    return result.rows[0]?.conflict===true;
  }
}
