import { Injectable } from '@nestjs/common';
import type { PoolClient } from 'pg';
import { DbService } from '../db/db.service.js';
import type { EvidencePoint } from './evidence-bundle.js';

@Injectable()
export class EvidenceRepository {
  constructor(private readonly db: DbService) {}

  transaction<T>(work: (client: PoolClient) => Promise<T>) { return this.db.transaction(work); }

  async exporter(client: PoolClient, actor: string) {
    const direct = Boolean((await client.query(`SELECT g.user_id FROM safety_evidence_export_grants g JOIN users u ON u.id=g.user_id
      WHERE g.user_id=$1 AND g.revoked_at IS NULL AND u.status='ACTIVE' AND u.role IN ('ADMIN','CLINICAL_REVIEWER')
      FOR SHARE OF g`, [actor])).rowCount);
    if (direct) return true;
    const user = (await client.query(`SELECT role FROM users WHERE id=$1 AND status='ACTIVE'`, [actor])).rows[0];
    return user?.role === 'ADMIN';
  }

  async approve(client: PoolClient, caseId: string, actor: string, dto: {
    exporterId: string; purpose: string; recipient: string; caseReference?: string;
  }) {
    return (await client.query(`INSERT INTO safety_evidence_approvals
      (case_id,approved_by,exporter_id,purpose,recipient,case_reference)
      VALUES($1,$2,$3,$4,$5,$6) RETURNING id,case_id,expires_at`,
    [caseId,actor,dto.exporterId,dto.purpose,dto.recipient,dto.caseReference ?? null])).rows[0];
  }

  async lockApproval(client: PoolClient, id: string, actor: string, caseId: string) {
    return (await client.query(`SELECT *,expires_at>clock_timestamp() AS current FROM safety_evidence_approvals
      WHERE id=$1 AND exporter_id=$2 AND case_id=$3 FOR UPDATE`, [id,actor,caseId])).rows[0];
  }

  async existing(client: PoolClient, approval: string) {
    return (await client.query('SELECT id,manifest,sha256,created_at FROM safety_evidence_exports WHERE approval_id=$1', [approval])).rows[0];
  }

  async collect(client: PoolClient, caseId: string) {
    const context = (await client.query(`SELECT c.id,c.state,c.opened_at,c.updated_at,
      e.silent,e.state AS emergency_state,e.triggered_at,e.received_at,
      al.kind AS alert_kind,s.id AS session_id,s.started_at,s.checked_out_at,
      a.id AS assignment_id,a.accepted_at,a.departed_at,a.released_at,
      r.id AS request_id,ST_X(r.location::geometry) AS visit_longitude,ST_Y(r.location::geometry) AS visit_latitude,
      v.arrived_at,v.started_at AS visit_started_at,v.completed_at,
      r.created_at AS request_created_at,r.address_text AS confirmed_visit_address,
      r.location_source,r.currency_code,r.payment_status,
      (SELECT sum(cc.amount) FROM cash_collections cc WHERE cc.visit_id=v.id) AS collected_amount,
      CASE WHEN v.completed_at>=v.arrived_at THEN floor(extract(epoch FROM(v.completed_at-v.arrived_at)))::int END AS visit_seconds
      FROM safety_cases c LEFT JOIN emergency_events e ON e.id=c.emergency_event_id
      LEFT JOIN safety_alerts al ON al.id=c.alert_id LEFT JOIN safety_aborts ab ON ab.emergency_event_id=e.id
      LEFT JOIN safety_sessions s ON s.id=coalesce(e.session_id,al.session_id)
      LEFT JOIN request_assignments a ON a.id=coalesce(s.assignment_id,ab.assignment_id)
      LEFT JOIN care_requests r ON r.id=a.request_id LEFT JOIN visits v ON v.assignment_id=a.id
      WHERE c.id=$1`,[caseId])).rows[0];
    if (context.session_id) {
      await client.query('SELECT id FROM safety_sessions WHERE id=$1 FOR SHARE',[context.session_id]);
    }
    const actions = (await client.query(`SELECT actor_user_id,action,note,created_at
      FROM safety_case_actions WHERE case_id=$1 ORDER BY resulting_version`,[caseId])).rows;
    const routes = (await client.query(`SELECT from_user_id,to_user_id,route_stage,routed_at,acknowledge_by
      FROM safety_case_routes WHERE case_id=$1 ORDER BY id`,[caseId])).rows;
    const handovers = (await client.query(`SELECT requested_by,from_user_id,to_user_id,state,created_at,accepted_at
      FROM safety_shift_handovers WHERE case_id=$1 ORDER BY created_at,id`,[caseId])).rows;
    const custody = (await client.query(`SELECT actor_user_id,action,occurred_at FROM audit_log
      WHERE target_type='safety_case' AND target_id=$1 ORDER BY id LIMIT 10001`, [caseId])).rows;
    const checkins = (await client.query(`SELECT c.id,c.created_at,c.deadline_at,c.state,r.response,r.responded_at
      FROM safety_checkins c LEFT JOIN safety_checkin_responses r ON r.checkin_id=c.id
      WHERE c.session_id=$1 ORDER BY c.created_at,r.responded_at`,[context.session_id])).rows;
    const points = (await client.query<EvidencePoint>(`SELECT sequence_no,ST_X(location::geometry) AS longitude,
      ST_Y(location::geometry) AS latitude,accuracy_m,captured_at,received_at
      FROM safety_location_points WHERE session_id=$1 ORDER BY sequence_no LIMIT 20001`,[context.session_id])).rows;
    return { context,actions,routes,handovers,custody,checkins,points };
  }

  async store(client: PoolClient, approval: string, actor: string, manifest: object, data: Buffer, hash: string) {
    return (await client.query(`INSERT INTO safety_evidence_exports(approval_id,exported_by,manifest,sealed_bundle,sha256)
      VALUES($1,$2,$3::jsonb,$4,$5) RETURNING id,manifest,sha256,created_at`,
    [approval,actor,JSON.stringify(manifest),data,hash])).rows[0];
  }

  async download(client: PoolClient, actor: string, id: string) {
    return (await client.query(`SELECT e.approval_id,e.sealed_bundle,e.sha256,a.case_id
      FROM safety_evidence_exports e JOIN safety_evidence_approvals a ON a.id=e.approval_id
      WHERE e.id=$1 AND e.exported_by=$2 AND a.expires_at>clock_timestamp() AND e.purged_at IS NULL`,
    [id,actor])).rows[0];
  }
}
