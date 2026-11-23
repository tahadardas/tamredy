import type pg from 'pg';

export async function notifyDelayedDepartures(db: pg.Pool): Promise<boolean> {
  const result = await db.query(`
    WITH due AS (
      SELECT a.id
      FROM request_assignments a JOIN care_requests r ON r.id=a.request_id
      WHERE r.status='ASSIGNED' AND a.status='ACTIVE' AND a.departed_at IS NULL
        AND a.departure_alerted_at IS NULL AND a.departure_due_at<=statement_timestamp()
      ORDER BY a.departure_due_at,a.id LIMIT 50 FOR UPDATE OF r SKIP LOCKED
    ), alerted AS (
      UPDATE request_assignments a SET departure_alerted_at=statement_timestamp()
      FROM due WHERE a.id=due.id AND a.departure_alerted_at IS NULL AND a.departed_at IS NULL
      RETURNING a.request_id,a.nurse_id
    )
    INSERT INTO outbox_events(event_type,aggregate_id,payload)
    SELECT 'visit.departure_delayed',a.request_id,jsonb_build_object(
      'requestId',a.request_id,'recipientUserId',n.user_id,
      'recipientUserIds',coalesce((SELECT jsonb_agg(id) FROM users WHERE role='ADMIN' AND status='ACTIVE'),'[]'::jsonb))
    FROM alerted a JOIN nurses n ON n.id=a.nurse_id
  `);
  return (result.rowCount ?? 0) > 0;
}
