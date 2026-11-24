import type pg from 'pg';

export async function releaseScheduledVisit(pool: pg.Pool): Promise<boolean> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const visit = (await client.query(`SELECT r.id,r.requester_user_id,s.appointment_at<=now() AS expired
      FROM scheduled_visits s JOIN care_requests r ON r.id=s.request_id
      WHERE s.released_at IS NULL AND s.release_at<=now() AND r.status='SCHEDULED'
      ORDER BY s.release_at,r.id LIMIT 1 FOR UPDATE OF r SKIP LOCKED`)).rows[0];
    if (!visit) {
      await client.query('COMMIT');
      return false;
    }
    const orders = (await client.query("SELECT value FROM app_settings WHERE key='orders'")).rows[0]?.value;
    if (!visit.expired && orders?.accepting === false) {
      await client.query('COMMIT');
      return false;
    }
    const policy = (await client.query("SELECT value FROM app_settings WHERE key='dispatch'")).rows[0]?.value;
    const open = !visit.expired && process.env.OPEN_DISPATCH_ENABLED === 'true' && policy?.openEnabled === true;
    await client.query(`UPDATE care_requests SET status=$8,version=version+1,
      search_started_at=CASE WHEN $2 THEN statement_timestamp() END,
      search_expires_at=CASE WHEN $2 THEN statement_timestamp()+$3::integer*interval '1 second' END,
      search_radius_meters=CASE WHEN $2 THEN $4::integer END,
      search_max_heartbeat_seconds=CASE WHEN $2 THEN $5::integer END,
      search_max_location_seconds=CASE WHEN $2 THEN $6::integer END,
      search_max_accuracy_meters=CASE WHEN $2 THEN $7::integer END WHERE id=$1`,
    [visit.id, open, policy?.offerDurationSeconds ?? 60, policy?.radiusMeters ?? 10000,
      policy?.maxHeartbeatAgeSeconds ?? 60, policy?.maxLocationAgeSeconds ?? 120,
      policy?.maxLocationAccuracyMeters ?? 100, visit.expired ? 'UNFULFILLED' : 'OFFERING']);
    await client.query('UPDATE scheduled_visits SET released_at=now() WHERE request_id=$1', [visit.id]);
    if (!visit.expired) await client.query('INSERT INTO dispatch_jobs(request_id) VALUES($1)', [visit.id]);
    const event = visit.expired ? 'request.unfulfilled' : 'request.schedule_released';
    await client.query(`INSERT INTO request_events(request_id,event_type)
      VALUES($1,$2)`, [visit.id, event]);
    await client.query(`INSERT INTO outbox_events(event_type,aggregate_id,payload)
      VALUES($3,$1,$2::jsonb)`,
    [visit.id, JSON.stringify({ recipientUserId: visit.requester_user_id, requestId: visit.id }), event]);
    await client.query('COMMIT');
    return true;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}
