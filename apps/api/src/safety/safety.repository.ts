import { Injectable } from '@nestjs/common';
import type { PoolClient } from 'pg';
import { DbService } from '../db/db.service.js';
import type { ReportSosDto } from './safety.dto.js';

export type SafetyPointRecord = {
  sequence: number;
  latitude: number;
  longitude: number;
  accuracy: number;
  captured_at: string;
  hash: string;
};

@Injectable()
export class SafetyRepository {
  constructor(private readonly db: DbService) {}

  transaction<T>(run: (client: PoolClient) => Promise<T>) {
    return this.db.transaction(run);
  }

  async assignment(client: PoolClient, owner: string, id: string) {
    return (await client.query(`SELECT a.id,a.status,r.status AS request_status
      FROM request_assignments a JOIN nurses n ON n.id=a.nurse_id
      JOIN care_requests r ON r.id=a.request_id WHERE a.id=$1 AND n.user_id=$2
      FOR UPDATE OF a`, [id, owner])).rows[0];
  }

  async start(client: PoolClient, id: string) {
    const inserted = await client.query(`INSERT INTO safety_sessions(assignment_id,policy_version_id,next_checkin_at)
      SELECT $1,v.id,now()+v.interval_seconds*interval '1 second'
      FROM safety_policy_versions v JOIN safety_policies p ON p.id=v.policy_id
      WHERE p.code='STANDARD' AND v.effective_at<=now()
      ORDER BY v.effective_at DESC LIMIT 1 ON CONFLICT(assignment_id) DO NOTHING RETURNING *`, [id]);
    return inserted.rows[0] ? { ...inserted.rows[0], next_sequence: 0 } :
      (await client.query(`SELECT s.*,coalesce((SELECT max(p.sequence_no)::bigint+1
        FROM safety_location_points p WHERE p.session_id=s.id),0)::text AS next_sequence
        FROM safety_sessions s WHERE s.assignment_id=$1`, [id])).rows[0];
  }

  async session(client: PoolClient, owner: string, id: string) {
    return (await client.query(`SELECT s.* FROM safety_sessions s
      JOIN request_assignments a ON a.id=s.assignment_id JOIN nurses n ON n.id=a.nurse_id
      WHERE s.id=$1 AND n.user_id=$2 FOR UPDATE OF s`, [id, owner])).rows[0];
  }

  async insertPoints(client: PoolClient, id: string, points: SafetyPointRecord[]) {
    await client.query(`INSERT INTO safety_location_points
      (session_id,sequence_no,location,accuracy_m,captured_at,payload_hash)
      SELECT $1,p.sequence,ST_SetSRID(ST_MakePoint(p.longitude,p.latitude),4326)::geography,
        p.accuracy,p.captured_at,p.hash FROM jsonb_to_recordset($2::jsonb)
      AS p(sequence integer,latitude float8,longitude float8,accuracy float8,captured_at timestamptz,hash text)
      ON CONFLICT(session_id,sequence_no) DO NOTHING`, [id, JSON.stringify(points)]);
  }

  async storedHashes(client: PoolClient, id: string, sequences: number[]) {
    return (await client.query<{sequence_no: number; payload_hash: string}>(`SELECT sequence_no,payload_hash
      FROM safety_location_points WHERE session_id=$1 AND sequence_no=ANY($2::integer[])`, [id, sequences])).rows;
  }

  async checkout(client: PoolClient, id: string) {
    await client.query(`UPDATE safety_checkins SET state='CANCELLED' WHERE session_id=$1 AND state='PENDING'`, [id]);
    return (await client.query(`UPDATE safety_sessions SET checked_out_at=coalesce(checked_out_at,now()),next_checkin_at=NULL
      WHERE id=$1 RETURNING *`, [id])).rows[0];
  }

  async eventByKey(client: PoolClient, owner: string, key: string) {
    return (await client.query(`SELECT id,session_id,silent,state,received_at,triggered_at FROM emergency_events
      WHERE reporter_user_id=$1 AND client_event_id=$2`, [owner, key])).rows[0];
  }

  async report(client: PoolClient, owner: string, dto: ReportSosDto) {
    return (await client.query(`INSERT INTO emergency_events
      (reporter_user_id,client_event_id,session_id,silent,location_sequence_no,triggered_at)
      VALUES($1,$2,$3,$4,(SELECT sequence_no FROM safety_location_points
        WHERE session_id=$3 ORDER BY captured_at DESC,sequence_no DESC LIMIT 1),$5)
      ON CONFLICT(reporter_user_id,client_event_id) DO NOTHING
      RETURNING id,session_id,silent,state,received_at,triggered_at`,
    [owner, dto.clientEventId, dto.sessionId ?? null, dto.silent, dto.triggeredAt ?? null])).rows[0];
  }

  async recordReceived(client: PoolClient, eventId: string, owner: string) {
    await client.query(`INSERT INTO emergency_event_actions(event_id,actor_user_id,action)
      VALUES($1,$2,'RECEIVED')`, [eventId, owner]);
    await client.query(`INSERT INTO outbox_events(event_type,aggregate_id,payload)
      VALUES('safety.sos_received',$1,jsonb_build_object(
        'eventId',$1::uuid,
        'recipientUserIds',coalesce((SELECT jsonb_agg(DISTINCT g.user_id)
          FROM safety_staff_grants g JOIN users u ON u.id=g.user_id
          WHERE g.revoked_at IS NULL AND u.status='ACTIVE'),'[]'::jsonb)
      ))`, [eventId]);
  }

  async event(owner: string, id: string) {
    return (await this.db.query(`SELECT id,session_id,silent,state,received_at,triggered_at FROM emergency_events
      WHERE id=$1 AND reporter_user_id=$2`, [id, owner])).rows[0];
  }

  async status(owner: string) {
    const active = await this.db.query(`SELECT s.id,s.assignment_id,s.started_at,
      coalesce((SELECT max(p.sequence_no)::bigint+1 FROM safety_location_points p
        WHERE p.session_id=s.id),0)::text AS next_sequence FROM safety_sessions s
      JOIN request_assignments a ON a.id=s.assignment_id JOIN nurses n ON n.id=a.nurse_id
      WHERE n.user_id=$1 AND s.checked_out_at IS NULL ORDER BY s.started_at DESC LIMIT 1`, [owner]);
    return active.rows[0] ?? null;
  }
}
