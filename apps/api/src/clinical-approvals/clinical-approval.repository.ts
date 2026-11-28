import { Injectable } from '@nestjs/common';
import type { PoolClient } from 'pg';
import { DbService } from '../db/db.service.js';

@Injectable()
export class ClinicalApprovalRepository {
  constructor(private readonly db: DbService) {}

  pending() {
    return this.db.query(`SELECT r.request_id,r.required_prescription,r.required_clinical_review,
      r.created_at,r.version,cr.beneficiary_id,
      count(DISTINCT e.id)::int AS evidence_count,
      array_agg(DISTINCT s.title_ar ORDER BY s.title_ar) AS services
      FROM request_clinical_reviews r JOIN care_requests cr ON cr.id=r.request_id
      JOIN care_request_items cri ON cri.request_id=cr.id JOIN services s ON s.id=cri.service_id
      LEFT JOIN request_clinical_evidence e ON e.request_id=cr.id AND e.deleted_at IS NULL
      WHERE r.status='PENDING' GROUP BY r.request_id,cr.beneficiary_id
      ORDER BY r.created_at,r.request_id LIMIT 100`);
  }

  lock(client: PoolClient, requestId: string) {
    return client.query(`SELECT r.*,cr.requester_user_id,cr.booking_mode,cr.status AS request_status,
      cr.version AS request_version,cr.open_duration_minutes,cr.original_latest_acceptable_arrival_at,sv.appointment_at
      FROM request_clinical_reviews r JOIN care_requests cr ON cr.id=r.request_id
      LEFT JOIN scheduled_visits sv ON sv.request_id=cr.id
      WHERE r.request_id=$1 FOR UPDATE OF r,cr`, [requestId]);
  }

  evidence(evidenceId: string) {
    return this.db.query(`SELECT e.*,cr.requester_user_id FROM request_clinical_evidence e
      JOIN care_requests cr ON cr.id=e.request_id WHERE e.id=$1 AND e.deleted_at IS NULL`, [evidenceId]);
  }


  evidenceForRequest(requestId: string) {
    return this.db.query(`SELECT id,evidence_type,original_filename,mime_type,file_size_bytes,created_at
      FROM request_clinical_evidence WHERE request_id=$1 AND deleted_at IS NULL
      ORDER BY created_at,id`, [requestId]);
  }
}
