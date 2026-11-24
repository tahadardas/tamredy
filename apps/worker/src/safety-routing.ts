import type pg from 'pg';

type Stage = 'PRIMARY' | 'BACKUP' | 'SUPERVISOR';
type Route = { user_id: string; shift_id: string; slot: Stage };
const nextStages: Record<string, Stage[]> = {
  QUEUED: ['PRIMARY','BACKUP','SUPERVISOR'],
  PRIMARY: ['BACKUP','SUPERVISOR'],
  BACKUP: ['SUPERVISOR'],
  SUPERVISOR: ['SUPERVISOR'],
  UNCOVERED: ['PRIMARY','BACKUP','SUPERVISOR'],
};

function acknowledgementSeconds() {
  const value = Number(process.env.GUARDIAN_ACK_SECONDS ?? 30);
  return Number.isInteger(value) && value >= 15 && value <= 300 ? value : 30;
}

async function candidates(client: pg.PoolClient, caseId: string, progression: Stage[], previous: string | null) {
  return (await client.query<Route>(`
    WITH region AS (
      SELECT n.governorate_id FROM safety_cases c
      LEFT JOIN emergency_events e ON e.id=c.emergency_event_id
      LEFT JOIN safety_aborts ab ON ab.emergency_event_id=e.id
      LEFT JOIN safety_alerts al ON al.id=c.alert_id
      LEFT JOIN safety_sessions s ON s.id=coalesce(e.session_id,al.session_id)
      LEFT JOIN request_assignments a ON a.id=coalesce(s.assignment_id,ab.assignment_id)
      LEFT JOIN nurses n ON n.id=a.nurse_id OR (a.id IS NULL AND n.user_id=e.reporter_user_id)
      WHERE c.id=$1
    ), available AS (
      SELECT s.id AS shift_id,sp.user_id,g.permission,
        CASE WHEN s.primary_user_id=sp.user_id THEN 'PRIMARY' ELSE 'BACKUP' END AS slot,
        s.governorate_id
      FROM safety_staff_shifts s JOIN safety_staff_shift_presence sp ON sp.shift_id=s.id
      JOIN safety_staff_grants g ON g.user_id=sp.user_id
      JOIN users u ON u.id=sp.user_id CROSS JOIN region r
      WHERE s.starts_at<=clock_timestamp() AND s.ends_at>clock_timestamp() AND s.cancelled_at IS NULL
        AND sp.user_id IN (s.primary_user_id,s.backup_user_id) AND sp.checked_out_at IS NULL
        AND sp.heartbeat_at>clock_timestamp()-interval '90 seconds'
        AND g.revoked_at IS NULL AND u.status='ACTIVE' AND u.role IN ('ADMIN','CLINICAL_REVIEWER')
        AND (s.governorate_id IS NULL OR s.governorate_id=r.governorate_id)
        AND sp.user_id IS DISTINCT FROM $3::uuid
    ), slots AS (
      SELECT user_id,shift_id,slot,governorate_id FROM available
      UNION ALL SELECT user_id,shift_id,'SUPERVISOR',governorate_id FROM available
        WHERE permission='SAFETY_SUPERVISOR'
    )
    SELECT user_id,shift_id,slot FROM slots WHERE slot=ANY($2::text[])
    ORDER BY array_position($2::text[],slot),governorate_id NULLS LAST,shift_id,user_id LIMIT 1`,
  [caseId,progression,previous])).rows[0];
}

export async function routeSafetyCase(pool: pg.Pool): Promise<boolean> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const due = (await client.query(`SELECT id,assigned_user_id,routing_stage FROM safety_cases
      WHERE state='RECEIVED' AND next_route_at<=clock_timestamp()
      ORDER BY next_route_at,id LIMIT 1 FOR UPDATE SKIP LOCKED`)).rows[0];
    if (!due) {
      await client.query('COMMIT');
      return false;
    }
    const next = await candidates(client,due.id,nextStages[due.routing_stage] ?? nextStages.QUEUED!,due.assigned_user_id);
    const stage = next?.slot ?? 'UNCOVERED';
    const changed = due.routing_stage !== stage || due.assigned_user_id !== (next?.user_id ?? null);
    const result = (await client.query(`UPDATE safety_cases SET assigned_user_id=$2,assigned_shift_id=$3,
      routing_stage=$4,next_route_at=clock_timestamp()+$5::integer*interval '1 second',
      version=version+CASE WHEN $6 THEN 1 ELSE 0 END,
      updated_at=CASE WHEN $6 THEN clock_timestamp() ELSE updated_at END
      WHERE id=$1 RETURNING next_route_at`,
    [due.id,next?.user_id ?? null,next?.shift_id ?? null,stage,acknowledgementSeconds(),changed])).rows[0];
    if (changed) {
      await client.query(`INSERT INTO safety_case_routes(case_id,from_user_id,to_user_id,shift_id,route_stage,acknowledge_by)
        VALUES($1,$2,$3,$4,$5,$6)`,
      [due.id,due.assigned_user_id,next?.user_id ?? null,next?.shift_id ?? null,stage,result.next_route_at]);
      if (next) {
        await client.query(`INSERT INTO outbox_events(event_type,aggregate_id,payload)
          VALUES('safety.case_routed',$1,jsonb_build_object('caseId',$1::uuid,'recipientUserId',$2::uuid))`, [due.id,next.user_id]);
      }
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
