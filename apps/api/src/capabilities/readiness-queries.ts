// Historical unparseable timestamps remain visible; only valid, expired events are excluded.
export const OUTBOX_HEALTH_SQL = `WITH current AS (
  SELECT * FROM outbox_events
  WHERE CASE WHEN pg_input_is_valid(payload->>'expiresAt', 'timestamptz')
    THEN (payload->>'expiresAt')::timestamptz > statement_timestamp() ELSE true END
), channels AS (
  SELECT *, $1::boolean AS track_realtime,
    ($2::boolean AND coalesce(payload->>'skipPush','false')<>'true'
      AND coalesce(payload->>'targetApp','')<>'ADMIN_WEB') AS track_push
  FROM current
)
SELECT
  count(*) FILTER (WHERE track_realtime AND realtime_published_at IS NULL AND realtime_dead_at IS NULL)::int AS pending_realtime,
  count(*) FILTER (WHERE track_push AND push_published_at IS NULL AND push_dead_at IS NULL)::int AS pending_push,
  min(created_at) FILTER (WHERE track_realtime AND realtime_published_at IS NULL AND realtime_dead_at IS NULL) AS oldest_realtime,
  min(created_at) FILTER (WHERE track_push AND push_published_at IS NULL AND push_dead_at IS NULL) AS oldest_push,
  count(*) FILTER (WHERE (track_realtime AND realtime_dead_at IS NOT NULL)
    OR (track_push AND push_dead_at IS NOT NULL))::int AS dead_letter_count
FROM channels`;
