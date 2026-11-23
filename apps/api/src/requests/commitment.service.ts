import { Injectable } from '@nestjs/common';
import { DbService } from '../db/db.service.js';
import { missing } from '../common/errors.js';

const openAppeal = "('SUBMITTED','UNDER_REVIEW','NEEDS_INFORMATION')";

@Injectable()
export class CommitmentService {
  constructor(private readonly db: DbService) {}

  private async summary(userId: string, offerId?: string) {
    // Evaluate the scope and aggregate in the same database snapshot.
    const subject = offerId === undefined
      ? 'SELECT $1::uuid AS patient_id'
      : `SELECT r.requester_user_id AS patient_id
        FROM request_offers o JOIN nurses n ON n.id=o.nurse_id
        JOIN care_requests r ON r.id=o.request_id
        WHERE n.user_id=$1 AND o.id=$2 AND o.status='OPEN'
          AND o.expires_at>statement_timestamp() AND r.status='OFFERING'`;
    const result = await this.db.query(`
      WITH subject AS (${subject}), policy AS (
        SELECT coalesce((value->>'lookbackDays')::int,90) AS days,
          coalesce((value->>'minAssignedVisits')::int,5) AS minimum
        FROM (SELECT (SELECT value FROM app_settings WHERE key='commitment') AS value) v
      )
      SELECT policy.days AS "lookbackDays", policy.minimum AS minimum,
        (SELECT count(*)::int FROM care_requests r WHERE r.requester_user_id=subject.patient_id
          AND EXISTS (SELECT 1 FROM request_assignments a WHERE a.request_id=r.id
            AND a.accepted_at>=statement_timestamp()-policy.days*interval '1 day')) AS "assignedVisits",
        (SELECT count(*)::int FROM request_cancellations c
          WHERE c.cancelled_by_user_id=subject.patient_id AND c.commitment_impact
            AND c.cancelled_at>=statement_timestamp()-policy.days*interval '1 day'
            AND NOT EXISTS (SELECT 1 FROM cancellation_appeals a WHERE a.cancellation_id=c.id
              AND a.submitter_role='PATIENT' AND a.status IN ${openAppeal})) AS "countedCancellations"
      FROM subject CROSS JOIN policy
    `, offerId === undefined ? [userId] : [userId, offerId]);
    if (!result.rowCount) missing();
    const { minimum, ...counts } = result.rows[0];
    return { ...counts, sufficient: counts.assignedVisits >= minimum };
  }

  async ownHistory(userId: string) {
    const [summary, history] = await Promise.all([
      this.summary(userId),
      this.db.query(`
        SELECT c.id,c.request_id AS "requestId",c.cancelled_at AS "cancelledAt",
          c.classification,c.commitment_impact AND coalesce(a.status NOT IN ${openAppeal},true) AS "commitmentImpact",
          a.id AS "appealId",a.status AS "appealStatus"
        FROM request_cancellations c
        LEFT JOIN cancellation_appeals a ON a.cancellation_id=c.id AND a.submitted_by_user_id=$1
        WHERE c.cancelled_by_user_id=$1 ORDER BY c.cancelled_at DESC,c.id DESC LIMIT 50
      `, [userId]),
    ]);
    return { ...summary, items: history.rows };
  }

  async forActiveOffer(nurseUserId: string, offerId: string) {
    const summary = await this.summary(nurseUserId, offerId);
    return summary.sufficient ? summary : { sufficient: false, lookbackDays: summary.lookbackDays };
  }
}
