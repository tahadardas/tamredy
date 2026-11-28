import { BadRequestException, ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { DbService } from '../db/db.service.js';
import { SubmitProposalDto, UpdateProposalDto, WithdrawProposalDto } from './marketplace.dto.js';
import { MarketplaceEligibilityService } from './marketplace-eligibility.service.js';
import { buildNotificationPayload } from '../notifications/notification-routing.js';
import { FeatureCapabilitiesService } from '../capabilities/feature-capabilities.service.js';

@Injectable()
export class ProposalsService {
  constructor(
    private readonly db: DbService,
    private readonly eligibility: MarketplaceEligibilityService,
    private readonly capabilities: FeatureCapabilitiesService = new FeatureCapabilitiesService(db),
  ) {}

  /**
   * Nurse submits a structured readiness proposal.
   */
  async submitProposal(nurseUserId: string, requestId: string, dto: SubmitProposalDto) {
    this.capabilities.assertBookingMode('OPEN');
    const nurse = (await this.db.query(`SELECT id FROM nurses WHERE user_id = $1`, [nurseUserId])).rows[0];
    if (!nurse) throw new NotFoundException({ code: 'NURSE_NOT_FOUND' });
    const nurseId = nurse.id;

    // Calculate absolute proposed arrival timestamp
    const now = new Date();
    let proposedArrivalAt: Date;
    if (dto.proposedArrivalAt) {
      proposedArrivalAt = new Date(dto.proposedArrivalAt);
    } else if (dto.arrivalMinutes && dto.arrivalMinutes > 0) {
      proposedArrivalAt = new Date(now.getTime() + dto.arrivalMinutes * 60000);
    } else {
      throw new BadRequestException({ code: 'ARRIVAL_TIME_REQUIRED' });
    }

    return this.db.transaction(async client => {
      // Serializes the per-nurse proposal-cap decision without locking an
      // unrelated table or relying on a race-prone count followed by insert.
      await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 0))', [nurseId]);
      // 1. Lock request to ensure it's still open
      const reqRes = await client.query(
        `SELECT id, status, requester_user_id, price_amount, commission_bps,
                open_expires_at, latest_acceptable_arrival_at, version
         FROM care_requests
         WHERE id = $1
         FOR SHARE`,
        [requestId],
      );
      if (!reqRes.rowCount) throw new NotFoundException({ code: 'REQUEST_NOT_FOUND' });
      const req = reqRes.rows[0];

      if (req.status !== 'OPEN_FOR_PROPOSALS') {
        throw new ConflictException({ code: 'REQUEST_NOT_OPEN', message: 'الطلب غير متاح لاستقبال عروض الاستعداد' });
      }
      if (req.open_expires_at && new Date(req.open_expires_at) <= now) {
        throw new ConflictException({ code: 'REQUEST_EXPIRED', message: 'انتهت مدة استقبال العروض لهذا الطلب' });
      }

      // 2. Check total estimated service duration
      const durationRes = await client.query(
        `SELECT coalesce(sum(expected_minutes), 30)::int AS total_mins
         FROM care_request_items
         WHERE request_id = $1`,
        [requestId],
      );
      const estimatedMinutes = durationRes.rows[0]?.total_mins || 30;

      // 3. Eligibility verification
      const check = await this.eligibility.checkProposalEligibility(
        nurseId,
        requestId,
        proposedArrivalAt,
        estimatedMinutes,
        client,
      );
      if (!check.eligible) {
        throw new BadRequestException({ code: check.reason ?? 'NURSE_NOT_ELIGIBLE' });
      }

      // 4. Calculate proposal expiration and nurse earnings
      const policy = (await client.query(
        `SELECT value FROM app_settings WHERE key = 'booking_policies'`,
      )).rows[0]?.value;
      const proposalDurationMins = Number(policy?.proposalDurationMinutes) || 5;
      const defaultExpires = new Date(now.getTime() + proposalDurationMins * 60000);

      // Proposal expires at earliest of: proposalDuration, open_expires_at, or proposedArrivalAt
      let proposalExpiresAt = defaultExpires;
      if (req.open_expires_at && new Date(req.open_expires_at) < proposalExpiresAt) {
        proposalExpiresAt = new Date(req.open_expires_at);
      }
      if (proposedArrivalAt < proposalExpiresAt) {
        proposalExpiresAt = proposedArrivalAt;
      }

      const commissionRate = (Number(req.commission_bps) || 2000) / 10000.0;
      const priceAmount = Number(req.price_amount);
      const estimatedNurseEarning = Math.round(priceAmount * (1.0 - commissionRate) * 100) / 100;

      // 5. Insert proposal
      const res = await client.query(
        `INSERT INTO marketplace_proposals(
           request_id, nurse_id, status, proposed_arrival_at,
           estimated_service_minutes, estimated_nurse_earning, note,
           pricing_version, request_version, expires_at
         )
         VALUES($1, $2, 'PENDING', $3, $4, $5, $6, 1, $7, $8)
         ON CONFLICT (request_id, nurse_id) WHERE status = 'PENDING'
         DO UPDATE SET
           proposed_arrival_at = EXCLUDED.proposed_arrival_at,
           estimated_service_minutes = EXCLUDED.estimated_service_minutes,
           estimated_nurse_earning = EXCLUDED.estimated_nurse_earning,
           note = EXCLUDED.note,
           expires_at = EXCLUDED.expires_at,
            request_version = EXCLUDED.request_version,
           proposal_version = marketplace_proposals.proposal_version + 1,
           updated_at = now()
         RETURNING *`,
        [
          requestId,
          nurseId,
          proposedArrivalAt.toISOString(),
          estimatedMinutes,
          estimatedNurseEarning,
          dto.note?.trim() || null,
          req.version,
          proposalExpiresAt.toISOString(),
        ],
      );

      const proposal = res.rows[0];

      // 6. Notify patient via outbox
      await client.query(
        `INSERT INTO outbox_events(event_type, aggregate_id, payload)
         VALUES('marketplace.proposal.created', $1, $2::jsonb)`,
        [
          proposal.id,
          JSON.stringify(buildNotificationPayload({
            eventType: 'marketplace.proposal.created',
            recipientUserId: req.requester_user_id,
            recipientRole: 'PATIENT',
            targetApp: 'PATIENT_APP',
            requestId,
            proposalId: proposal.id,
            entityVersion: proposal.proposal_version,
            expiresAt: proposal.expires_at ? new Date(proposal.expires_at).toISOString() : null,
            extra: {
              proposedArrivalAt: proposal.proposed_arrival_at,
              estimatedNurseEarning,
            },
          })),
        ],
      );

      return proposal;
    });
  }

  /**
   * Nurse withdraws active proposal before acceptance.
   */
  async withdrawProposal(nurseUserId: string, proposalId: string, dto?: WithdrawProposalDto) {
    const nurse = (await this.db.query(`SELECT id FROM nurses WHERE user_id = $1`, [nurseUserId])).rows[0];
    if (!nurse) throw new NotFoundException({ code: 'NURSE_NOT_FOUND' });

    const res = await this.db.query(
      `UPDATE marketplace_proposals
       SET status = 'WITHDRAWN',
           withdrawn_at = now(),
           invalidation_reason = coalesce($3, 'WITHDRAWN_BY_NURSE'),
           updated_at = now()
       WHERE id = $1 AND nurse_id = $2 AND status = 'PENDING'
       RETURNING *`,
      [proposalId, nurse.id, dto?.reason ?? null],
    );

    if (!res.rowCount) {
      throw new NotFoundException({ code: 'PROPOSAL_NOT_FOUND_OR_NOT_PENDING' });
    }
    const prop = res.rows[0];

    const reqOwner = (await this.db.query(`SELECT requester_user_id, version FROM care_requests WHERE id = $1`, [prop.request_id])).rows[0];
    if (reqOwner?.requester_user_id) {
      // Inform patient of withdrawal
      await this.db.query(
        `INSERT INTO outbox_events(event_type, aggregate_id, payload)
         VALUES('marketplace.proposal.withdrawn', $1, $2::jsonb)`,
        [
          prop.id,
          JSON.stringify(buildNotificationPayload({
            eventType: 'marketplace.proposal.withdrawn',
            recipientUserId: reqOwner.requester_user_id,
            recipientRole: 'PATIENT',
            targetApp: 'PATIENT_APP',
            requestId: prop.request_id,
            proposalId: prop.id,
            entityVersion: reqOwner.version,
          })),
        ],
      );
    }

    return { withdrawn: true, proposalId };
  }

  /**
   * Lists all proposals submitted by the nurse.
   */
  async listNurseProposals(nurseUserId: string, statusFilter?: string) {
    const nurse = (await this.db.query(`SELECT id FROM nurses WHERE user_id = $1`, [nurseUserId])).rows[0];
    if (!nurse) throw new NotFoundException({ code: 'NURSE_NOT_FOUND' });

    let sql = `
      SELECT mp.*,
             cr.price_amount, cr.currency_code, cr.status AS request_status,
             s.title_ar AS service_title,
             split_part(cr.address_text, ',', 1) AS approximate_area
      FROM marketplace_proposals mp
      JOIN care_requests cr ON cr.id = mp.request_id
      JOIN services s ON s.id = cr.service_id
      WHERE mp.nurse_id = $1
    `;
    const params: unknown[] = [nurse.id];
    if (statusFilter) {
      params.push(statusFilter);
      sql += ` AND mp.status = $${params.length}`;
    }
    sql += ` ORDER BY mp.created_at DESC LIMIT 50`;

    const res = await this.db.query(sql, params);
    return res.rows;
  }

  /**
   * Patient views all incoming readiness proposals for their request.
   */
  async listRequestProposals(patientUserId: string, requestId: string) {
    // Verify request ownership
    const req = (await this.db.query(
      `SELECT id, status FROM care_requests WHERE id = $1 AND requester_user_id = $2`,
      [requestId, patientUserId],
    )).rows[0];
    if (!req) throw new NotFoundException({ code: 'REQUEST_NOT_FOUND' });

    const res = await this.db.query(
      `SELECT mp.id,
              mp.status,
              mp.proposed_arrival_at,
              mp.estimated_service_minutes,
              mp.note,
              mp.expires_at,
              mp.created_at,
              mp.proposal_version,
              n.id AS nurse_id,
              u.id AS nurse_user_id,
              -- Nurse professional presentation (no private phone or address)
              u.display_name AS nurse_name,
              coalesce(n.reputation_score, 5.0) AS nurse_rating,
              coalesce(n.completed_orders_count, 0) AS completed_orders_count,
              nc.license_ref AS license_tail
       FROM marketplace_proposals mp
       JOIN nurses n ON n.id = mp.nurse_id
       JOIN users u ON u.id = n.user_id
       LEFT JOIN nurse_credentials nc ON nc.nurse_id = n.id AND nc.approved = true
       WHERE mp.request_id = $1
         AND (mp.status = 'PENDING' AND mp.expires_at > now() OR mp.status = 'ACCEPTED')
       ORDER BY mp.proposed_arrival_at ASC, mp.created_at ASC`,
      [requestId],
    );

    return res.rows;
  }

  /**
   * Patient declines a specific proposal.
   */
  async declineProposal(patientUserId: string, requestId: string, proposalId: string) {
    const req = (await this.db.query(
      `SELECT id FROM care_requests WHERE id = $1 AND requester_user_id = $2`,
      [requestId, patientUserId],
    )).rows[0];
    if (!req) throw new NotFoundException({ code: 'REQUEST_NOT_FOUND' });

    const res = await this.db.query(
      `UPDATE marketplace_proposals
       SET status = 'DECLINED', updated_at = now()
       WHERE id = $1 AND request_id = $2 AND status = 'PENDING'
       RETURNING id`,
      [proposalId, requestId],
    );

    return { declined: (res.rowCount ?? 0) > 0, proposalId };
  }
}
