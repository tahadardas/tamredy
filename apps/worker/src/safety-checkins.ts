import type pg from 'pg';

async function nurseEvent(client: pg.PoolClient, session: string, recipient: string, type: string) {
  await client.query(`INSERT INTO outbox_events(event_type,aggregate_id,payload)
    VALUES($3,$1,jsonb_build_object('sessionId',$1::uuid,'recipientUserId',$2::uuid))`, [session, recipient, type]);
}

export async function runSafetyCheckin(pool: pg.Pool): Promise<boolean> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const dueQuery = `SELECT s.id,n.user_id,v.interval_seconds,v.reminder_seconds,v.grace_seconds,
      c.id AS checkin_id,c.deadline_at<=clock_timestamp() AS missed
      FROM safety_sessions s JOIN safety_policy_versions v ON v.id=s.policy_version_id
      JOIN request_assignments a ON a.id=s.assignment_id JOIN nurses n ON n.id=a.nurse_id
      LEFT JOIN safety_checkins c ON c.session_id=s.id AND c.state='PENDING'
      WHERE s.checked_out_at IS NULL AND (c.deadline_at<=clock_timestamp() OR
        (s.started_at+interval '12 hours'>clock_timestamp() AND
          ((c.id IS NULL AND s.next_checkin_at<=clock_timestamp()) OR (c.reminded_at IS NULL AND c.remind_at<=clock_timestamp()))))`;
    const candidate = (await client.query(`${dueQuery}
      ORDER BY coalesce(c.deadline_at,s.next_checkin_at),s.id LIMIT 1 FOR UPDATE OF s SKIP LOCKED`)).rows[0];
    // Re-read after taking the session lock to use the latest prompt and response.
    const due = candidate && (await client.query(`${dueQuery} AND s.id=$1`, [candidate.id])).rows[0];
    if (!due) {
      await client.query('COMMIT');
      return false;
    }
    if (!due.checkin_id) {
      await client.query(`INSERT INTO safety_checkins(session_id,remind_at,deadline_at)
        VALUES($1,now()+$2::integer*interval '1 second',now()+($2::integer+$3::integer)*interval '1 second')`,
      [due.id, due.reminder_seconds, due.grace_seconds]);
      await client.query('UPDATE safety_sessions SET next_checkin_at=NULL WHERE id=$1', [due.id]);
      await nurseEvent(client, due.id, due.user_id, 'safety.checkin_due');
    } else if (due.missed) {
      await client.query("UPDATE safety_checkins SET state='MISSED' WHERE id=$1", [due.checkin_id]);
      await client.query(`UPDATE safety_sessions SET next_checkin_at=now()+$2::integer*interval '1 second'
        WHERE id=$1`, [due.id, due.interval_seconds]);
      const alert = (await client.query(`INSERT INTO safety_alerts(session_id,checkin_id,kind)
        VALUES($1,$2,'CHECKIN_MISSED') RETURNING id`, [due.id, due.checkin_id])).rows[0];
      await client.query(`INSERT INTO outbox_events(event_type,aggregate_id,payload)
        VALUES('safety.alert_created',$1,jsonb_build_object('alertId',$1::uuid))`, [alert.id]);
    } else {
      await client.query('UPDATE safety_checkins SET reminded_at=now() WHERE id=$1', [due.checkin_id]);
      await nurseEvent(client, due.id, due.user_id, 'safety.checkin_reminder');
    }
    await client.query('COMMIT');
    return true;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}
