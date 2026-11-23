import { Injectable } from '@nestjs/common';
import type { PoolClient } from 'pg';
import { DbService } from '../db/db.service.js';
import { conflict, invalid, missing } from '../common/errors.js';
import type { AppealReviewStatus, ReviewAppealDto } from './appeals.dto.js';

const reviewTransitions: Readonly<Record<string, readonly AppealReviewStatus[]>> = {
  SUBMITTED: ['UNDER_REVIEW'],
  UNDER_REVIEW: ['NEEDS_INFORMATION', 'APPROVED', 'REJECTED'],
  NEEDS_INFORMATION: ['UNDER_REVIEW'],
  APPROVED: ['CLOSED'],
  REJECTED: ['CLOSED'],
  CLOSED: [],
};

@Injectable()
export class AppealsService {
  constructor(private readonly db: DbService) {}

  async submit(userId: string, role: 'PATIENT' | 'NURSE', cancellationId: string, description: string) {
    const detail = description.trim();
    if (!detail) invalid('APPEAL_DESCRIPTION_REQUIRED');
    return this.db.transaction(async client => {
      const result = await client.query(`
        SELECT c.id,c.classification,c.commitment_impact,c.cancelled_by_user_id,n.user_id AS nurse_user_id,
          c.cancelled_at+coalesce((SELECT (value->>'submissionWindowDays')::int FROM app_settings WHERE key='appeals'),14)
            *interval '1 day'>clock_timestamp() AS within_window
        FROM request_cancellations c
        LEFT JOIN request_assignments a ON a.id=c.assignment_id
        LEFT JOIN nurses n ON n.id=a.nurse_id
        WHERE c.id=$1 FOR UPDATE OF c
      `, [cancellationId]);
      const record = result.rows[0];
      if (!record || (role === 'PATIENT' ? record.cancelled_by_user_id : record.nurse_user_id) !== userId) missing();
      const eligible = role === 'PATIENT' ? record.commitment_impact : record.classification === 'NURSE_DELAY';
      if (!eligible || !record.within_window) conflict('APPEAL_NOT_AVAILABLE');
      const appeal = (await client.query(`
        INSERT INTO cancellation_appeals(cancellation_id,submitted_by_user_id,submitter_role,description)
        VALUES($1,$2,$3,$4) ON CONFLICT(cancellation_id,submitted_by_user_id) DO NOTHING
        RETURNING id,status,created_at
      `, [cancellationId,userId,role,detail])).rows[0];
      if (!appeal) conflict('APPEAL_ALREADY_SUBMITTED');
      await this.recordAudit(client,userId,'cancellation.appeal.submitted',appeal.id,appeal.status);
      await client.query(`
        INSERT INTO outbox_events(event_type,aggregate_id,payload)
        VALUES('cancellation.appeal.submitted',$1,jsonb_build_object('appealId',$1::uuid,'recipientUserId',$2::uuid))
      `,[appeal.id,userId]);
      return appeal;
    });
  }

  async own(userId: string) {
    const result = await this.db.query(`
      SELECT a.id,a.cancellation_id,a.status,a.created_at,a.updated_at,
        CASE WHEN a.submitter_role='PATIENT' THEN e.decision_note END AS decision_note
      FROM cancellation_appeals a LEFT JOIN LATERAL (
        SELECT decision_note FROM cancellation_appeal_events
        WHERE appeal_id=a.id AND next_status IN ('APPROVED','REJECTED') ORDER BY id DESC LIMIT 1
      ) e ON true
      WHERE a.submitted_by_user_id=$1 ORDER BY a.created_at DESC,a.id DESC LIMIT 50
    `, [userId]);
    return { items: result.rows };
  }

  async queue() {
    const result = await this.db.query(`
      SELECT id,cancellation_id,submitted_by_user_id,submitter_role,description,status,created_at,updated_at
      FROM cancellation_appeals WHERE status IN ('SUBMITTED','UNDER_REVIEW','NEEDS_INFORMATION')
      ORDER BY created_at,id LIMIT 100
    `);
    return { items: result.rows };
  }

  async review(actorId: string, id: string, dto: ReviewAppealDto) {
    const reason = dto.reason.trim();
    if (!reason) invalid('APPEAL_DECISION_REASON_REQUIRED');
    return this.db.transaction(async client => {
      const link = (await client.query('SELECT cancellation_id FROM cancellation_appeals WHERE id=$1',[id])).rows[0];
      if (!link) missing();
      const cancellation = (await client.query('SELECT id,classification,commitment_impact FROM request_cancellations WHERE id=$1 FOR UPDATE',
        [link.cancellation_id])).rows[0];
      const appeal = (await client.query('SELECT * FROM cancellation_appeals WHERE id=$1 FOR UPDATE',[id])).rows[0];
      if (!reviewTransitions[appeal.status]?.includes(dto.status)) conflict('APPEAL_TRANSITION_NOT_ALLOWED');
      if (dto.status === 'APPROVED' && appeal.submitter_role === 'PATIENT' && cancellation.commitment_impact) {
        await client.query(`UPDATE request_cancellations SET classification='EXCUSED',commitment_impact=false WHERE id=$1`,
          [cancellation.id]);
        await client.query(`
          INSERT INTO cancellation_classification_events(cancellation_id,actor_user_id,
            previous_classification,next_classification,previous_impact,next_impact,decision_note)
          VALUES($1,$2,$3,'EXCUSED',true,false,$4)
        `, [cancellation.id,actorId,cancellation.classification,reason]);
      }
      await client.query(`UPDATE cancellation_appeals SET status=$2,updated_at=statement_timestamp() WHERE id=$1`,[id,dto.status]);
      await client.query(`
        INSERT INTO cancellation_appeal_events(appeal_id,actor_user_id,previous_status,next_status,decision_note)
        VALUES($1,$2,$3,$4,$5)
      `, [id,actorId,appeal.status,dto.status,reason]);
      await this.recordAudit(client,actorId,'cancellation.appeal.reviewed',id,dto.status);
      if (dto.status === 'APPROVED' || dto.status === 'REJECTED') {
        await client.query(`
          INSERT INTO outbox_events(event_type,aggregate_id,payload)
          VALUES('cancellation.appeal.resolved',$1,jsonb_build_object('appealId',$1::uuid,'recipientUserId',$2::uuid,'status',$3::text))
        `,[id,appeal.submitted_by_user_id,dto.status]);
      }
      return { id, status: dto.status };
    });
  }

  private async recordAudit(client: PoolClient, actorId: string, action: string, id: string, status: string) {
    await client.query(`INSERT INTO audit_log(actor_user_id,action,target_type,target_id,detail)
      VALUES($1,$2,'cancellation_appeal',$3,jsonb_build_object('status',$4::text))`, [actorId,action,id,status]);
  }
}
