import { collectDispatchCandidates } from './dispatch-candidates.ts';
import type pg from 'pg';
import { featureCapabilities } from '../../../packages/backend-policy/capabilities.mjs';

const reconcileSeconds = 5;

/** Caller holds the request row lock. Every offer shares the persisted server deadline. */
export async function runOpenSearch(client: pg.PoolClient, requestId: string): Promise<void> {
  if (!featureCapabilities().openDispatchEnabled) return;
  const closed = await client.query(`
    UPDATE care_requests SET status='UNFULFILLED', version=version+1,
      closed_at=statement_timestamp(), close_reason='EXPIRED', updated_at=statement_timestamp()
    WHERE id=$1 AND status='OFFERING' AND search_expires_at <= statement_timestamp()
    RETURNING requester_user_id
  `, [requestId]);

  if (closed.rowCount) {
    await client.query(`
      WITH expired AS (
        UPDATE request_offers SET status='EXPIRED' WHERE request_id=$1 AND status='OPEN'
        RETURNING id,nurse_id
      )
      INSERT INTO outbox_events(event_type,aggregate_id,payload)
      SELECT 'offer.expired',$1,jsonb_build_object(
        'eventType','offer.expired','requestId',$1::uuid,'offerId',e.id,
        'recipientUserId',n.user_id,'recipientRole','NURSE','targetApp','NURSE_APP','priority','HIGH')
      FROM expired e JOIN nurses n ON n.id=e.nurse_id
    `,[requestId]);
    await client.query('DELETE FROM dispatch_jobs WHERE request_id=$1', [requestId]);
    await client.query(`
      INSERT INTO request_events(request_id,event_type) VALUES($1,'request.unfulfilled');
    `, [requestId]);
    await client.query(`
      INSERT INTO outbox_events(event_type,aggregate_id,payload)
      VALUES('request.unfulfilled',$1,jsonb_build_object(
        'eventType','request.unfulfilled','requestId',$1::uuid,'recipientUserId',$2::uuid,
        'recipientRole','PATIENT','targetApp','PATIENT_APP','priority','HIGH',
        'deepLink','tamreedy://patient/requests/' || $1::text))
    `, [requestId, closed.rows[0].requester_user_id]);
    return;
  }

  const request=(await client.query('SELECT search_radius_meters FROM care_requests WHERE id=$1',[requestId])).rows[0];
  const snapshot = await collectDispatchCandidates(client, requestId, Number(request?.search_radius_meters ?? 10000));
  const recipients = snapshot.filter(candidate => !candidate.reasons.length && !candidate.alreadyOffered)
    .map(candidate => candidate.nurseId);
  const offers = await client.query(`
    WITH inserted AS (
      INSERT INTO request_offers(request_id,nurse_id,wave_no,expires_at)
      SELECT r.id,candidate.id,1,r.search_expires_at
      FROM care_requests r CROSS JOIN unnest($2::uuid[]) AS candidate(id)
      WHERE r.id=$1 AND r.status='OFFERING' AND r.search_expires_at>statement_timestamp()
      ON CONFLICT(request_id,nurse_id) DO NOTHING
      RETURNING id,nurse_id,expires_at
    )
    INSERT INTO outbox_events(event_type,aggregate_id,payload)
    SELECT 'offer.created',$1,jsonb_build_object(
      'eventType','offer.created','requestId',$1::uuid,'offerId',i.id,'recipientUserId',n.user_id,
      'recipientRole','NURSE','targetApp','NURSE_APP','expiresAt',i.expires_at,
      'priority','CRITICAL','deepLink','tamreedy://nurse/offers/' || i.id::text,'createdAt',statement_timestamp())
    FROM inserted i JOIN nurses n ON n.id=i.nurse_id
  `, [requestId, recipients]);

  if ((offers.rowCount ?? 0) > 0) {
    console.info(`[Dispatch] Open search ${requestId} created ${offers.rowCount} offers`);
  }
  await client.query(`
    UPDATE dispatch_jobs j
    SET next_run_at=least(r.search_expires_at,statement_timestamp()+$2::integer*interval '1 second'),
      updated_at=statement_timestamp()
    FROM care_requests r WHERE r.id=j.request_id AND j.request_id=$1
  `, [requestId, reconcileSeconds]);
}
