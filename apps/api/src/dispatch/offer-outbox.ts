import type { PoolClient } from 'pg';

export async function closeOpenOffers(
  client: PoolClient, requestId: string, reason: 'ASSIGNED' | 'CANCELLED', winnerId?: string,
): Promise<void> {
  await client.query(`
    WITH closed AS (
      UPDATE request_offers SET status=CASE WHEN id=$3::uuid THEN 'ACCEPTED' ELSE 'CLOSED' END
      WHERE request_id=$1 AND status='OPEN'
      RETURNING id,nurse_id,status
    )
    INSERT INTO outbox_events(event_type,aggregate_id,payload)
    SELECT 'offer.closed',$1,jsonb_build_object(
      'eventType','offer.closed',
      'requestId',$1::uuid,
      'offerId',c.id,
      'reason',$2::text,
      'recipientUserId',n.user_id,
      'recipientRole','NURSE',
      'targetApp','NURSE_APP',
      'priority','HIGH',
      'createdAt',statement_timestamp()
    )
    FROM closed c JOIN nurses n ON n.id=c.nurse_id WHERE c.status='CLOSED'
  `, [requestId, reason, winnerId ?? null]);
}
