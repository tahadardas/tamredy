import { nightPolicyEnabled } from './night-safety.ts';
import type pg from 'pg';

const reconcileSeconds = 5;

/** Caller holds the request row lock. Every offer shares the persisted server deadline. */
export async function runOpenSearch(client: pg.PoolClient, requestId: string): Promise<void> {
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
        'requestId',$1::uuid,'offerId',e.id,'recipientUserId',n.user_id)
      FROM expired e JOIN nurses n ON n.id=e.nurse_id
    `,[requestId]);
    await client.query('DELETE FROM dispatch_jobs WHERE request_id=$1', [requestId]);
    await client.query(`
      INSERT INTO request_events(request_id,event_type) VALUES($1,'request.unfulfilled');
    `, [requestId]);
    await client.query(`
      INSERT INTO outbox_events(event_type,aggregate_id,payload)
      VALUES('request.unfulfilled',$1,jsonb_build_object('requestId',$1::uuid,'recipientUserId',$2::uuid))
    `, [requestId, closed.rows[0].requester_user_id]);
    return;
  }

  const offers = await client.query(`
    WITH candidates AS (
      SELECT n.id, r.search_expires_at
      FROM care_requests r
      JOIN nurse_locations l ON ST_DWithin(l.location,r.location,r.search_radius_meters)
      JOIN nurses n ON n.id=l.nurse_id AND n.verified AND n.work_status='AVAILABLE' AND n.availability_intent='AVAILABLE'
      JOIN users u ON u.id=n.user_id AND u.status='ACTIVE'
      JOIN nurse_skills k ON k.nurse_id=n.id AND k.service_id=r.service_id AND k.approved
      LEFT JOIN pricing_settings ps ON ps.id=1
      WHERE r.id=$1 AND r.status='OFFERING' AND r.search_expires_at > statement_timestamp()
        ${nightPolicyEnabled() ? 'AND guardian_night_denial(n.id,r.service_id,statement_timestamp()) IS NULL' : ''}
        AND n.last_heartbeat_at > statement_timestamp()-r.search_max_heartbeat_seconds*interval '1 second'
        AND l.recorded_at > statement_timestamp()-r.search_max_location_seconds*interval '1 second'
        AND l.accuracy_m <= r.search_max_accuracy_meters
        AND EXISTS (SELECT 1 FROM nurse_credentials lic WHERE lic.nurse_id=n.id AND lic.approved AND lic.expires_at > statement_timestamp())
        AND NOT EXISTS (SELECT 1 FROM request_assignments a WHERE a.nurse_id=n.id AND a.status='ACTIVE')
        AND NOT EXISTS (SELECT 1 FROM request_offers o WHERE o.request_id=r.id AND o.nurse_id=n.id)
        AND (coalesce(ps.nurse_debt_limit,0) <= 0 OR (
          (SELECT coalesce(sum(cr.owed_to_company),0)
            FROM request_assignments a JOIN visits v ON v.assignment_id=a.id AND v.completed_at IS NOT NULL
            JOIN care_requests cr ON cr.id=a.request_id AND cr.payment_status='PAID'
            WHERE a.nurse_id=n.id)
          + (SELECT coalesce(sum(CASE WHEN s.direction='FROM_NURSE' THEN -s.amount ELSE s.amount END),0)
            FROM nurse_settlements s WHERE s.nurse_id=n.id)
        ) <= ps.nurse_debt_limit)
    ), inserted AS (
      INSERT INTO request_offers(request_id,nurse_id,wave_no,expires_at)
      SELECT $1,id,1,search_expires_at FROM candidates
      ON CONFLICT(request_id,nurse_id) DO NOTHING
      RETURNING id,nurse_id,expires_at
    )
    INSERT INTO outbox_events(event_type,aggregate_id,payload)
    SELECT 'offer.created',$1,jsonb_build_object(
      'requestId',$1::uuid,'offerId',i.id,'recipientUserId',n.user_id,'expiresAt',i.expires_at)
    FROM inserted i JOIN nurses n ON n.id=i.nurse_id
  `, [requestId]);

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
