import type pg from 'pg';

const defaultWaves = [
  { radius: 3000, seconds: 15 },
  { radius: 6000, seconds: 15 },
  { radius: 10000, seconds: 20 },
];

async function loadWaves(c: pg.PoolClient) {
  try {
    const r = await c.query(`SELECT value FROM app_settings WHERE key='dispatch'`);
    const w = r.rows[0]?.value?.waves;
    if (Array.isArray(w) && w.length >= 1 && w.length <= 5 && w.every((x: any) => x.radiusM > 0 && x.seconds > 0)) {
      return w.map((x: any) => ({ radius: Number(x.radiusM), seconds: Number(x.seconds) }));
    }
  } catch {}
  return defaultWaves;
}

/** Evaluates all potential nurses against dispatch criteria and returns diagnostic breakdown. */
async function diagnoseExclusions(c: pg.PoolClient, requestId: string, serviceId: string, radiusM: number) {
  const diagQuery = await c.query(`
    SELECT
      n.id AS nurse_id,
      'N-' || substring(n.id::text, 1, 6) AS nurse_code,
      CASE
        WHEN u.status <> 'ACTIVE' THEN 'ACCOUNT_INACTIVE'
        WHEN n.verified = false THEN 'NOT_VERIFIED'
        WHEN n.availability_intent != 'AVAILABLE' THEN 'NURSE_OFFLINE'
        WHEN n.work_status != 'AVAILABLE' THEN 'NURSE_BUSY'
        WHEN n.last_heartbeat_at IS NULL OR n.last_heartbeat_at <= now() - interval '120 seconds' THEN 'STALE_HEARTBEAT'
        WHEN nl.location IS NULL THEN 'NO_LOCATION'
        WHEN NOT EXISTS (SELECT 1 FROM nurse_credentials nc WHERE nc.nurse_id = n.id AND nc.approved = true AND nc.expires_at > now()) THEN 'LICENSE_NOT_APPROVED'
        WHEN NOT EXISTS (SELECT 1 FROM nurse_skills ns WHERE ns.nurse_id = n.id AND ns.service_id = $2 AND ns.approved = true) THEN 'SKILL_NOT_APPROVED'
        WHEN EXISTS (SELECT 1 FROM request_assignments a WHERE a.nurse_id = n.id AND a.status = 'ACTIVE') THEN 'ACTIVE_ASSIGNMENT'
        WHEN EXISTS (SELECT 1 FROM request_offers ro WHERE ro.request_id = $1 AND ro.nurse_id = n.id) THEN 'OFFER_ALREADY_SENT'
        WHEN NOT ST_DWithin(nl.location, req.location, $3::double precision) THEN 'OUTSIDE_RADIUS'
        ELSE 'ELIGIBLE'
      END AS status,
      CASE
        WHEN n.last_heartbeat_at IS NOT NULL THEN 'Heartbeat ' || EXTRACT(EPOCH FROM (now() - n.last_heartbeat_at))::int || 's ago'
        WHEN nl.recorded_at IS NOT NULL THEN 'Location ' || EXTRACT(EPOCH FROM (now() - nl.recorded_at))::int || 's ago'
        ELSE 'No active telemetry'
      END AS detail
    FROM nurses n JOIN users u ON u.id = n.user_id
    LEFT JOIN nurse_locations nl ON nl.nurse_id = n.id
    CROSS JOIN care_requests req
    WHERE req.id = $1
      AND (n.availability_intent = 'AVAILABLE' OR n.verified = true)
    LIMIT 100
  `, [requestId, serviceId, radiusM]);

  const reasons: Record<string, number> = {};
  const excludedNurses: { nurse_code: string; reason: string; detail: string }[] = [];

  for (const r of diagQuery.rows) {
    if (r.status !== 'ELIGIBLE') {
      reasons[r.status] = (reasons[r.status] ?? 0) + 1;
      if (excludedNurses.length < 15) {
        excludedNurses.push({ nurse_code: r.nurse_code, reason: r.status, detail: r.detail });
      }
    }
  }

  return { reasons, excludedNurses };
}

export async function doDispatch(pool: pg.Pool): Promise<boolean> {
  const c = await pool.connect();
  try {
    await c.query('BEGIN');
    const due = await c.query(`
      SELECT j.request_id, cr.status, cr.service_id, cr.requester_user_id
      FROM dispatch_jobs j JOIN care_requests cr ON cr.id = j.request_id
      WHERE j.next_run_at <= now()
      ORDER BY j.next_run_at, j.request_id LIMIT 1
      FOR UPDATE OF cr SKIP LOCKED
    `);

    if (!due.rowCount) {
      await c.query('COMMIT');
      return false;
    }

    const request = due.rows[0];
    const { request_id: requestId } = request;
    const job = await c.query(
      'SELECT next_wave FROM dispatch_jobs WHERE request_id=$1 AND next_run_at <= clock_timestamp()',
      [requestId],
    );
    if (!job.rowCount) {
      await c.query('COMMIT');
      return false;
    }
    const wave: number = job.rows[0].next_wave;

    if (request.status !== 'OFFERING') {
      await c.query('DELETE FROM dispatch_jobs WHERE request_id=$1', [requestId]);
      await c.query('COMMIT');
      return true;
    }

    const waveConfig = await loadWaves(c);
    if (wave > waveConfig.length) {
      console.log(`[Dispatch] Request ${requestId} exhausted all ${waveConfig.length} waves with no acceptance. Marking UNFULFILLED.`);
      await c.query(`UPDATE care_requests SET status='UNFULFILLED', version=version+1, updated_at=now() WHERE id=$1`, [requestId]);
      await c.query('DELETE FROM dispatch_jobs WHERE request_id=$1', [requestId]);
      await c.query(`UPDATE request_offers SET status='EXPIRED' WHERE request_id=$1 AND status='OPEN'`, [requestId]);
      await c.query(`
        INSERT INTO outbox_events(event_type, aggregate_id, payload)
        VALUES('request.unfulfilled', $1, $2::jsonb)
      `, [requestId, JSON.stringify({ requestId, recipientUserId: request.requester_user_id })]);
      await c.query('COMMIT');
      return true;
    }

    const cfg = waveConfig[wave - 1]!;
    await c.query(`UPDATE request_offers SET status='EXPIRED'
      WHERE request_id=$1 AND status='OPEN' AND expires_at <= now()`, [requestId]);

    // 1. Diagnostics: evaluate candidate pool and record exclusion reasons
    const diag = await diagnoseExclusions(c, requestId, request.service_id, cfg.radius);

    // 2. Offer the visit to every eligible nurse who has not already received it.
    const candidateOffers = await c.query(`
      WITH candidates AS (
        SELECT n.id, n.user_id FROM nurses n
        JOIN users u ON u.id = n.user_id AND u.status = 'ACTIVE'
        JOIN nurse_locations nl ON nl.nurse_id = n.id
        JOIN nurse_skills ns ON ns.nurse_id = n.id AND ns.service_id = $2 AND ns.approved = true
        JOIN care_requests req ON req.id = $1
        WHERE n.verified = true AND n.work_status = 'AVAILABLE' AND n.availability_intent = 'AVAILABLE'
          AND n.last_heartbeat_at > now() - interval '120 seconds'
          AND nl.location IS NOT NULL
          AND EXISTS (SELECT 1 FROM nurse_credentials nc
                     WHERE nc.nurse_id = n.id AND nc.approved = true AND nc.expires_at > now())
          AND NOT EXISTS (SELECT 1 FROM request_offers existing
                         WHERE existing.request_id = req.id AND existing.nurse_id = n.id)
          AND NOT EXISTS (SELECT 1 FROM request_assignments a
                         WHERE a.nurse_id = n.id AND a.status = 'ACTIVE')
          AND ST_DWithin(nl.location, req.location, $3::double precision)
      ), inserted AS (
        INSERT INTO request_offers(request_id, nurse_id, wave_no, expires_at)
        SELECT $1, id, $4, now() + ($5::integer * interval '1 second')
        FROM candidates
        ON CONFLICT(request_id, nurse_id) DO NOTHING
        RETURNING id, nurse_id, expires_at
      ), emitted AS (
        INSERT INTO outbox_events(event_type, aggregate_id, payload)
        SELECT 'offer.created', $1,
          jsonb_build_object('requestId', $1, 'offerId', i.id, 'recipientUserId', n.user_id, 'expiresAt', i.expires_at)
        FROM inserted i JOIN nurses n ON n.id = i.nurse_id
        RETURNING id
      ) SELECT count(*)::integer AS emitted_count FROM emitted
    `, [requestId, request.service_id, cfg.radius, wave, cfg.seconds]);

    const emittedCount = candidateOffers.rows[0]?.emitted_count ?? 0;

    // 3. Record diagnostic audit entry
    await c.query(`
      INSERT INTO dispatch_diagnostics(
        request_id, wave_no, radius_m, candidates_found, offers_created, exclusion_reasons, excluded_nurses
      ) VALUES($1, $2, $3, $4, $5, $6::jsonb, $7::jsonb)
    `, [requestId, wave, cfg.radius, emittedCount, emittedCount, JSON.stringify(diag.reasons), JSON.stringify(diag.excludedNurses)]);

    console.log(`[Dispatch] Request ${requestId} Wave ${wave}/${waveConfig.length} (r: ${cfg.radius}m): ${emittedCount} offers created. Excluded reasons: ${JSON.stringify(diag.reasons)}`);

    // 4. Advance dispatch job schedule for next wave
    await c.query(`
      UPDATE dispatch_jobs
      SET next_wave = $2, next_run_at = now() + ($3 || ' seconds')::interval, updated_at = now()
      WHERE request_id = $1
    `, [requestId, wave + 1, String(emittedCount > 0 ? cfg.seconds : 0)]);

    await c.query('COMMIT');
    return true;
  } catch (e) {
    await c.query('ROLLBACK');
    console.error('[Dispatch Error]', e);
    throw e;
  } finally {
    c.release();
  }
}
