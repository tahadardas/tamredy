export const OUTBOX_HEALTH_SQL = `SELECT
        count(*) FILTER (WHERE realtime_published_at IS NULL AND realtime_dead_at IS NULL)::int AS pending_realtime,
        count(*) FILTER (WHERE push_published_at IS NULL AND push_dead_at IS NULL
          AND coalesce(payload->>'skipPush','false')<>'true'
          AND CASE WHEN payload->>'expiresAt' ~ '^\\d{4}-\\d{2}-\\d{2}T' THEN (payload->>'expiresAt')::timestamptz > statement_timestamp() ELSE true END)::int AS pending_push,
        min(created_at) FILTER (WHERE realtime_published_at IS NULL AND realtime_dead_at IS NULL) AS oldest_realtime,
        min(created_at) FILTER (WHERE push_published_at IS NULL AND push_dead_at IS NULL
          AND coalesce(payload->>'skipPush','false')<>'true'
          AND CASE WHEN payload->>'expiresAt' ~ '^\\d{4}-\\d{2}-\\d{2}T' THEN (payload->>'expiresAt')::timestamptz > statement_timestamp() ELSE true END) AS oldest_push,
        count(*) FILTER (WHERE realtime_dead_at IS NOT NULL OR push_dead_at IS NOT NULL)::int AS dead_letter_count
        FROM outbox_events`;
