import { Injectable } from '@nestjs/common';
import { DbService } from '../db/db.service.js';

@Injectable()
export class AdminBookingService {
  constructor(private readonly db: DbService) {}

  /**
   * Retrieves current booking & marketplace policies.
   */
  async getPolicies() {
    const res = await this.db.query(`SELECT value FROM app_settings WHERE key = 'booking_policies'`);
    const val = (res.rows[0]?.value ?? {}) as Record<string, any>;
    return {
      instantEnabled: true,
      openMarketplaceEnabled: true,
      scheduledBookingEnabled: true,
      allowModeConversion: true,
      instantSearchTimeoutSeconds: 60,
      openRequestDurationMinutes: 120,
      proposalDurationMinutes: 5,
      maxConcurrentProposalsPerNurse: 5,
      smartRecoveryEnabled: true,
      recoveryCooldownMinutes: 15,
      recoveryMaxDaily: 8,
      recoveryAggregationSeconds: 60,
      ...val,
      // Provide snake_case aliases for frontend form inputs
      instant_search_timeout_seconds: val.instant_search_timeout_seconds ?? val.instantSearchTimeoutSeconds ?? 60,
      open_marketplace_default_duration_minutes: val.open_marketplace_default_duration_minutes ?? val.openRequestDurationMinutes ?? 120,
      max_wait_extension_minutes: val.max_wait_extension_minutes ?? 120,
      max_active_proposals_per_nurse: val.max_active_proposals_per_nurse ?? val.maxConcurrentProposalsPerNurse ?? 5,
      quiet_recovery_cooldown_minutes: val.quiet_recovery_cooldown_minutes ?? val.recoveryCooldownMinutes ?? 15,
      quiet_recovery_daily_limit: val.quiet_recovery_daily_limit ?? val.recoveryMaxDaily ?? 8,
    };
  }

  /**
   * Updates booking & marketplace policies.
   */
  async updatePolicies(userId: string, update: Record<string, unknown>) {
    const current = await this.getPolicies();
    const merged: Record<string, any> = { ...current, ...update };

    // Synchronize both naming conventions if present
    if (update.instant_search_timeout_seconds !== undefined) {
      merged.instantSearchTimeoutSeconds = update.instant_search_timeout_seconds;
    }
    if (update.open_marketplace_default_duration_minutes !== undefined) {
      merged.openRequestDurationMinutes = update.open_marketplace_default_duration_minutes;
    }
    if (update.max_active_proposals_per_nurse !== undefined) {
      merged.maxConcurrentProposalsPerNurse = update.max_active_proposals_per_nurse;
    }
    if (update.quiet_recovery_cooldown_minutes !== undefined) {
      merged.recoveryCooldownMinutes = update.quiet_recovery_cooldown_minutes;
    }
    if (update.quiet_recovery_daily_limit !== undefined) {
      merged.recoveryMaxDaily = update.quiet_recovery_daily_limit;
    }

    await this.db.query(
      `INSERT INTO app_settings(key, value)
       VALUES('booking_policies', $1::jsonb)
       ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value`,
      [JSON.stringify(merged)],
    );

    // Audit settings change in outbox_events with a valid UUID aggregate_id
    await this.db.query(
      `INSERT INTO outbox_events(event_type, aggregate_id, payload)
       VALUES('admin.booking_policies.updated', gen_random_uuid(), $1::jsonb)`,
      [JSON.stringify({ updatedBy: userId, policies: merged, timestamp: new Date() })],
    );

    // Also record in administrative audit_log
    await this.db.query(
      `INSERT INTO audit_log(actor_user_id, action, target_type, target_id, detail)
       VALUES($1, 'settings.changed', 'booking_policies', gen_random_uuid(), $2::jsonb)`,
      [userId, JSON.stringify({ key: 'booking_policies', value: merged })],
    );

    return merged;
  }

  /**
   * Admin lists requests across all booking modes with filters.
   */
  async listRequests(filters?: { bookingMode?: string; status?: string; limit?: number }) {
    const limit = Math.min(filters?.limit ?? 50, 100);
    let sql = `
      SELECT cr.id, cr.booking_mode, cr.original_booking_mode, cr.status, cr.marketplace_status,
             cr.price_amount, cr.currency_code, cr.created_at, cr.open_expires_at,
             cr.latest_acceptable_arrival_at, cr.published_at,
             s.title_ar AS service_title, s.code AS service_code,
             u.display_name AS requester_name, '***'||right(u.phone_e164,4) AS requester_phone,
             (SELECT count(*)::int FROM marketplace_proposals mp WHERE mp.request_id = cr.id) AS total_proposals_count,
             (SELECT count(*)::int FROM marketplace_proposals mp WHERE mp.request_id = cr.id AND mp.status = 'PENDING') AS active_proposals_count
      FROM care_requests cr
      JOIN services s ON s.id = cr.service_id
      JOIN users u ON u.id = cr.requester_user_id
      WHERE 1=1
    `;
    const params: unknown[] = [];
    if (filters?.bookingMode) {
      params.push(filters.bookingMode);
      sql += ` AND cr.booking_mode = $${params.length}`;
    }
    if (filters?.status) {
      params.push(filters.status);
      sql += ` AND cr.status = $${params.length}`;
    }
    params.push(limit);
    sql += ` ORDER BY cr.created_at DESC LIMIT $${params.length}`;

    const res = await this.db.query(sql, params);
    return res.rows;
  }

  /**
   * Admin lists nurse readiness proposals with filtering.
   */
  async listProposals(filters?: { status?: string; requestId?: string; nurseId?: string }) {
    let sql = `
      SELECT mp.*,
             cr.booking_mode, cr.status AS request_status, cr.price_amount, cr.currency_code,
             s.title_ar AS service_title,
             nu.display_name AS nurse_name, '***'||right(nu.phone_e164,4) AS nurse_phone,
             pu.display_name AS patient_name
      FROM marketplace_proposals mp
      JOIN care_requests cr ON cr.id = mp.request_id
      JOIN services s ON s.id = cr.service_id
      JOIN nurses n ON n.id = mp.nurse_id
      JOIN users nu ON nu.id = n.user_id
      JOIN users pu ON pu.id = cr.requester_user_id
      WHERE 1=1
    `;
    const params: unknown[] = [];
    if (filters?.status) {
      params.push(filters.status);
      sql += ` AND mp.status = $${params.length}`;
    }
    if (filters?.requestId) {
      params.push(filters.requestId);
      sql += ` AND mp.request_id = $${params.length}`;
    }
    if (filters?.nurseId) {
      params.push(filters.nurseId);
      sql += ` AND mp.nurse_id = $${params.length}`;
    }
    sql += ` ORDER BY mp.created_at DESC LIMIT 100`;

    const res = await this.db.query(sql, params);
    return res.rows;
  }

  /**
   * Admin Booking & Recovery Analytics.
   */
  async getAnalytics() {
    const statsRes = await this.db.query(`
      SELECT
        count(*)::int AS total_requests,
        count(*) FILTER (WHERE booking_mode = 'INSTANT')::int AS instant_requests,
        count(*) FILTER (WHERE booking_mode = 'OPEN' AND original_booking_mode = 'OPEN')::int AS direct_open_requests,
        count(*) FILTER (WHERE booking_mode = 'OPEN' AND original_booking_mode = 'INSTANT')::int AS converted_instant_to_open,
        count(*) FILTER (WHERE booking_mode = 'SCHEDULED')::int AS scheduled_requests,
        count(*) FILTER (WHERE booking_mode = 'INSTANT' AND status IN ('ASSIGNED', 'EN_ROUTE', 'ARRIVED', 'IN_SERVICE', 'COMPLETED'))::int AS instant_assigned,
        count(*) FILTER (WHERE booking_mode = 'OPEN' AND original_booking_mode = 'INSTANT' AND status IN ('ASSIGNED', 'EN_ROUTE', 'ARRIVED', 'IN_SERVICE', 'COMPLETED'))::int AS recovered_assigned,
        count(*) FILTER (WHERE booking_mode = 'OPEN' AND original_booking_mode = 'INSTANT' AND status = 'COMPLETED')::int AS recovered_completed,
        count(*) FILTER (WHERE status = 'UNFULFILLED' OR (status = 'EXPIRED' AND booking_mode = 'OPEN'))::int AS unfulfilled_total
      FROM care_requests
    `);
    const s = statsRes.rows[0];

    const instantTotal = Number(s.instant_requests) || 1;
    const convertedTotal = Number(s.converted_instant_to_open) || 1;

    const instantAssignmentRate = Math.round((Number(s.instant_assigned) / instantTotal) * 100);
    const openMarketplaceRecoveryRate = Math.round((Number(s.recovered_assigned) / convertedTotal) * 100);
    const recoveredCompletionRate = Math.round((Number(s.recovered_completed) / convertedTotal) * 100);

    const proposalsStats = (await this.db.query(`
      SELECT
        count(*)::int AS total_proposals,
        count(*) FILTER (WHERE status = 'ACCEPTED')::int AS accepted_proposals,
        count(*) FILTER (WHERE status = 'PENDING')::int AS pending_proposals,
        round(avg(estimated_nurse_earning), 2) AS avg_nurse_earning
      FROM marketplace_proposals
    `)).rows[0];

    return {
      overview: {
        totalRequests: Number(s.total_requests),
        instantRequests: Number(s.instant_requests),
        directOpenRequests: Number(s.direct_open_requests),
        convertedInstantToOpen: Number(s.converted_instant_to_open),
        scheduledRequests: Number(s.scheduled_requests),
        unfulfilledTotal: Number(s.unfulfilled_total),
      },
      rates: {
        instantAssignmentRate: `${instantAssignmentRate}%`,
        openMarketplaceRecoveryRate: `${openMarketplaceRecoveryRate}%`,
        recoveredCompletionRate: `${recoveredCompletionRate}%`,
      },
      proposals: {
        total: Number(proposalsStats.total_proposals || 0),
        accepted: Number(proposalsStats.accepted_proposals || 0),
        pending: Number(proposalsStats.pending_proposals || 0),
        avgNurseEarning: Number(proposalsStats.avg_nurse_earning || 0),
      },
    };
  }
}
