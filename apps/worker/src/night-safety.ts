import type pg from 'pg';

export const nightPolicyEnabled = () => process.env.GUARDIAN_NIGHT_POLICY_ENABLED === 'true';

export async function closeNightIneligibleOffers(pool: pg.Pool): Promise<boolean> {
  const result = await pool.query(`WITH candidates AS (
    SELECT o.id,guardian_night_denial(o.nurse_id,r.service_id,statement_timestamp()) AS reason FROM request_offers o JOIN care_requests r ON r.id=o.request_id
    WHERE o.status='OPEN' AND o.expires_at>clock_timestamp() AND r.status='OFFERING'
      AND guardian_night_denial(o.nurse_id,r.service_id,statement_timestamp()) IS NOT NULL
    ORDER BY o.id LIMIT 100 FOR UPDATE OF o SKIP LOCKED
  ), closed AS (
    UPDATE request_offers o SET status='CLOSED' FROM candidates c
    WHERE o.id=c.id RETURNING o.id,o.request_id,o.nurse_id,c.reason
  )
  INSERT INTO outbox_events(event_type,aggregate_id,payload)
  SELECT 'offer.closed',c.request_id,jsonb_build_object('offerId',c.id,'requestId',c.request_id,'recipientUserId',n.user_id,'reason',c.reason)
  FROM closed c JOIN nurses n ON n.id=c.nurse_id`);
  return Boolean(result.rowCount);
}
