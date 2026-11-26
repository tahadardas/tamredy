import { Injectable } from '@nestjs/common';
import type { PoolClient } from 'pg';
import { DbService } from '../db/db.service.js';
import { FinancialReservationsService } from '../wallet/financial-reservations.service.js';

@Injectable()
export class SafeAbortRepository {
  constructor(
    private readonly db: DbService,
    private readonly reservations: FinancialReservationsService = new FinancialReservationsService(),
  ) {}

  transaction<T>(work: (client: PoolClient) => Promise<T>) {
    return this.db.transaction(work);
  }

  async lockAssignment(client: PoolClient, assignment: string, owner: string) {
    const target = (await client.query(`SELECT a.request_id,a.nurse_id FROM request_assignments a
      JOIN nurses n ON n.id=a.nurse_id
      WHERE a.id=$1 AND n.user_id=$2`, [assignment, owner])).rows[0];
    if (!target) return null;
    const request = (await client.query(`SELECT id,status,requester_user_id
      FROM care_requests WHERE id=$1 FOR UPDATE`, [target.request_id])).rows[0];
    await client.query('SELECT id FROM nurses WHERE id=$1 FOR UPDATE', [target.nurse_id]);
    const locked = (await client.query('SELECT status FROM request_assignments WHERE id=$1 FOR UPDATE', [assignment])).rows[0];
    return { request, nurseId: target.nurse_id as string, assignmentStatus: locked.status as string };
  }

  async existing(client: PoolClient, assignment: string) {
    return (await client.query('SELECT emergency_event_id FROM safety_aborts WHERE assignment_id=$1', [assignment])).rows[0];
  }

  async safetySession(client: PoolClient, assignment: string) {
    return (await client.query('SELECT id FROM safety_sessions WHERE assignment_id=$1 FOR UPDATE', [assignment])).rows[0]?.id as string | undefined;
  }

  async openEvent(client: PoolClient, session: string) {
    return (await client.query(`SELECT id FROM emergency_events WHERE session_id=$1
      AND state NOT IN ('RESOLVED','FALSE_ALARM','CLOSED') ORDER BY received_at DESC,id LIMIT 1`, [session])).rows[0]?.id as string | undefined;
  }

  async finish(client: PoolClient, info: {
    assignment: string; requestId: string; requester: string; nurse: string;
    actor: string; eventId: string; reason?: string;
  }) {
    const {assignment,requestId,requester,nurse,actor,eventId,reason} = info;
    const incident = (await client.query(`INSERT INTO incidents(request_id,reported_by,severity,description)
      VALUES($1,$2,'HIGH','Safety abort') RETURNING id`, [requestId, actor])).rows[0].id;
    await client.query(`INSERT INTO safety_aborts(assignment_id,incident_id,emergency_event_id,actor_user_id,reason)
      VALUES($1,$2,$3,$4,$5)`, [assignment,incident,eventId,actor,reason ?? null]);
    await client.query(`UPDATE visits SET completed_at=now(),outcome='ESCALATED'
      WHERE assignment_id=$1 AND completed_at IS NULL`, [assignment]);
    await client.query(`UPDATE request_assignments SET status='RELEASED',released_at=now(),reason='SAFETY_ABORT'
      WHERE id=$1`, [assignment]);
    await client.query(`UPDATE care_requests SET status='ESCALATED',version=version+1,updated_at=now()
      WHERE id=$1`, [requestId]);
    await this.reservations.releaseForRequest(client, requestId, 'SAFE_ABORT', actor);
    await client.query(`UPDATE nurses SET work_status='PAUSED',availability_intent='PAUSED',updated_at=now() WHERE id=$1`, [nurse]);
    await client.query(`INSERT INTO request_events(request_id,actor_user_id,event_type)
      VALUES($1,$2,'visit.interrupted')`, [requestId,actor]);
    await client.query(`INSERT INTO audit_log(actor_user_id,action,target_type,target_id)
      VALUES($1,'safety.visit_aborted','incident',$2)`, [actor,incident]);
    await client.query(`INSERT INTO outbox_events(event_type,aggregate_id,payload)
      VALUES('visit.interrupted',$1,jsonb_build_object(
        'eventType','visit.interrupted',
        'requestId',$1::uuid,
        'assignmentId',$3::uuid,
        'recipientUserId',$2::uuid,
        'recipientRole','PATIENT',
        'targetApp','PATIENT_APP',
        'priority','HIGH',
        'createdAt',statement_timestamp()
      ))`,
    [requestId,requester,assignment]);
  }
}
