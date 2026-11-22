import { Controller, Get, Param, Query, Request, UseGuards } from '@nestjs/common';
import { AuthGuard, AuthRequest, requireRole } from '../auth/auth.guard.js';
import { DbService } from '../db/db.service.js';
import { missing } from '../common/errors.js';

@Controller('v1/admin')
@UseGuards(AuthGuard)
export class AdminDispatchController {
  constructor(private readonly db: DbService) {}

  @Get('dispatch/diagnostics')
  async diagnostics(@Request() r: AuthRequest) {
    requireRole(r.user!, 'ADMIN');

    // 1. Live Counters
    const [counts, nurseStats, deliveryStats] = await Promise.all([
      this.db.query(`
        SELECT
          (SELECT count(*)::int FROM care_requests WHERE status = 'OFFERING') AS active_searches,
          (SELECT count(*)::int FROM care_requests WHERE status = 'UNFULFILLED' AND created_at >= now() - interval '24 hours') AS unfulfilled_24h,
          (SELECT count(*)::int FROM request_offers WHERE created_at >= date_trunc('day', now())) AS offers_today,
          (SELECT count(*)::int FROM request_offers WHERE status = 'ACCEPTED' AND created_at >= date_trunc('day', now())) AS offers_accepted_today,
          (SELECT count(*)::int FROM request_offers WHERE status = 'EXPIRED' AND created_at >= date_trunc('day', now())) AS offers_expired_today,
          (SELECT count(*)::int FROM outbox_events WHERE created_at >= date_trunc('day', now())) AS realtime_events_today,
          (SELECT count(*)::int FROM outbox_events WHERE realtime_published_at IS NULL) AS unpublished_realtime,
          (SELECT count(*)::int FROM outbox_events WHERE push_published_at IS NULL) AS unpublished_push
      `),
      this.db.query(`
        SELECT
          count(*)::int AS total_nurses,
          count(*) FILTER (WHERE n.availability_intent = 'AVAILABLE')::int AS available_nurses,
          count(*) FILTER (WHERE n.verified = true)::int AS verified_nurses,
          count(*) FILTER (WHERE n.verified = false)::int AS unverified_nurses,
          count(*) FILTER (WHERE n.availability_intent = 'AVAILABLE' AND n.last_heartbeat_at > now() - interval '60 seconds')::int AS fresh_heartbeat_nurses,
          count(*) FILTER (WHERE n.availability_intent = 'AVAILABLE' AND (n.last_heartbeat_at <= now() - interval '60 seconds' OR n.last_heartbeat_at IS NULL))::int AS stale_heartbeat_nurses,
          count(*) FILTER (WHERE n.availability_intent = 'AVAILABLE' AND nl.recorded_at > now() - interval '120 seconds' AND nl.accuracy_m <= 150)::int AS fresh_location_nurses,
          count(*) FILTER (WHERE n.availability_intent = 'AVAILABLE' AND (nl.recorded_at <= now() - interval '120 seconds' OR nl.recorded_at IS NULL OR nl.accuracy_m > 150))::int AS stale_location_nurses,
          count(*) FILTER (
            WHERE n.verified = true
              AND n.availability_intent = 'AVAILABLE'
              AND n.work_status = 'AVAILABLE'
              AND n.last_heartbeat_at > now() - interval '60 seconds'
              AND nl.recorded_at > now() - interval '120 seconds'
              AND nl.accuracy_m <= 150
              AND EXISTS (SELECT 1 FROM nurse_credentials nc WHERE nc.nurse_id = n.id AND nc.approved = true AND nc.expires_at > now())
              AND EXISTS (SELECT 1 FROM nurse_skills ns WHERE ns.nurse_id = n.id AND ns.approved = true)
          )::int AS ready_nurses
        FROM nurses n
        LEFT JOIN nurse_locations nl ON nl.nurse_id = n.id
      `),
      this.db.query(`
        SELECT
          count(*)::int AS push_attempts_today,
          count(*) FILTER (WHERE status = 'SENT')::int AS push_sent_today,
          count(*) FILTER (WHERE status = 'FAILED')::int AS push_failed_today,
          count(*) FILTER (WHERE status = 'UNREGISTERED')::int AS push_unregistered_today,
          count(*) FILTER (WHERE status = 'PENDING')::int AS push_pending
        FROM notification_deliveries
        WHERE created_at >= date_trunc('day', now())
      `),
    ]);

    // 2. Recent dispatch run logs
    const recentLogs = await this.db.query(`
      SELECT dd.id, dd.request_id, dd.wave_no, dd.radius_m, dd.candidates_found, dd.offers_created,
             dd.exclusion_reasons, dd.excluded_nurses, dd.created_at,
             cr.status AS request_status, s.title_ar AS service_title
      FROM dispatch_diagnostics dd
      JOIN care_requests cr ON cr.id = dd.request_id
      JOIN services s ON s.id = cr.service_id
      ORDER BY dd.created_at DESC
      LIMIT 30
    `);

    // 3. Worker & System health determination
    const lastJobRun = await this.db.query(`SELECT max(updated_at) AS last_dispatch FROM dispatch_jobs`);
    const lastOutbox = await this.db.query(`SELECT max(created_at) AS last_event FROM outbox_events`);

    return {
      metrics: {
        ...counts.rows[0],
        ...nurseStats.rows[0],
        ...deliveryStats.rows[0],
      },
      worker: {
        status: 'RUNNING',
        lastDispatchAt: lastJobRun.rows[0]?.last_dispatch,
        lastEventAt: lastOutbox.rows[0]?.last_event,
      },
      recentLogs: recentLogs.rows,
    };
  }

  @Get('dispatch/requests/:id')
  async requestDiagnostics(@Request() r: AuthRequest, @Param('id') id: string) {
    requireRole(r.user!, 'ADMIN');

    // 1. Care request info
    const req = await this.db.query(`
      SELECT cr.id, cr.status, cr.address_text, cr.price_amount, cr.currency_code,
             cr.created_at, cr.updated_at,
             s.title_ar AS service_title, s.code AS service_code,
             u.display_name AS requester_name, u.phone_e164 AS requester_phone,
             dj.next_wave, dj.next_run_at
      FROM care_requests cr
      JOIN services s ON s.id = cr.service_id
      JOIN users u ON u.id = cr.requester_user_id
      LEFT JOIN dispatch_jobs dj ON dj.request_id = cr.id
      WHERE cr.id = $1
    `, [id]);
    if (!req.rowCount) missing();

    // 2. Diagnostics per wave
    const diag = await this.db.query(`
      SELECT id, wave_no, radius_m, candidates_found, offers_created, exclusion_reasons, excluded_nurses, created_at
      FROM dispatch_diagnostics
      WHERE request_id = $1
      ORDER BY wave_no ASC, created_at ASC
    `, [id]);

    // 3. Offers created
    const offers = await this.db.query(`
      SELECT ro.id, ro.wave_no, ro.status, ro.created_at, ro.expires_at,
             n.id AS nurse_id, u.display_name AS nurse_name, u.phone_e164 AS nurse_phone
      FROM request_offers ro
      JOIN nurses n ON n.id = ro.nurse_id
      JOIN users u ON u.id = n.user_id
      WHERE ro.request_id = $1
      ORDER BY ro.wave_no ASC, ro.created_at ASC
    `, [id]);

    // 4. Realtime & FCM Deliveries for this request
    const deliveries = await this.db.query(`
      SELECT nd.id, nd.channel, nd.status, nd.attempts, nd.last_error_code, nd.last_error_detail,
             nd.created_at, nd.sent_at, u.display_name AS recipient_name
      FROM notification_deliveries nd
      JOIN outbox_events oe ON oe.id = nd.event_id
      JOIN users u ON u.id = nd.recipient_user_id
      WHERE oe.aggregate_id = $1
      ORDER BY nd.created_at DESC
    `, [id]);

    return {
      request: req.rows[0],
      diagnostics: diag.rows,
      offers: offers.rows,
      deliveries: deliveries.rows,
    };
  }

  @Get('notifications/health')
  async notificationHealth(@Request() r: AuthRequest) {
    requireRole(r.user!, 'ADMIN');

    // Determine FCM configured status
    const fcmConfigured = Boolean(
      process.env.FCM_SERVICE_ACCOUNT_JSON?.trim() ||
      process.env.FCM_SERVICE_ACCOUNT_FILE?.trim()
    );

    const [tokenStats, deliveryStats, recentErrors] = await Promise.all([
      this.db.query(`
        SELECT platform, count(*)::int AS count
        FROM device_tokens
        GROUP BY platform
      `),
      this.db.query(`
        SELECT status, count(*)::int AS count
        FROM notification_deliveries
        WHERE created_at >= date_trunc('day', now())
        GROUP BY status
      `),
      this.db.query(`
        SELECT id, channel, status, last_error_code, last_error_detail, created_at
        FROM notification_deliveries
        WHERE status = 'FAILED'
        ORDER BY created_at DESC
        LIMIT 10
      `),
    ]);

    const platformCounts: Record<string, number> = {};
    for (const row of tokenStats.rows) platformCounts[row.platform] = row.count;

    const deliveryCounts: Record<string, number> = {};
    for (const row of deliveryStats.rows) deliveryCounts[row.status] = row.count;

    return {
      status: fcmConfigured ? 'FCM_READY' : 'FCM_NOT_CONFIGURED',
      configured: fcmConfigured,
      platformTokens: platformCounts,
      todayDeliveries: deliveryCounts,
      recentErrors: recentErrors.rows,
    };
  }

  @Get('dispatch/export')
  async exportTechnicalReport(@Request() r: AuthRequest, @Query('hours') hours?: string) {
    requireRole(r.user!, 'ADMIN');
    const h = parseInt(hours || '24', 10) || 24;

    const rows = await this.db.query(`
      SELECT dd.id, dd.wave_no, dd.radius_m, dd.candidates_found, dd.offers_created,
             dd.exclusion_reasons, dd.created_at,
             cr.status AS request_status, s.code AS service_code
      FROM dispatch_diagnostics dd
      JOIN care_requests cr ON cr.id = dd.request_id
      JOIN services s ON s.id = cr.service_id
      WHERE dd.created_at >= now() - ($1 || ' hours')::interval
      ORDER BY dd.created_at DESC
    `, [h]);

    return {
      exportedAt: new Date().toISOString(),
      timeframeHours: h,
      recordCount: rows.rowCount,
      records: rows.rows,
    };
  }
}
