import type pg from 'pg';

export async function expireVoiceCalls(pool: pg.Pool): Promise<boolean> {
  const result = await pool.query(
    `WITH expired AS (
       UPDATE voice_call_sessions SET
         call_status=CASE WHEN call_status IN ('INITIATED','RINGING') THEN 'MISSED' ELSE 'FAILED' END,
         ended_at=statement_timestamp(),
         end_reason=CASE WHEN call_status IN ('INITIATED','RINGING') THEN 'RING_TIMEOUT' ELSE 'CONNECT_TIMEOUT' END,
         session_version=session_version+1
       WHERE (call_status IN ('INITIATED','RINGING') AND ring_expires_at<=statement_timestamp())
          OR (call_status IN ('ACCEPTED','CONNECTING') AND accepted_at<statement_timestamp()-interval '90 seconds')
       RETURNING id,request_id,caller_user_id,receiver_user_id,call_status,end_reason
     ), events AS (
       INSERT INTO outbox_events(event_type,aggregate_id,payload)
       SELECT CASE WHEN call_status='MISSED' THEN 'call.missed' ELSE 'call.failed' END,id,
         jsonb_build_object(
           'eventType',CASE WHEN call_status='MISSED' THEN 'call.missed' ELSE 'call.failed' END,
           'recipientUserIds',ARRAY[caller_user_id,receiver_user_id],
           'callId',id,'requestId',request_id,'reason',end_reason,
           'priority','HIGH')
       FROM expired RETURNING aggregate_id
     ), removed AS (
       DELETE FROM voice_call_events e USING expired x
       WHERE e.session_id=x.id AND e.event_type IN ('SDP_OFFER','SDP_ANSWER','ICE_CANDIDATE','ICE_RESTART')
       RETURNING e.id
     ) SELECT count(*)::integer AS expired_count FROM events`,
  );
  await pool.query(
    `DELETE FROM voice_call_events WHERE event_type IN ('SDP_OFFER','SDP_ANSWER','ICE_CANDIDATE','ICE_RESTART')
     AND created_at<statement_timestamp()-interval '24 hours'`,
  );
  return Number(result.rows[0]?.expired_count ?? 0) > 0;
}
