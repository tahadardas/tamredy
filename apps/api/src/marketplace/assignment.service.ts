import { ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { DbService } from '../db/db.service.js';
import { AcceptProposalDto } from './marketplace.dto.js';
import { MarketplaceEligibilityService } from './marketplace-eligibility.service.js';
import { AssignmentOrchestrator } from '../dispatch/assignment.orchestrator.js';

@Injectable()
export class AssignmentService {
  constructor(
    private readonly db: DbService,
    private readonly eligibility: MarketplaceEligibilityService,
    private readonly assignments: AssignmentOrchestrator,
  ) {}

  /**
   * Atomically accepts a readiness proposal, assigning the request to the nurse.
   * Enforces strict canonical lock ordering:
   * 1. care_requests
   * 2. marketplace_proposals
   * 3. nurses
   * Guarantees absolute prevention of double-assignment.
   */
  async acceptProposal(
    patientUserId: string,
    requestId: string,
    proposalId: string,
    dto?: AcceptProposalDto,
  ) {
    const outcome = await this.db.transaction(async client => {
      // 1. Lock Care Request
      const reqRes = await client.query(
        `SELECT id, requester_user_id, status, version, price_amount, commission_bps,
                open_expires_at, latest_acceptable_arrival_at, booking_mode
         FROM care_requests
         WHERE id = $1
         FOR UPDATE`,
        [requestId],
      );
      if (!reqRes.rowCount) throw new NotFoundException({ code: 'REQUEST_NOT_FOUND' });
      const request = reqRes.rows[0];

      if (request.requester_user_id !== patientUserId) {
        throw new ForbiddenException({ code: 'FORBIDDEN_NOT_REQUEST_OWNER' });
      }

      if (request.status !== 'OPEN_FOR_PROPOSALS') {
        throw new ConflictException({
          code: 'REQUEST_ALREADY_ASSIGNED',
          message: 'تم إسناد هذا الطلب بالفعل أو لم يعد متاحاً في السوق المفتوح',
        });
      }

      if (dto?.requestVersion && request.version !== dto.requestVersion) {
        throw new ConflictException({ code: 'REQUEST_VERSION_CONFLICT' });
      }

      // 2. Lock Proposal
      const propRes = await client.query(
        `SELECT id, request_id, nurse_id, status, proposed_arrival_at,
                estimated_service_minutes, estimated_nurse_earning, proposal_version,
                expires_at
         FROM marketplace_proposals
         WHERE id = $1 AND request_id = $2
         FOR UPDATE`,
        [proposalId, requestId],
      );
      if (!propRes.rowCount) throw new NotFoundException({ code: 'PROPOSAL_NOT_FOUND' });
      const proposal = propRes.rows[0];

      if (proposal.status !== 'PENDING') {
        throw new ConflictException({
          code: 'PROPOSAL_NOT_PENDING',
          message: 'هذا العرض لم يعد متاحاً للقبول',
        });
      }

      if (new Date(proposal.expires_at) <= new Date()) {
        throw new ConflictException({
          code: 'PROPOSAL_EXPIRED',
          message: 'انتهت مدة صلاحية هذا العرض',
        });
      }

      if (dto?.proposalVersion && proposal.proposal_version !== dto.proposalVersion) {
        throw new ConflictException({
          code: 'PROPOSAL_VERSION_CONFLICT',
          message: 'تم تحديث العرض من قبل الممرض، يرجى مراجعة تفاصيل العرض المحدث',
        });
      }

      // 3. Lock Nurse
      const nurseRes = await client.query(
        `SELECT n.id, n.user_id, n.verified, n.work_status
         FROM nurses n
         WHERE n.id = $1
         FOR UPDATE`,
        [proposal.nurse_id],
      );
      if (!nurseRes.rowCount) throw new NotFoundException({ code: 'NURSE_NOT_FOUND' });
      const nurse = nurseRes.rows[0];

      if (!nurse.verified) {
        throw new ConflictException({ code: 'NURSE_NOT_VERIFIED' });
      }

      // 4. Re-evaluate every mutable eligibility invariant after all
      // contested rows have been locked.
      const proposedArrival = new Date(proposal.proposed_arrival_at);
      const estimatedMinutes = proposal.estimated_service_minutes || 30;
      const proposedEnd = new Date(proposedArrival.getTime() + estimatedMinutes * 60000);

      const eligibility = await this.eligibility.checkAcceptanceEligibility(
        nurse.id,
        requestId,
        proposedArrival,
        estimatedMinutes,
        client,
      );
      if (!eligibility.eligible) {
        const primaryReason = eligibility.reason ?? 'NURSE_NOT_ELIGIBLE';
        // Persist the invalidation and report the conflict only after commit;
        // throwing here would silently roll the invalidation back.
        await client.query(
          `UPDATE marketplace_proposals
           SET status = 'INVALIDATED', invalidation_reason = $2, invalidated_at=now(), updated_at = now()
           WHERE id = $1`,
          [proposal.id, primaryReason],
        );
        return { assigned: false as const, rejection: primaryReason, reasons: eligibility.reasons };
      }

      // 6. Invalidate overlapping proposals by this nurse for other open requests
      const bufferMs = 30 * 60000;
      const windowStart = new Date(proposedArrival.getTime() - bufferMs).toISOString();
      const windowEnd = new Date(proposedEnd.getTime() + bufferMs).toISOString();

      await client.query(
        `UPDATE marketplace_proposals
         SET status = 'INVALIDATED',
             invalidation_reason = 'NURSE_COMMITTED_ELSEWHERE',
             updated_at = now()
         WHERE nurse_id = $1
           AND id != $2
           AND status = 'PENDING'
           AND (proposed_arrival_at < $4::timestamptz AND proposed_arrival_at + interval '60 minutes' > $3::timestamptz)`,
        [nurse.id, proposal.id, windowStart, windowEnd],
      );

      // 7. Final assignment, lifecycle transition, channel closure, and
      // duplicate prevention are centralized in the orchestrator.
      const assigned = await this.assignments.assignLocked(client, {
        request,
        nurseId: nurse.id,
        actor: 'PATIENT',
        actorUserId: patientUserId,
        source: 'MARKETPLACE_PROPOSAL',
        sourceId: proposal.id,
        plannedStart: proposedArrival,
        plannedEnd: proposedEnd,
        reserveImmediately: false,
      });

      // 11. Record Request Event
      await client.query(
        `INSERT INTO request_events(request_id, actor_user_id, event_type, payload)
         VALUES($1, $2, 'marketplace.proposal.accepted', $3::jsonb)`,
        [
          requestId,
          patientUserId,
          JSON.stringify({
            proposalId: proposal.id,
            nurseId: nurse.id,
            proposedArrivalAt: proposal.proposed_arrival_at,
          }),
        ],
      );

      // 12. Create Durable Outbox Events
      // A: Notify Nurse
      await client.query(
        `INSERT INTO outbox_events(event_type, aggregate_id, payload)
         VALUES('marketplace.proposal.accepted', $1, $2::jsonb)`,
        [
          proposal.id,
          JSON.stringify({
            proposalId: proposal.id,
            requestId,
            nurseUserId: nurse.user_id,
            recipientUserId: nurse.user_id,
            proposedArrivalAt: proposal.proposed_arrival_at,
          }),
        ],
      );

      // B: Standard request.assigned event for dispatch tracking & Guardian
      await client.query(
        `INSERT INTO outbox_events(event_type, aggregate_id, payload)
         VALUES('request.assigned', $1, $2::jsonb)`,
        [
          requestId,
          JSON.stringify({
            requestId,
            nurseId: nurse.id,
            nurseUserId: nurse.user_id,
            patientUserId,
            expectedArrivalAt: proposal.proposed_arrival_at,
          }),
        ],
      );

      return {
        assigned: true,
        assignmentId: assigned.assignmentId,
        requestId,
        proposalId: proposal.id,
        nurseId: nurse.id,
        expectedArrivalAt: proposal.proposed_arrival_at,
      };
    });
    if (!outcome.assigned) {
      throw new ConflictException({ code: outcome.rejection, reasons: outcome.reasons });
    }
    return outcome;
  }
}
