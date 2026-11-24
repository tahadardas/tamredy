import { Injectable, BadRequestException, ConflictException, NotFoundException } from '@nestjs/common';
import { DbService } from '../db/db.service.js';

@Injectable()
export class FavoritesService {
  constructor(private readonly db: DbService) {}

  /** Adds a nurse to patient's favorites after a completed visit */
  async addFavorite(patientUserId: string, nurseId: string) {
    // 1. Verify patient has had a completed visit with this nurse
    const visitCheck = await this.db.query(`
      SELECT cr.id FROM care_requests cr
      JOIN request_assignments ra ON ra.request_id = cr.id
      JOIN visits v ON v.assignment_id = ra.id AND v.completed_at IS NOT NULL
      WHERE cr.requester_user_id = $1 AND ra.nurse_id = $2
      LIMIT 1
    `, [patientUserId, nurseId]);

    if (!visitCheck.rowCount) {
      throw new BadRequestException({ code: 'CANNOT_FAVORITE_WITHOUT_COMPLETED_VISIT' });
    }

    // 2. Check mutual blocking
    const blockCheck = await this.db.query(`
      SELECT 1 FROM user_blocks ub
      JOIN nurses n ON n.id = $2
      WHERE ((ub.blocker_user_id = $1 AND ub.blocked_user_id = n.user_id)
         OR (ub.blocker_user_id = n.user_id AND ub.blocked_user_id = $1))
        AND ub.revoked_at IS NULL
    `, [patientUserId, nurseId]);

    if (blockCheck.rowCount) {
      throw new ConflictException({ code: 'MUTUAL_BLOCK_ACTIVE' });
    }

    const res = await this.db.query(`
      INSERT INTO patient_favorite_nurses(patient_user_id, nurse_id)
      VALUES($1, $2)
      ON CONFLICT (patient_user_id, nurse_id) DO NOTHING
      RETURNING *
    `, [patientUserId, nurseId]);

    return res.rows[0] ?? { status: 'ALREADY_FAVORITED' };
  }

  /** Removes nurse from favorites */
  async removeFavorite(patientUserId: string, nurseId: string) {
    const res = await this.db.query(`
      DELETE FROM patient_favorite_nurses
      WHERE patient_user_id = $1 AND nurse_id = $2
      RETURNING id
    `, [patientUserId, nurseId]);

    if (!res.rowCount) throw new NotFoundException({ code: 'FAVORITE_NOT_FOUND' });
    return { ok: true };
  }

  /** Lists favorite nurses with Bayesian average rating, excluding any blocked */
  async listFavorites(patientUserId: string) {
    const res = await this.db.query(`
      SELECT n.id AS nurse_id, n.verified, n.availability_intent,
             pfn.created_at AS favorited_at,
             (
               SELECT coalesce(round(avg(vr.stars)::numeric, 1), 5.0)
               FROM request_assignments ra
               JOIN visits v ON v.assignment_id = ra.id
               JOIN visit_reviews vr ON vr.visit_id = v.id AND vr.reviewer_role = 'PATIENT'
               WHERE ra.nurse_id = n.id
             ) AS rating,
             (
               SELECT count(*)::int
               FROM request_assignments ra
               JOIN visits v ON v.assignment_id = ra.id
               JOIN visit_reviews vr ON vr.visit_id = v.id AND vr.reviewer_role = 'PATIENT'
               WHERE ra.nurse_id = n.id
             ) AS review_count,
             (
               SELECT max(v.completed_at)
               FROM care_requests cr
               JOIN request_assignments ra ON ra.request_id = cr.id
               JOIN visits v ON v.assignment_id = ra.id
               WHERE cr.requester_user_id = $1 AND ra.nurse_id = n.id
             ) AS last_visit_at,
             (
               SELECT jsonb_agg(jsonb_build_object('id', s.id, 'titleAr', s.title_ar, 'code', s.code))
               FROM nurse_skills ns
               JOIN services s ON s.id = ns.service_id
               WHERE ns.nurse_id = n.id AND ns.approved = true
             ) AS offered_services
      FROM patient_favorite_nurses pfn
      JOIN nurses n ON n.id = pfn.nurse_id
      JOIN users u ON u.id = n.user_id AND u.status = 'ACTIVE'
      WHERE pfn.patient_user_id = $1
        AND NOT EXISTS (
          SELECT 1 FROM user_blocks ub
          WHERE ((ub.blocker_user_id = $1 AND ub.blocked_user_id = n.user_id)
             OR (ub.blocker_user_id = n.user_id AND ub.blocked_user_id = $1))
            AND ub.revoked_at IS NULL
        )
      ORDER BY pfn.created_at DESC
    `, [patientUserId]);

    return res.rows;
  }
}
