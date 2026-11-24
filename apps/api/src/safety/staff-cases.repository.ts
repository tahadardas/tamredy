import { Injectable } from '@nestjs/common';
import type { PoolClient } from 'pg';
import { DbService } from '../db/db.service.js';
import type { SafetyCaseActionDto } from './staff-cases.dto.js';

@Injectable()
export class StaffCasesRepository {
  constructor(private readonly db: DbService) {}

  transaction<T>(work: (client: PoolClient) => Promise<T>) {
    return this.db.transaction(work);
  }

  async grant(client: PoolClient, actor: string) {
    const direct = (await client.query(`SELECT permission FROM safety_staff_grants
      WHERE user_id=$1 AND revoked_at IS NULL FOR SHARE`, [actor])).rows[0]?.permission;
    if (direct) return direct;
    const user = (await client.query(`SELECT role FROM users WHERE id=$1 AND status='ACTIVE'`, [actor])).rows[0];
    if (user?.role === 'ADMIN') return 'SAFETY_SUPERVISOR';
    return undefined;
  }

  async dashboard(client: PoolClient, actor: string, supervisor: boolean) {
    return (await client.query(`SELECT count(*) FILTER (WHERE c.state='RECEIVED')::int AS received,
      count(*) FILTER (WHERE c.state='ACKNOWLEDGED')::int AS acknowledged,
      count(*) FILTER (WHERE c.state='ESCALATED')::int AS escalated,
      count(*) FILTER (WHERE c.state<>'RESOLVED' AND c.emergency_event_id IS NOT NULL)::int AS open_sos,
      count(*) FILTER (WHERE c.state<>'RESOLVED' AND a.kind='CHECKIN_MISSED')::int AS missed_checkins,
      max(c.updated_at) AS last_update FROM safety_cases c LEFT JOIN safety_alerts a ON a.id=c.alert_id
      WHERE $2 OR c.assigned_user_id=$1 OR (c.state='RECEIVED' AND c.assigned_user_id IS NULL)`, [actor,supervisor])).rows[0];
  }

  async list(client: PoolClient, actor: string, supervisor: boolean) {
    return (await client.query(`SELECT c.id,c.state,c.version,c.opened_at,c.updated_at,c.routing_stage,c.next_route_at,
      coalesce(a.kind,'SOS') AS kind,
      CASE WHEN $2 OR c.assigned_user_id=$1 THEN c.assigned_user_id END AS assigned_user_id
      FROM safety_cases c LEFT JOIN safety_alerts a ON a.id=c.alert_id
      WHERE $2 OR c.assigned_user_id=$1 OR (c.state='RECEIVED' AND c.assigned_user_id IS NULL)
      ORDER BY CASE c.state WHEN 'ESCALATED' THEN 0 WHEN 'RECEIVED' THEN 1
        WHEN 'ACKNOWLEDGED' THEN 2 ELSE 3 END,c.opened_at,c.id LIMIT 100`, [actor, supervisor])).rows;
  }

  async find(client: PoolClient, id: string) {
    return (await client.query('SELECT * FROM safety_cases WHERE id=$1 FOR UPDATE', [id])).rows[0];
  }

  async detail(client: PoolClient, id: string) {
    const information = (await client.query(`SELECT coalesce(a.kind,'SOS') AS kind,e.silent,e.triggered_at,e.received_at,
      u.display_name AS reporter_name,coalesce(s.assignment_id,ab.assignment_id) AS assignment_id
      FROM safety_cases c
      LEFT JOIN safety_alerts a ON a.id=c.alert_id
      LEFT JOIN emergency_events e ON e.id=c.emergency_event_id
      LEFT JOIN safety_aborts ab ON ab.emergency_event_id=e.id
      LEFT JOIN safety_sessions s ON s.id=coalesce(a.session_id,e.session_id)
      LEFT JOIN request_assignments r ON r.id=s.assignment_id
      LEFT JOIN nurses n ON n.id=r.nurse_id
      LEFT JOIN users u ON u.id=coalesce(e.reporter_user_id,n.user_id)
      WHERE c.id=$1`, [id])).rows[0];
    const actions = (await client.query(`SELECT actor_user_id,action,note,resulting_version,created_at
      FROM safety_case_actions WHERE case_id=$1 ORDER BY resulting_version`, [id])).rows;
    const routes = (await client.query(`SELECT route_stage,routed_at,acknowledge_by
      FROM safety_case_routes WHERE case_id=$1 ORDER BY id`, [id])).rows;
    return { ...information, actions, routes };
  }

  async replay(client: PoolClient, id: string, actor: string, key: string) {
    return (await client.query(`SELECT action,note,resulting_version FROM safety_case_actions
      WHERE case_id=$1 AND actor_user_id=$2 AND client_action_id=$3`, [id, actor, key])).rows[0];
  }

  async update(client: PoolClient, id: string, actor: string, action: string, dto: SafetyCaseActionDto) {
    const changed = (await client.query(`UPDATE safety_cases SET state=$2,version=version+1,updated_at=now(),
      assigned_shift_id=CASE WHEN $2='ACKNOWLEDGED' AND assigned_user_id IS DISTINCT FROM $3 THEN NULL ELSE assigned_shift_id END,
      assigned_user_id=CASE WHEN $2='ACKNOWLEDGED' THEN $3 ELSE assigned_user_id END WHERE id=$1 RETURNING *`, [id, action, actor])).rows[0];
    await client.query(`INSERT INTO safety_case_actions(case_id,actor_user_id,client_action_id,action,note,resulting_version)
      VALUES($1,$2,$3,$4,$5,$6)`, [id, actor, dto.clientActionId, action, dto.note || null, changed.version]);
    if (changed.emergency_event_id) {
      await client.query('UPDATE emergency_events SET state=$2 WHERE id=$1', [changed.emergency_event_id, action]);
      await client.query('INSERT INTO emergency_event_actions(event_id,actor_user_id,action) VALUES($1,$2,$3)',
        [changed.emergency_event_id, actor, action]);
      await client.query(`INSERT INTO outbox_events(event_type,aggregate_id,payload)
        SELECT 'safety.event_changed',id,jsonb_build_object('eventId',id,'recipientUserId',reporter_user_id)
        FROM emergency_events WHERE id=$1`, [changed.emergency_event_id]);
    }
    return { id, state: changed.state, version: changed.version };
  }

  async audit(client: PoolClient, actor: string, action: string, target: string) {
    await client.query(`INSERT INTO audit_log(actor_user_id,action,target_type,target_id)
      VALUES($1,$2,'safety_case',$3)`, [actor, action, target]);
  }
}
