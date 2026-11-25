import { randomUUID } from 'node:crypto';
import type pg from 'pg';
import type { OutboxEvent } from './push.js';

export async function deliverOutbox(
  db: pg.Pool, channel: 'push' | 'realtime',
  deliver: (events: OutboxEvent[]) => Promise<void>,
): Promise<boolean> {
  const token = randomUUID();
  const claim = await db.query<OutboxEvent>(`
    WITH due AS (
      SELECT id FROM outbox_events
      WHERE ${channel}_published_at IS NULL
        AND ${channel}_dead_at IS NULL
        AND (${channel}_lease_until IS NULL OR ${channel}_lease_until<=statement_timestamp())
      ORDER BY id LIMIT 20 FOR UPDATE SKIP LOCKED
    )
    UPDATE outbox_events e SET ${channel}_lease_token=$1,
      ${channel}_lease_until=statement_timestamp()+interval '3 minutes'
    FROM due WHERE e.id=due.id RETURNING e.id,e.event_type,e.payload
  `, [token]);
  if (!claim.rowCount) return false;
  const events = claim.rows.sort((a,b) => BigInt(a.id) < BigInt(b.id) ? -1 : 1);
  const ids = events.map(event => String(event.id));
  // No database session or row lock is held while contacting external services.
  try {
    await deliver(events);
  } catch (error) {
    await db.query(`
      UPDATE outbox_events SET
        ${channel}_attempts=${channel}_attempts+1,
        ${channel}_dead_at=CASE WHEN ${channel}_attempts+1>=12 THEN statement_timestamp() END,
        ${channel}_lease_token=NULL,
        ${channel}_lease_until=statement_timestamp()
          + (least(600,power(2,least(10,${channel}_attempts+1)))+random()*2)*interval '1 second'
      WHERE id=ANY($1::bigint[]) AND ${channel}_lease_token=$2
    `,[ids,token]);
    throw error;
  }
  await db.query(`
    UPDATE outbox_events SET ${channel}_published_at=statement_timestamp(),
      ${channel}_lease_token=NULL,${channel}_lease_until=NULL
    WHERE id = ANY($1::bigint[]) AND ${channel}_lease_token=$2
  `,[ids,token]);
  return true;
}
