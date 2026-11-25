import { Injectable } from '@nestjs/common';
import { DbService } from '../db/db.service.js';

export interface TrackingRecipient {
  requestId: string;
  assignmentId: string;
  patientUserId: string;
}

@Injectable()
export class TrackingAuthorizationService {
  constructor(private readonly db: DbService) {}

  async recipient(nurseId: string, assignmentId?: string): Promise<TrackingRecipient | null> {
    const result = await this.db.query(
      `SELECT r.id AS request_id,a.id AS assignment_id,r.requester_user_id AS patient_user_id
       FROM request_assignments a
       JOIN care_requests r ON r.id=a.request_id
       WHERE a.nurse_id=$1 AND a.status='ACTIVE' AND r.status='EN_ROUTE'
         AND ($2::uuid IS NULL OR a.id=$2)
       ORDER BY a.accepted_at DESC LIMIT 1`,
      [nurseId, assignmentId ?? null],
    );
    if (!result.rowCount) return null;
    return {
      requestId: result.rows[0].request_id,
      assignmentId: result.rows[0].assignment_id,
      patientUserId: result.rows[0].patient_user_id,
    };
  }
}

