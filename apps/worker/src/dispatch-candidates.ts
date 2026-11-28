import type pg from 'pg';
import { dispatchLocations } from './live-location.ts';
import { nightPolicyEnabled } from './night-safety.ts';

interface Candidate {
  nurseId: string;
  reasons: string[];
  alreadyOffered: boolean;
}

/** Resolve each geographically bounded candidate once, under the caller's request lock. */
export async function collectDispatchCandidates(client: pg.PoolClient, requestId: string, radiusMeters: number): Promise<Candidate[]> {
  const locations = await dispatchLocations(client, requestId, radiusMeters);
  const result = await client.query<Candidate>(`
    WITH request AS MATERIALIZED (
      SELECT r.*, statement_timestamp() AS service_start,
        statement_timestamp()+greatest(1,coalesce((SELECT sum(expected_minutes)
          FROM care_request_items WHERE request_id=r.id),30))*interval '1 minute' AS service_end
      FROM care_requests r WHERE r.id=$1
    ), geographic AS MATERIALIZED (
      SELECT l.nurse_id, NULL::jsonb AS snapshot
      FROM request req JOIN nurse_locations l ON ST_DWithin(l.location,req.location,$2)
      WHERE $3::jsonb IS NULL
      UNION ALL
      SELECT (item->>'nurseId')::uuid AS nurse_id, item AS snapshot
      FROM jsonb_array_elements($3::jsonb) AS entries(item)
    )
    SELECT n.id AS "nurseId", EXISTS(SELECT 1 FROM request_offers o
        WHERE o.nurse_id=n.id AND o.request_id=req.id) AS "alreadyOffered",
      CASE WHEN u.status<>'ACTIVE' THEN ARRAY['NURSE_ACCOUNT_INACTIVE']
        WHEN NOT n.verified THEN ARRAY['NURSE_NOT_VERIFIED']
        WHEN n.availability_intent<>'AVAILABLE' OR n.work_status<>'AVAILABLE' THEN ARRAY['NURSE_NOT_AVAILABLE']
        WHEN n.last_heartbeat_at IS NULL OR n.last_heartbeat_at<req.service_start
            -coalesce(req.search_max_heartbeat_seconds,120)*interval '1 second' THEN ARRAY['HEARTBEAT_STALE']
        ELSE nurse_eligibility_reasons(n.id,req.id,'OFFER',req.service_start,req.service_end,g.snapshot,$2,$4)
      END AS reasons
    FROM geographic g JOIN nurses n ON n.id=g.nurse_id JOIN users u ON u.id=n.user_id CROSS JOIN request req
    ORDER BY n.id`, [requestId, radiusMeters, locations === null ? null : JSON.stringify(locations), nightPolicyEnabled()]);
  return result.rows;
}

export function diagnoseExclusions(candidates: Candidate[]) {
  const reasons: Record<string, number> = {};
  const excludedNurses: { nurse_code: string; reason: string; detail: string }[] = [];
  for (const candidate of candidates) {
    const reason = candidate.reasons[0];
    if (!reason) continue;
    reasons[reason] = (reasons[reason] ?? 0) + 1;
    if (excludedNurses.length < 15) {
      excludedNurses.push({ nurse_code: `N-${candidate.nurseId.slice(0,6)}`, reason, detail: reason });
    }
  }
  return { reasons, excludedNurses };
}
