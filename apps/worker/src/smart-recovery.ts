import pg from 'pg';

export interface SmartRecoveryPolicy {
  smartRecoveryEnabled?: boolean;
  recoveryCooldownMinutes?: number;
  recoveryMaxDaily?: number;
  recoveryAggregationSeconds?: number;
}

/**
 * Runs periodic background maintenance for the Open Marketplace:
 * 1. Closes expired proposals.
 * 2. Closes expired open requests.
 * 3. Quiet Smart Alerting: Finds qualified idle nurses not in cooldown and alerts them about open requests.
 */
export async function runSmartRecoveryJob(pool: pg.Pool): Promise<{
  expiredProposals: number;
  expiredRequests: number;
  alertsSent: number;
}> {
  const client = await pool.connect();
  try {
    // 1. Expire stale proposals
    const expPropRes = await client.query(
      `UPDATE marketplace_proposals
       SET status = 'EXPIRED', updated_at = now()
       WHERE status = 'PENDING' AND expires_at <= now()`,
    );
    const expiredProposals = expPropRes.rowCount ?? 0;

    // 2. Expire stale open requests
    const expReqRes = await client.query(
      `UPDATE care_requests
       SET status = 'EXPIRED', marketplace_status = 'EXPIRED', version = version + 1, updated_at = now()
       WHERE status = 'OPEN_FOR_PROPOSALS' AND open_expires_at <= now()`,
    );
    const expiredRequests = expReqRes.rowCount ?? 0;

    // 3. Load policies
    const policyRes = await client.query(
      `SELECT value FROM app_settings WHERE key = 'booking_policies'`,
    );
    const policy: SmartRecoveryPolicy = policyRes.rows[0]?.value ?? {};
    if (policy.smartRecoveryEnabled === false) {
      return { expiredProposals, expiredRequests, alertsSent: 0 };
    }

    const cooldownMinutes = Number(policy.recoveryCooldownMinutes) || 15;
    const maxDaily = Number(policy.recoveryMaxDaily) || 8;

    // Candidate discovery, skill/block checks, delivery recording, and outbox
    // publication are intentionally set-based. This keeps query count constant
    // and lets PostgreSQL use the spatial, skill, and active-state indexes.
    let alertsSent = 0;
    await client.query('BEGIN');
    try {
      const lock = await client.query(`SELECT pg_try_advisory_xact_lock(hashtext('tamreedy.smart-recovery')) AS acquired`);
      if (!lock.rows[0]?.acquired) {
        await client.query('ROLLBACK');
        return { expiredProposals, expiredRequests, alertsSent: 0 };
      }
      const deliveries = await client.query(
      `WITH candidate_nurses AS MATERIALIZED (
         SELECT n.id,n.user_id,nl.location
         FROM nurses n
         JOIN users u ON u.id=n.user_id AND u.status='ACTIVE'
         JOIN nurse_locations nl ON nl.nurse_id=n.id
           AND nl.captured_at > statement_timestamp()-interval '120 seconds'
           AND nl.accuracy_m <= 150
         WHERE n.verified AND n.availability_intent='AVAILABLE' AND n.work_status='AVAILABLE'
           AND n.last_heartbeat_at > statement_timestamp()-interval '120 seconds'
           AND EXISTS (SELECT 1 FROM nurse_credentials nc
             WHERE nc.nurse_id=n.id AND nc.approved AND nc.expires_at>statement_timestamp())
           AND NOT EXISTS (SELECT 1 FROM request_assignments ra
             WHERE ra.nurse_id=n.id AND ra.status IN ('RESERVED','ACTIVE'))
           AND NOT EXISTS (SELECT 1 FROM smart_recovery_deliveries d
             WHERE d.nurse_id=n.id AND d.cooldown_until>statement_timestamp())
           AND (SELECT count(*) FROM smart_recovery_deliveries d
             WHERE d.nurse_id=n.id AND d.delivered_at>=date_trunc('day',statement_timestamp())) < $1
         ORDER BY n.last_heartbeat_at DESC,n.id
         LIMIT 50
       ), matched AS MATERIALIZED (
         SELECT cn.id AS nurse_id,cn.user_id,
           (array_agg(r.id ORDER BY ST_Distance(cn.location,r.location),r.created_at))[1:20] AS request_ids
         FROM candidate_nurses cn
         JOIN care_requests r ON r.status='OPEN_FOR_PROPOSALS'
           AND r.clinical_approval_status IN ('NOT_REQUIRED','APPROVED')
           AND r.open_expires_at>statement_timestamp()
           AND ST_DWithin(cn.location,r.location,LEAST(r.search_radius_meters,25000))
         WHERE EXISTS (SELECT 1 FROM nurse_skills ns
             WHERE ns.nurse_id=cn.id AND ns.service_id=r.service_id AND ns.approved)
           AND NOT EXISTS (SELECT 1 FROM care_request_items ri
             WHERE ri.request_id=r.id AND NOT EXISTS (SELECT 1 FROM nurse_skills ns
               WHERE ns.nurse_id=cn.id AND ns.service_id=ri.service_id AND ns.approved))
           AND NOT EXISTS (SELECT 1 FROM user_blocks b WHERE b.revoked_at IS NULL AND
             ((b.blocker_user_id=cn.user_id AND b.blocked_user_id=r.requester_user_id)
              OR (b.blocker_user_id=r.requester_user_id AND b.blocked_user_id=cn.user_id)))
           AND NOT EXISTS (SELECT 1 FROM marketplace_proposals p
             WHERE p.request_id=r.id AND p.nurse_id=cn.id AND p.status='PENDING')
         GROUP BY cn.id,cn.user_id
       ), inserted AS (
         INSERT INTO smart_recovery_deliveries(nurse_id,request_ids,trigger_event,cooldown_until)
         SELECT nurse_id,request_ids,'OPEN_REQUESTS_MATCHED',
           statement_timestamp()+$2::integer*interval '1 minute' FROM matched
         RETURNING nurse_id,request_ids
       ), events AS (
         INSERT INTO outbox_events(event_type,aggregate_id,payload)
         SELECT 'marketplace.recovery.alert',i.nurse_id,
           jsonb_build_object(
             'eventType','marketplace.recovery.alert',
             'recipientUserId',m.user_id,
             'recipientRole','NURSE',
             'targetApp','NURSE_APP',
             'priority','NORMAL',
             'deepLink','tamreedy://nurse/marketplace',
             'openRequestsCount',cardinality(i.request_ids),
             'requestIds',i.request_ids
           )
         FROM inserted i JOIN matched m ON m.nurse_id=i.nurse_id
         RETURNING id
       ) SELECT count(*)::integer AS alerts_sent FROM events`,
      [maxDaily,cooldownMinutes],
    );
      alertsSent = Number(deliveries.rows[0]?.alerts_sent ?? 0);
      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    }

    return { expiredProposals, expiredRequests, alertsSent };
  } finally {
    client.release();
  }
}
