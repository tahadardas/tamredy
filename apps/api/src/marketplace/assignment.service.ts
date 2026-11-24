import { BadRequestException, ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { DbService } from '../db/db.service.js';
import { AcceptProposalDto } from './marketplace.dto.js';
import { MarketplaceEligibilityService } from './marketplace-eligibility.service.js';

@Injectable()
export class AssignmentService {
  constructor(
    private readonly db: DbService,
    private readonly eligibility: MarketplaceEligibilityService,
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
    return this.db.transaction(async client => {
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

      // 4. Re-verify Mutual Block Invariant
      const blockRes = await client.query(
        `SELECT 1 FROM user_blocks
         WHERE ((blocker_user_id = $1 AND blocked_user_id = $2)
            OR (blocker_user_id = $2 AND blocked_user_id = $1))
           AND revoked_at IS NULL
         LIMIT 1`,
        [patientUserId, nurse.user_id],
      );
      if (blockRes.rowCount) {
        throw new ConflictException({ code: 'USER_BLOCKED' });
      }

      // 5. Re-verify Schedule Conflict
      const proposedArrival = new Date(proposal.proposed_arrival_at);
      const estimatedMinutes = proposal.estimated_service_minutes || 30;
      const proposedEnd = new Date(proposedArrival.getTime() + estimatedMinutes * 60000);

      const conflict = await this.eligibility.hasScheduleConflict(
        nurse.id,
        proposedArrival,
        proposedEnd,
        client,
      );
      if (conflict) {
        // Invalidate this proposal
        await client.query(
          `UPDATE marketplace_proposals
           SET status = 'INVALIDATED', invalidation_reason = 'NURSE_SCHEDULE_CONFLICT', updated_at = now()
           WHERE id = $1`,
          [proposal.id],
        );
        throw new ConflictException({
          code: 'NURSE_SCHEDULE_CONFLICT',
          message: 'الممرض مرتبط بموعد آخر في هذا التوقيت',
        });
      }

      // 6. Update Proposal to ACCEPTED
      await client.query(
        `UPDATE marketplace_proposals
         SET status = 'ACCEPTED', accepted_at = now(), updated_at = now()
         WHERE id = $1`,
        [proposal.id],
      );

      // 7. Supersede Sibling Proposals for this request
      await client.query(
        `UPDATE marketplace_proposals
         SET status = 'SUPERSEDED', updated_at = now(), invalidation_reason = 'ANOTHER_PROPOSAL_ACCEPTED'
         WHERE request_id = $1 AND id != $2 AND status = 'PENDING'`,
        [requestId, proposal.id],
      );

      // 8. Invalidate overlapping proposals by this nurse for other open requests
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

      // 9. Update Care Request to ASSIGNED
      await client.query(
        `UPDATE care_requests
         SET status = 'ASSIGNED',
             marketplace_status = 'ASSIGNED',
             version = version + 1,
             updated_at = now()
         WHERE id = $1`,
        [requestId],
      );

      // 10. Create Active Assignment
      await client.query(
        `INSERT INTO request_assignments(
           request_id, nurse_id, status, expected_arrival_at, eta_status
         )
         VALUES($1, $2, 'ACTIVE', $3, 'AVAILABLE')`,
        [requestId, nurse.id, proposal.proposed_arrival_at],
      );

      // 11. Record Request Event
      await client.query(
        `INSERT INTO request_events(request_id, actor_user_id, event_type, metadata)
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
        requestId,
        proposalId: proposal.id,
        nurseId: nurse.id,
        expectedArrivalAt: proposal.proposed_arrival_at,
      };
    });
  }
}
