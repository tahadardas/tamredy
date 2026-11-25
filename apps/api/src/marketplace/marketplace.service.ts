import { Injectable, NotFoundException } from '@nestjs/common';
import { DbService } from '../db/db.service.js';
import { MarketplaceQueryDto } from './marketplace.dto.js';
import { MarketplaceEligibilityService } from './marketplace-eligibility.service.js';
import { validatedPage } from '../common/page-query.js';
import { encodeCursor } from '../common/pagination.js';

@Injectable()
export class MarketplaceService {
  constructor(
    private readonly db: DbService,
    private readonly eligibility: MarketplaceEligibilityService,
  ) {}

  /**
   * Retrieves all open marketplace requests available to the nurse.
   * Enforces privacy: returns approximate area and distance without revealing patient exact address or pin.
   */
  async listOpenRequests(nurseUserId: string, query: MarketplaceQueryDto) {
    const nurse = (await this.db.query(
      `SELECT n.id, n.user_id
       FROM nurses n JOIN users u ON u.id=n.user_id
       WHERE n.user_id = $1 AND u.status='ACTIVE' AND n.verified
         AND EXISTS (SELECT 1 FROM nurse_credentials nc WHERE nc.nurse_id=n.id
           AND nc.approved AND nc.expires_at>statement_timestamp())`,
      [nurseUserId],
    )).rows[0];

    if (!nurse) throw new NotFoundException({ code: 'NURSE_NOT_FOUND' });
    const nurseId = nurse.id;

    const sort = query.sortBy ?? 'newest';
    const scope = JSON.stringify(['marketplace',nurseUserId,sort,query.serviceId,query.regionId,query.maxDistanceKm]);
    const {limit,cursor} = validatedPage(query.limit,query.cursor,scope);
    const params: unknown[] = [nurseUserId, nurseId];

    let sql = `
      WITH current_nurse AS (
        SELECT nl.location FROM nurse_locations nl WHERE nl.nurse_id=$2
      )
      SELECT cr.id,
             cr.booking_mode,
             cr.published_at,
             cr.open_expires_at,
             cr.latest_acceptable_arrival_at,
             cr.price_amount,
             cr.currency_code,
             cr.commission_bps,
             cr.created_at,
             to_char(cr.created_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS cursor_created_at,
             s.title_ar AS service_title,
             s.code AS service_code,
             s.icon AS service_icon,
             s.expected_minutes AS primary_expected_minutes,
             a.name_ar AS approximate_area,
             a.id AS area_id,
             a.governorate_id,
             -- Approximate distance calculation if nurse location available
             CASE
               WHEN cn.location IS NOT NULL THEN
                 round((ST_Distance(cr.location, cn.location) / 1000.0)::numeric, 1)
               ELSE NULL
             END AS distance_km,
             -- Net nurse earnings calculation
             round(cr.price_amount * (1.0 - (coalesce(cr.commission_bps, 2000)::numeric / 10000.0)), 2) AS estimated_nurse_earning,
             (SELECT count(*)::int FROM marketplace_proposals mp WHERE mp.request_id = cr.id AND mp.status = 'PENDING') AS active_proposals_count,
             EXISTS (
               SELECT 1 FROM marketplace_proposals my_p
               WHERE my_p.request_id = cr.id AND my_p.nurse_id = $2 AND my_p.status = 'PENDING'
             ) AS has_my_proposal,
             EXISTS (
               SELECT 1 FROM marketplace_saved_requests msr
               WHERE msr.request_id = cr.id AND msr.nurse_id = $2
             ) AS is_saved
      FROM care_requests cr
      JOIN services s ON s.id = cr.service_id
      LEFT JOIN areas a ON a.id=cr.area_id
      LEFT JOIN current_nurse cn ON true
      WHERE cr.status = 'OPEN_FOR_PROPOSALS'
        AND cr.clinical_approval_status IN ('NOT_REQUIRED','APPROVED')
        AND cr.open_expires_at > now()
        -- Exclude requests where patient or nurse is mutually blocked
        AND NOT EXISTS (
          SELECT 1 FROM user_blocks ub
          WHERE ((ub.blocker_user_id = $1 AND ub.blocked_user_id = cr.requester_user_id)
             OR (ub.blocker_user_id = cr.requester_user_id AND ub.blocked_user_id = $1))
            AND ub.revoked_at IS NULL
        )
        -- Ensure nurse has approved skills for all services in this request
        AND NOT EXISTS (
          SELECT 1 FROM care_request_items cri
          WHERE cri.request_id = cr.id
            AND NOT EXISTS (
              SELECT 1 FROM nurse_skills ns
              WHERE ns.nurse_id = $2
                AND ns.service_id = cri.service_id
                AND ns.approved = true
            )
        )
    `;

    if (query.serviceId) {
      params.push(query.serviceId);
      sql += ` AND (cr.service_id = $${params.length} OR EXISTS (SELECT 1 FROM care_request_items cri WHERE cri.request_id = cr.id AND cri.service_id = $${params.length}))`;
    }

    if (query.regionId) {
      params.push(query.regionId);
      sql += ` AND (a.id=$${params.length} OR a.governorate_id=$${params.length})`;
    }

    if (query.maxDistanceKm) {
      params.push(query.maxDistanceKm * 1000);
      sql += ` AND cn.location IS NOT NULL AND ST_DWithin(cr.location,cn.location,$${params.length})`;
    }

    const rank = sort === 'nearest' ? 'distance_km'
      : sort === 'highest_earning' ? 'estimated_nurse_earning'
      : sort === 'arrival_time' ? 'latest_acceptable_arrival_at' : null;
    const rankType = sort === 'arrival_time' ? 'timestamptz' : 'numeric';
    const direction = sort === 'oldest' ? 'ASC' : 'DESC';
    const rankDirection = sort === 'highest_earning' ? 'DESC' : 'ASC';
    sql = `WITH listed AS (${sql}) SELECT listed.*${rank ? `,${rank}::text AS cursor_rank` : ''} FROM listed`;
    if (cursor) {
      params.push(cursor.at,cursor.id);
      const tie = `(created_at,id) ${direction === 'ASC' ? '>' : '<'} ($${params.length-1}::timestamptz,$${params.length}::uuid)`;
      if (rank) {
        params.push(cursor.rank ?? null);
        const boundary = `$${params.length}::${rankType}`;
        sql += ` WHERE (${rank} ${rankDirection === 'ASC' ? '>' : '<'} ${boundary}
          OR (${rank} IS NULL AND ${boundary} IS NOT NULL)
          OR (${rank} IS NOT DISTINCT FROM ${boundary} AND ${tie}))`;
      } else sql += ` WHERE ${tie}`;
    }
    params.push(limit+1);
    sql += ` ORDER BY ${rank ? `${rank} ${rankDirection} NULLS LAST,` : ''} created_at ${direction},id ${direction} LIMIT $${params.length}`;

    const res = await this.db.query(sql, params);
    const rows = res.rows.slice(0,limit);
    const last = rows.at(-1);
    return {
      requests: rows.map(({cursor_created_at,cursor_rank,...row}) => row),
      totalCount: rows.length,
      nextCursor: res.rows.length>limit && last
        ? encodeCursor({id:last.id,at:last.cursor_created_at,rank:last.cursor_rank},scope) : null,
    };
  }

  /**
   * Detailed request view for nurse before submitting a proposal.
   */
  async getRequestDetails(nurseUserId: string, requestId: string) {
    const nurse = (await this.db.query(`SELECT id FROM nurses WHERE user_id = $1`, [nurseUserId])).rows[0];
    if (!nurse) throw new NotFoundException({ code: 'NURSE_NOT_FOUND' });

    const eligibility = await this.eligibility.checkBrowseEligibility(nurse.id, requestId);
    if (!eligibility.eligible) {
      throw new NotFoundException({ code: eligibility.reason ?? 'REQUEST_NOT_ACCESSIBLE' });
    }

    const reqRes = await this.db.query(
      `SELECT cr.id, cr.booking_mode, cr.published_at, cr.open_expires_at,
              cr.latest_acceptable_arrival_at, cr.price_amount, cr.currency_code,
              cr.commission_bps, cr.created_at,
              s.title_ar AS service_title, s.code AS service_code, s.icon AS service_icon,
              a.name_ar AS approximate_area,
              round(cr.price_amount * (1.0 - (coalesce(cr.commission_bps, 2000)::numeric / 10000.0)), 2) AS estimated_nurse_earning
       FROM care_requests cr
       JOIN services s ON s.id = cr.service_id
       LEFT JOIN areas a ON a.id=cr.area_id
       WHERE cr.id = $1`,
      [requestId],
    );
    if (!reqRes.rowCount) throw new NotFoundException({ code: 'REQUEST_NOT_FOUND' });
    const req = reqRes.rows[0];

    const itemsRes = await this.db.query(
      `SELECT cri.id, cri.service_id, cri.quantity, cri.unit_price, cri.expected_minutes,
              s.title_ar, s.code, s.requires_prescription, s.required_skills,
              cri.clinical_requirements_snapshot
       FROM care_request_items cri
       JOIN services s ON s.id = cri.service_id
       WHERE cri.request_id = $1
       ORDER BY cri.created_at ASC`,
      [requestId],
    );

    const myProposal = (await this.db.query(
      `SELECT id, status, proposed_arrival_at, estimated_nurse_earning, note, expires_at, created_at
       FROM marketplace_proposals
       WHERE request_id = $1 AND nurse_id = $2 AND status = 'PENDING'
       LIMIT 1`,
      [requestId, nurse.id],
    )).rows[0] ?? null;

    return {
      ...req,
      items: itemsRes.rows,
      myProposal,
    };
  }

  /**
   * Bookmarks a request for quick access in the nurse app.
   */
  async saveRequest(nurseUserId: string, requestId: string) {
    const nurse = (await this.db.query(`SELECT id FROM nurses WHERE user_id = $1`, [nurseUserId])).rows[0];
    if (!nurse) throw new NotFoundException({ code: 'NURSE_NOT_FOUND' });

    await this.db.query(
      `INSERT INTO marketplace_saved_requests(nurse_id, request_id)
       VALUES($1, $2)
       ON CONFLICT (nurse_id, request_id) DO NOTHING`,
      [nurse.id, requestId],
    );
    return { saved: true, requestId };
  }

  /**
   * Removes bookmark for a request.
   */
  async unsaveRequest(nurseUserId: string, requestId: string) {
    const nurse = (await this.db.query(`SELECT id FROM nurses WHERE user_id = $1`, [nurseUserId])).rows[0];
    if (!nurse) throw new NotFoundException({ code: 'NURSE_NOT_FOUND' });

    await this.db.query(
      `DELETE FROM marketplace_saved_requests WHERE nurse_id = $1 AND request_id = $2`,
      [nurse.id, requestId],
    );
    return { saved: false, requestId };
  }
}
