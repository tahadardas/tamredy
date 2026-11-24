import type pg from 'pg';

export async function runSafetyRetention(pool: pg.Pool): Promise<boolean> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SELECT pg_advisory_xact_lock(hashtext('guardian.evidence.retention'))");
    const policy = (await client.query(
      'SELECT id,point_days,export_days FROM safety_retention_policies ORDER BY created_at DESC,id DESC LIMIT 1')).rows[0];
    if (!policy) {
      await client.query('COMMIT');
      return false;
    }
    const sessions = (await client.query(`SELECT s.id FROM safety_sessions s
      WHERE (s.checked_out_at IS NOT NULL OR s.started_at<now()-interval '12 hours')
      AND EXISTS (SELECT 1 FROM safety_location_points p WHERE p.session_id=s.id
        AND p.received_at<now()-$1::integer*interval '1 day')
      AND NOT EXISTS (
        SELECT 1 FROM safety_cases c LEFT JOIN emergency_events e ON e.id=c.emergency_event_id
        LEFT JOIN safety_alerts a ON a.id=c.alert_id
        WHERE coalesce(e.session_id,a.session_id)=s.id AND (
          c.state<>'RESOLVED' OR EXISTS (
            SELECT 1 FROM safety_legal_holds h WHERE h.case_id=c.id AND h.released_at IS NULL
          )
        )
      )
      ORDER BY s.id LIMIT 100 FOR UPDATE OF s SKIP LOCKED`,[policy.point_days])).rows;
    // Re-read protection after locking the sessions, which serializes SOS and check-in writers.
    const points = (await client.query(`SELECT p.session_id,p.sequence_no FROM safety_location_points p
      WHERE p.session_id=ANY($2::uuid[]) AND p.received_at<now()-$1::integer*interval '1 day'
        AND NOT EXISTS (
          SELECT 1 FROM safety_cases c LEFT JOIN emergency_events e ON e.id=c.emergency_event_id
          LEFT JOIN safety_alerts a ON a.id=c.alert_id
          WHERE coalesce(e.session_id,a.session_id)=p.session_id AND (
            c.state<>'RESOLVED' OR EXISTS (
              SELECT 1 FROM safety_legal_holds h WHERE h.case_id=c.id AND h.released_at IS NULL
            )
          )
        )
      ORDER BY p.received_at,p.session_id,p.sequence_no LIMIT 2000`,
    [policy.point_days,sessions.map(row => row.id)])).rows;
    if (points.length) {
      const keys = JSON.stringify(points);
      const selected = 'jsonb_to_recordset($1::jsonb) AS k(session_id uuid,sequence_no int)';
      await client.query(`UPDATE emergency_events e SET location_sequence_no=NULL FROM ${selected}
        WHERE e.session_id=k.session_id AND e.location_sequence_no=k.sequence_no`,[keys]);
      await client.query(`DELETE FROM safety_location_points p USING ${selected}
        WHERE p.session_id=k.session_id AND p.sequence_no=k.sequence_no`,[keys]);
    }
    const bundles = await client.query(`WITH due AS (
      SELECT e.id FROM safety_evidence_exports e
      JOIN safety_evidence_approvals a ON a.id=e.approval_id JOIN safety_cases c ON c.id=a.case_id
      WHERE e.purged_at IS NULL AND e.created_at<now()-$1::integer*interval '1 day'
        AND a.expires_at<=now() AND c.state='RESOLVED'
        AND NOT EXISTS (SELECT 1 FROM safety_legal_holds h WHERE h.case_id=c.id AND h.released_at IS NULL)
      ORDER BY e.created_at,e.id LIMIT 100 FOR UPDATE OF e SKIP LOCKED
    ) UPDATE safety_evidence_exports e SET sealed_bundle=NULL,purged_at=now()
      FROM due WHERE e.id=due.id`,[policy.export_days]);
    if (points.length || bundles.rowCount) {
      await client.query('INSERT INTO safety_retention_runs(policy_id,point_count,export_count) VALUES($1,$2,$3)',
        [policy.id,points.length,bundles.rowCount ?? 0]);
    }
    await client.query('COMMIT');
    return Boolean(points.length || bundles.rowCount);
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}
