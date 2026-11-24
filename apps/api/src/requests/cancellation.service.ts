import { createHash } from 'node:crypto';
import type { PoolClient } from 'pg';
import { conflict, invalid, missing } from '../common/errors.js';
import { DuesService } from '../pricing/fees.service.js';
import type { CancelRequestDto } from './cancel-request.dto.js';

import { closeOpenOffers } from '../dispatch/offer-outbox.js';

type Evidence = {
  status: string;
  departed: boolean;
  etaAvailable: boolean;
  thresholdMet: boolean;
};

export function cancellationClassification(evidence: Evidence, legacy: boolean) {
  if (['SCHEDULED', 'OFFERING'].includes(evidence.status)) return 'BEFORE_ASSIGNMENT';
  if (evidence.status === 'ASSIGNED') return 'BEFORE_DEPARTURE';
  if (evidence.status !== 'EN_ROUTE') return 'LEGACY_UNCLASSIFIED';
  if (!evidence.departed || !evidence.etaAvailable) return 'ETA_UNAVAILABLE';
  if (evidence.thresholdMet) return 'NURSE_DELAY';
  return legacy ? 'LEGACY_UNCLASSIFIED' : 'EN_ROUTE_COUNTED';
}

function response(row: Record<string, unknown>, replayed: boolean) {
  return {
    requestId: row.request_id, status: 'CANCELLED', cancellationId: row.id,
    reasonCode: row.reason_code, policyClassification: row.classification,
    commitmentImpact: row.commitment_impact, lateBySeconds: row.delay_seconds,
    wasNurseAssigned: row.assignment_id !== null, notificationQueued: true, replayed,
  };
}

export async function cancelRequest(
  client: PoolClient, userId: string, requestId: string, dto: CancelRequestDto,
) {
  const request = (await client.query(`SELECT id,status,version,search_max_heartbeat_seconds
    FROM care_requests WHERE id=$1 AND requester_user_id=$2 FOR UPDATE`, [requestId, userId])).rows[0];
  if (!request) missing();

  const legacy = dto.reasonCode === undefined && dto.idempotencyKey === undefined;
  const key = dto.idempotencyKey?.trim() ?? (legacy ? `legacy:${requestId}` : '');
  if (!key || (!legacy && (!dto.reasonCode || key.startsWith('legacy:')))) {
    invalid('CANCELLATION_REASON_AND_KEY_REQUIRED');
  }
  const reason = dto.reasonCode ?? 'LEGACY_UNSPECIFIED';
  const note = dto.reasonNote?.trim() || null;
  const digest = createHash('sha256').update(JSON.stringify([
    requestId, reason, note, dto.expectedVersion ?? null, dto.policyAcknowledged === true,
  ])).digest('hex');

  const previous = (await client.query(`SELECT c.*,
      coalesce(change.previous_classification,c.classification) AS original_classification,
      coalesce(change.previous_impact,c.commitment_impact) AS original_impact
    FROM request_cancellations c LEFT JOIN LATERAL (
      SELECT previous_classification,previous_impact FROM cancellation_classification_events
      WHERE cancellation_id=c.id ORDER BY id LIMIT 1
    ) change ON true WHERE c.cancelled_by_user_id=$1 AND c.idempotency_key=$2`, [userId, key])).rows[0];
  if (previous) {
    if (previous.payload_digest !== digest) conflict('IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD');
    return response({...previous, classification: previous.original_classification, commitment_impact: previous.original_impact}, true);
  }
  if (request.status === 'CANCELLED') {
    if (!legacy) conflict('REQUEST_ALREADY_CANCELLED');
    return {requestId, status: 'CANCELLED', replayed: true};
  }
  if (request.status === 'ARRIVED') conflict('ARRIVAL_REVIEW_REQUIRED');
  if (request.status === 'IN_SERVICE') conflict('EARLY_TERMINATION_REQUIRED');
  if (!['SCHEDULED', 'OFFERING', 'ASSIGNED', 'EN_ROUTE', 'UNFULFILLED'].includes(request.status)) {
    conflict('REQUEST_CANNOT_BE_CANCELLED');
  }
  if (dto.expectedVersion !== undefined && dto.expectedVersion !== request.version) {
    conflict('REQUEST_STATE_CHANGED');
  }

  const assignment = (await client.query(`SELECT id,nurse_id FROM request_assignments
    WHERE request_id=$1 AND status='ACTIVE'`, [requestId])).rows[0];
  let nurseUserId: string | undefined;
  if (assignment) {
    const nurse = await client.query('SELECT user_id FROM nurses WHERE id=$1 FOR UPDATE', [assignment.nurse_id]);
    nurseUserId = nurse.rows[0]?.user_id;
    await client.query('SELECT id FROM request_assignments WHERE id=$1 FOR UPDATE', [assignment.id]);
  }

  // PostgreSQL captures one decision time after all contested locks have been acquired.
  const snapshot = (await client.query(`WITH decision AS (SELECT statement_timestamp() AS at)
    SELECT at::text AS cancelled_at,
      a.departed_at::text AS departed_at, a.eta_reference_at::text AS eta_reference_at,
      a.expected_arrival_at::text AS expected_arrival_at,
      a.eta_status='AVAILABLE' AS eta_available,
      at>=a.expected_arrival_at+interval '30 minutes' AS threshold_met,
      CASE WHEN a.expected_arrival_at IS NOT NULL THEN
        greatest(0,floor(EXTRACT(EPOCH FROM (at-a.expected_arrival_at))))::integer END AS delay_seconds
    FROM decision LEFT JOIN request_assignments a ON a.id=$1`, [assignment?.id ?? null])).rows[0];
  const classification = cancellationClassification({
    status: request.status, departed: snapshot.departed_at != null,
    etaAvailable: snapshot.eta_available === true, thresholdMet: snapshot.threshold_met === true,
  }, legacy);
  const counts = classification === 'EN_ROUTE_COUNTED';
  if (counts && !dto.policyAcknowledged) conflict('CANCELLATION_POLICY_ACK_REQUIRED');
  const recordedReason = classification === 'NURSE_DELAY' ? 'NURSE_DELAY_OVER_THRESHOLD' : reason;

  const written = await client.query(`
    INSERT INTO request_cancellations(request_id,cancelled_by_user_id,assignment_id,reason_code,
      reason_note,status_at_cancellation,cancelled_at,nurse_departed_at,eta_reference_at,expected_arrival_at,
      delay_seconds,classification,commitment_impact,policy_version,idempotency_key,payload_digest)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,1,$14,$15)
    ON CONFLICT(cancelled_by_user_id,idempotency_key) DO NOTHING
    RETURNING *
  `, [requestId,userId,assignment?.id ?? null,recordedReason,note,request.status,snapshot.cancelled_at,
    snapshot.departed_at,snapshot.eta_reference_at,snapshot.expected_arrival_at,snapshot.delay_seconds,
    classification,counts,key,digest]);
  if (!written.rowCount) conflict('IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD');

  if (assignment) {
    await client.query(`UPDATE request_assignments SET status='RELEASED',released_at=$2,reason='PATIENT_CANCELLED'
      WHERE id=$1`, [assignment.id, snapshot.cancelled_at]);
    const dues = await new DuesService().balance(client, assignment.nurse_id);
    const pause = request.status === 'EN_ROUTE' && (await client.query(
      "SELECT value->>'pauseAfterTravelCancellation' = 'true' AS enabled FROM app_settings WHERE key='dispatch'",
    )).rows[0]?.enabled === true;
    await client.query(`UPDATE nurses n SET availability_intent=CASE WHEN $5::boolean THEN 'PAUSED' ELSE n.availability_intent END,
      work_status=CASE
        WHEN $5::boolean OR n.availability_intent='PAUSED' THEN 'PAUSED'
        WHEN n.verified AND n.availability_intent='AVAILABLE' AND NOT $3::boolean
          AND n.last_heartbeat_at>$2::timestamptz-$4::int*interval '1 second'
          AND EXISTS (SELECT 1 FROM users u WHERE u.id=n.user_id AND u.status='ACTIVE')
          AND EXISTS (SELECT 1 FROM nurse_credentials nc WHERE nc.nurse_id=n.id AND nc.approved AND nc.expires_at>$2)
          AND EXISTS (SELECT 1 FROM nurse_locations nl WHERE nl.nurse_id=n.id
            AND nl.recorded_at>$2::timestamptz-interval '120 seconds')
          AND NOT EXISTS (SELECT 1 FROM request_assignments a WHERE a.nurse_id=n.id AND a.status='ACTIVE')
        THEN 'AVAILABLE' ELSE 'OFFLINE' END, updated_at=$2
      WHERE n.id=$1`, [assignment.nurse_id, snapshot.cancelled_at, dues.blocked,
      request.search_max_heartbeat_seconds ?? 120, pause]);
  }
  if (reason === 'SYSTEM_OR_LOCATION_ERROR') {
    await client.query(`INSERT INTO incidents(request_id,reported_by,severity,description)
      VALUES($1,$2,'MEDIUM','Patient reported a system or location problem during cancellation')`, [requestId,userId]);
  }
  await closeOpenOffers(client, requestId, 'CANCELLED');
  await client.query(`UPDATE care_requests SET status='CANCELLED',version=version+1,updated_at=$2,
    closed_at=coalesce(closed_at,$2),close_reason=coalesce(close_reason,'CANCELLED') WHERE id=$1`,
  [requestId, snapshot.cancelled_at]);
  await client.query('DELETE FROM dispatch_jobs WHERE request_id=$1', [requestId]);
  await client.query(`INSERT INTO request_events(request_id,actor_user_id,event_type)
    VALUES($1,$2,'request.cancelled')`, [requestId,userId]);
  await client.query(`INSERT INTO outbox_events(event_type,aggregate_id,payload)
    VALUES('request.cancelled',$1,$2::jsonb)`, [requestId, JSON.stringify({
    requestId, recipientUserIds: nurseUserId ? [userId, nurseUserId] : [userId],
  })]);
  return response(written.rows[0], false);
}
