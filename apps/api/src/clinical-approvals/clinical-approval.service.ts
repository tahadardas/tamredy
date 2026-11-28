import { Injectable } from '@nestjs/common';
import { DbService } from '../db/db.service.js';
import { DocStore } from '../admin/doc-store.js';
import { conflict, missing } from '../common/errors.js';
import { ClinicalApprovalRepository } from './clinical-approval.repository.js';
import type { ClinicalDecisionDto, ClinicalEvidenceDto } from './clinical-approval.dto.js';
import { transitionRequest } from '../requests/request-lifecycle.js';
import { buildNotificationPayload } from '../notifications/notification-routing.js';

@Injectable()
export class ClinicalApprovalService {
  constructor(
    private readonly db: DbService,
    private readonly repository: ClinicalApprovalRepository,
    private readonly documents: DocStore,
  ) {}

  async upload(patientUserId: string, requestId: string, dto: ClinicalEvidenceDto, file: {buffer:Buffer;originalname:string}) {
    const request = (await this.db.query(`SELECT id,clinical_approval_status,status FROM care_requests
      WHERE id=$1 AND requester_user_id=$2`, [requestId,patientUserId])).rows[0];
    if (!request) missing();
    if (!['PENDING', 'REJECTED'].includes(request.clinical_approval_status)) {
      conflict('CLINICAL_REVIEW_NOT_PENDING');
    }
    if (['COMPLETED', 'CANCELLED', 'EXPIRED'].includes(request.status)) {
      conflict('REQUEST_TERMINAL_STATE');
    }
    const saved = await this.documents.save(`clinical-${requestId}`,file,'OTHER');
    try {
      return await this.db.transaction(async client => {
        const evidence = (await client.query(`INSERT INTO request_clinical_evidence(
          request_id,uploaded_by,evidence_type,storage_key,original_filename,mime_type,file_size_bytes,sha256
        ) VALUES($1,$2,$3,$4,$5,$6,$7,$8) RETURNING id,request_id,evidence_type,original_filename,mime_type,file_size_bytes,created_at`,
        [requestId,patientUserId,dto.evidenceType,saved.storageKey,file.originalname,saved.mime,saved.size,saved.sha256])).rows[0];
        if (request.clinical_approval_status === 'REJECTED') {
          await client.query(
            `UPDATE request_clinical_reviews SET status='PENDING', version=version+1 WHERE request_id=$1`,
            [requestId],
          );
          await client.query(
            `UPDATE care_requests SET clinical_approval_status='PENDING', version=version+1, updated_at=statement_timestamp() WHERE id=$1`,
            [requestId],
          );
          await client.query(
            `INSERT INTO clinical_review_events(request_id,actor_user_id,previous_status,next_status,note)
             VALUES($1,$2,'REJECTED','PENDING','Patient resubmitted clinical evidence')`,
            [requestId, patientUserId],
          );
        }
        await client.query(`INSERT INTO clinical_access_audit(request_id,evidence_id,actor_user_id,action)
          VALUES($1,$2,$3,'UPLOAD_EVIDENCE')`, [requestId,evidence.id,patientUserId]);
        return evidence;
      });
    } catch (error) {
      await this.documents.remove(saved.storageKey);
      throw error;
    }
  }

  async listPending(actorUserId: string) {
    const result = await this.repository.pending();
    if (result.rows.length) await this.db.query(`INSERT INTO clinical_access_audit(request_id,actor_user_id,action)
      SELECT request_id,$1,'LIST_QUEUE' FROM unnest($2::uuid[]) AS listed(request_id)`,
    [actorUserId,result.rows.map(row=>row.request_id)]);
    return result.rows;
  }

  async readEvidence(actorUserId: string, evidenceId: string) {
    const row = (await this.repository.evidence(evidenceId)).rows[0];
    if (!row) missing();
    await this.db.query(`INSERT INTO clinical_access_audit(request_id,evidence_id,actor_user_id,action)
      VALUES($1,$2,$3,'VIEW_EVIDENCE')`, [row.request_id,evidenceId,actorUserId]);
    return { row, bytes: await this.documents.read(row.storage_key) };
  }

  async listEvidence(actorUserId: string, requestId: string) {
    const review = await this.db.query('SELECT 1 FROM request_clinical_reviews WHERE request_id=$1', [requestId]);
    if (!review.rowCount) missing();
    const evidence = await this.repository.evidenceForRequest(requestId);
    await this.db.query(`INSERT INTO clinical_access_audit(request_id,actor_user_id,action)
      VALUES($1,$2,'LIST_EVIDENCE')`, [requestId,actorUserId]);
    return evidence.rows;
  }

  async decide(actorUserId: string, requestId: string, dto: ClinicalDecisionDto) {
    return this.db.transaction(async client => {
      const review = (await this.repository.lock(client,requestId)).rows[0];
      if (!review) missing();
      if (review.status !== 'PENDING') conflict('CLINICAL_REVIEW_ALREADY_DECIDED');
      if (!['OFFERING','OPEN_FOR_PROPOSALS','SCHEDULED'].includes(review.request_status)) {
        conflict('REQUEST_NOT_OPEN_FOR_CLINICAL_REVIEW');
      }
      const evidence = await client.query(`SELECT evidence_type FROM request_clinical_evidence
        WHERE request_id=$1 AND deleted_at IS NULL`, [requestId]);
      if (dto.decision === 'APPROVE' && review.required_prescription
        && !evidence.rows.some(row => row.evidence_type === 'PRESCRIPTION')) {
        conflict('PRESCRIPTION_EVIDENCE_REQUIRED');
      }
      if (dto.decision === 'APPROVE' && !evidence.rowCount) conflict('CLINICAL_EVIDENCE_REQUIRED');
      const status = dto.decision === 'APPROVE' ? 'APPROVED' : 'REJECTED';
      await client.query(`UPDATE request_clinical_reviews SET status=$2,reviewed_by=$3,
        decision_note=$4,reviewed_at=statement_timestamp(),version=version+1 WHERE request_id=$1`,
      [requestId,status,actorUserId,dto.note.trim()]);
      await client.query(`UPDATE care_requests SET clinical_approval_status=$2,version=version+1,updated_at=statement_timestamp()
        WHERE id=$1`, [requestId,status]);
      await client.query(`INSERT INTO clinical_review_events(request_id,actor_user_id,previous_status,next_status,note)
        VALUES($1,$2,'PENDING',$3,$4)`, [requestId,actorUserId,status,dto.note.trim()]);
      await client.query(`INSERT INTO clinical_access_audit(request_id,actor_user_id,action)
        VALUES($1,$2,'DECIDE')`, [requestId,actorUserId]);

      if (status === 'APPROVED') {
        if (review.booking_mode === 'OPEN') {
          const policy = (await client.query("SELECT value FROM app_settings WHERE key='booking_policies'")).rows[0]?.value;
          // BUG-024: honor patient's chosen open_duration_minutes, only falling back to default policy
          const durationMinutes = Number(review.open_duration_minutes) || Number(policy?.openRequestDurationMinutes) || 120;
          if (review.original_latest_acceptable_arrival_at
            && new Date(review.original_latest_acceptable_arrival_at).getTime() <= Date.now()) {
            conflict('ARRIVAL_WINDOW_EXPIRED_REQUIRES_RESCHEDULING');
          }
          await client.query(`UPDATE care_requests SET published_at=statement_timestamp(),
            open_expires_at=least(statement_timestamp()+$2::integer*interval '1 minute',
              coalesce(original_latest_acceptable_arrival_at,'infinity'::timestamptz)),
            latest_acceptable_arrival_at=coalesce(original_latest_acceptable_arrival_at,
              statement_timestamp()+($2::integer+60)*interval '1 minute')
            WHERE id=$1`, [requestId,durationMinutes]);
          await client.query(`INSERT INTO outbox_events(event_type,aggregate_id,payload)
            VALUES('marketplace.request.published',$1,$2::jsonb)`,
          [
            requestId,
            JSON.stringify(buildNotificationPayload({
              eventType: 'marketplace.request.published',
              recipientUserId: review.requester_user_id,
              recipientRole: 'PATIENT',
              targetApp: 'PATIENT_APP',
              requestId,
              entityVersion: Number(review.request_version) + 1,
              skipPush: true,
            })),
          ]);
        } else if (review.request_status === 'SCHEDULED' && review.appointment_at && new Date(review.appointment_at).getTime() <= Date.now()) {
          // BUG-024: scheduled slot elapsed during clinical review -> require rescheduling instead of dispatching a passed slot
          await client.query(`DELETE FROM scheduled_visits WHERE request_id=$1`, [requestId]);
          await transitionRequest(client, {
            requestId,
            fromStatus: 'SCHEDULED',
            toStatus: 'UNFULFILLED',
            currentVersion: Number(review.request_version) + 1,
            actor: 'ADMIN',
            actorUserId,
            reason: 'SCHEDULED_TIME_PASSED_DURING_REVIEW',
          });
        } else if (review.request_status === 'OFFERING') {
          const dispatchPolicy = (await client.query("SELECT value FROM app_settings WHERE key='dispatch'")).rows[0]?.value;
          if (dispatchPolicy?.openEnabled === true && process.env.OPEN_DISPATCH_ENABLED === 'true') {
            await client.query(`UPDATE care_requests SET
              search_started_at=statement_timestamp(),
              search_expires_at=statement_timestamp()+$2::integer*interval '1 second'
              WHERE id=$1`, [requestId, dispatchPolicy?.offerDurationSeconds ?? 60]);
          }
          await client.query(`INSERT INTO dispatch_jobs(request_id) VALUES($1) ON CONFLICT(request_id) DO NOTHING`, [requestId]);
        }
      } else {
        // BUG-025: REJECTED clinical review must stop dispatch & open offers cleanly
        await client.query(`DELETE FROM dispatch_jobs WHERE request_id=$1`, [requestId]);
        await client.query(`UPDATE care_requests SET marketplace_status='INITIAL', open_expires_at=NULL WHERE id=$1`, [requestId]);
      }
      await client.query(`INSERT INTO outbox_events(event_type,aggregate_id,payload)
        VALUES('request.clinical_review_changed',$1,$2::jsonb)`,
      [
        requestId,
        JSON.stringify(buildNotificationPayload({
          eventType: 'request.clinical_review_changed',
          recipientUserId: review.requester_user_id,
          recipientRole: 'PATIENT',
          targetApp: 'PATIENT_APP',
          requestId,
          entityVersion: Number(review.request_version) + 1,
          extra: { decision: status, note: dto.note.trim() },
        })),
      ]);
      return {requestId,status};
    });
  }
}
