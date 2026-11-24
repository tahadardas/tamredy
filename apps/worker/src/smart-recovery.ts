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
       SET status = 'EXPIRED', marketplace_status = 'EXPIRED', updated_at = now()
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

    // 4. Find open requests
    const openReqsRes = await client.query(
      `SELECT id, service_id, location, requester_user_id
       FROM care_requests
       WHERE status = 'OPEN_FOR_PROPOSALS' AND open_expires_at > now()`,
    );
    if (!openReqsRes.rowCount || openReqsRes.rowCount === 0) {
      return { expiredProposals, expiredRequests, alertsSent: 0 };
    }

    const openRequestIds = openReqsRes.rows.map(r => r.id);

    // 5. Find candidate idle nurses not in cooldown
    const nursesRes = await client.query(
      `SELECT n.id, n.user_id
       FROM nurses n
       JOIN users u ON u.id = n.user_id
       WHERE n.verified = true
         AND u.status = 'ACTIVE'
         -- Not in active assignment
         AND NOT EXISTS (
           SELECT 1 FROM request_assignments ra
           JOIN care_requests cr ON cr.id = ra.request_id
           WHERE ra.nurse_id = n.id
             AND ra.status = 'ACTIVE'
             AND cr.status IN ('ASSIGNED', 'EN_ROUTE', 'ARRIVED', 'IN_SERVICE')
         )
         -- Not in active cooldown
         AND NOT EXISTS (
           SELECT 1 FROM smart_recovery_deliveries srd
           WHERE srd.nurse_id = n.id
             AND srd.cooldown_until > now()
         )
         -- Has not exceeded daily limit
         AND (
           SELECT count(*) FROM smart_recovery_deliveries srd2
           WHERE srd2.nurse_id = n.id
             AND srd2.delivered_at >= date_trunc('day', now())
         ) < $1
       LIMIT 50`,
      [maxDaily],
    );

    let alertsSent = 0;

    for (const nurse of nursesRes.rows) {
      // Find matching open requests for this nurse (skills approved & no mutual block)
      const matchingRes = await client.query(
        `SELECT cr.id
         FROM care_requests cr
         WHERE cr.id = ANY($1::uuid[])
           AND NOT EXISTS (
             SELECT 1 FROM user_blocks ub
             WHERE ((ub.blocker_user_id = $2 AND ub.blocked_user_id = cr.requester_user_id)
                OR (ub.blocker_user_id = cr.requester_user_id AND ub.blocked_user_id = $2))
               AND ub.revoked_at IS NULL
           )
           AND NOT EXISTS (
             SELECT 1 FROM care_request_items cri
             WHERE cri.request_id = cr.id
               AND NOT EXISTS (
                 SELECT 1 FROM nurse_skills ns
                 WHERE ns.nurse_id = $3
                   AND ns.service_id = cri.service_id
                   AND ns.approved = true
               )
           )
           -- Do not re-alert if nurse already has a pending proposal
           AND NOT EXISTS (
             SELECT 1 FROM marketplace_proposals mp
             WHERE mp.request_id = cr.id AND mp.nurse_id = $3 AND mp.status = 'PENDING'
           )`,
        [openRequestIds, nurse.user_id, nurse.id],
      );

      const matchingCount = matchingRes.rowCount ?? 0;
      if (matchingCount > 0) {
        const matchingIds = matchingRes.rows.map(r => r.id);

        await client.query('BEGIN');
        try {
          // Record delivery with cooldown
          await client.query(
            `INSERT INTO smart_recovery_deliveries(
               nurse_id, request_ids, trigger_event, cooldown_until
             )
             VALUES($1, $2, 'OPEN_REQUESTS_MATCHED', now() + $3 * interval '1 minute')`,
            [nurse.id, matchingIds, cooldownMinutes],
          );

          // Emit outbox event for quiet push notification
          await client.query(
            `INSERT INTO outbox_events(event_type, aggregate_id, payload)
             VALUES('marketplace.recovery.alert', $1, $2::jsonb)`,
            [
              nurse.id,
              JSON.stringify({
                recipientUserId: nurse.user_id,
                openRequestsCount: matchingCount,
                requestIds: matchingIds,
              }),
            ],
          );

          await client.query('COMMIT');
          alertsSent++;
        } catch (e) {
          await client.query('ROLLBACK');
          console.error(`[SmartRecovery] Failed to alert nurse ${nurse.id}:`, e);
        }
      }
    }

    return { expiredProposals, expiredRequests, alertsSent };
  } finally {
    client.release();
  }
}
