ALTER TABLE voice_call_sessions DROP CONSTRAINT IF EXISTS voice_call_sessions_call_status_check;
ALTER TABLE voice_call_sessions
  ADD CONSTRAINT voice_call_sessions_call_status_check CHECK(call_status IN (
    'INITIATED','RINGING','ACCEPTED','CONNECTING','CONNECTED','RECONNECTING',
    'REJECTED','MISSED','FAILED','ENDED','CANCELLED')),
  ADD COLUMN IF NOT EXISTS ringing_at timestamptz,
  ADD COLUMN IF NOT EXISTS ring_expires_at timestamptz,
  ADD COLUMN IF NOT EXISTS accepted_at timestamptz,
  ADD COLUMN IF NOT EXISTS initiation_key uuid,
  ADD COLUMN IF NOT EXISTS session_version integer NOT NULL DEFAULT 1;

UPDATE voice_call_sessions SET
  ringing_at=coalesce(ringing_at,started_at),
  ring_expires_at=coalesce(ring_expires_at,started_at+interval '40 seconds'),
  accepted_at=CASE WHEN call_status IN ('ACCEPTED','CONNECTING','CONNECTED','RECONNECTING','ENDED')
    THEN coalesce(accepted_at,connected_at,started_at) ELSE accepted_at END
WHERE ringing_at IS NULL OR ring_expires_at IS NULL
  OR (accepted_at IS NULL AND call_status IN ('ACCEPTED','CONNECTING','CONNECTED','RECONNECTING','ENDED'));

WITH duplicates AS (
  SELECT id,row_number() OVER(PARTITION BY request_id ORDER BY started_at,id) AS position
  FROM voice_call_sessions
  WHERE call_status IN ('INITIATED','RINGING','ACCEPTED','CONNECTING','CONNECTED','RECONNECTING')
)
UPDATE voice_call_sessions s SET call_status='FAILED',ended_at=coalesce(ended_at,now()),end_reason='MIGRATION_DUPLICATE_ACTIVE_CALL'
FROM duplicates d WHERE d.id=s.id AND d.position>1;

CREATE UNIQUE INDEX IF NOT EXISTS uq_voice_call_request_active
  ON voice_call_sessions(request_id)
  WHERE call_status IN ('INITIATED','RINGING','ACCEPTED','CONNECTING','CONNECTED','RECONNECTING');
CREATE UNIQUE INDEX IF NOT EXISTS uq_voice_call_initiation_key
  ON voice_call_sessions(caller_user_id,initiation_key) WHERE initiation_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_voice_calls_ring_timeout
  ON voice_call_sessions(ring_expires_at)
  WHERE call_status IN ('INITIATED','RINGING');

ALTER TABLE voice_call_events
  ADD COLUMN IF NOT EXISTS event_id uuid,
  ADD COLUMN IF NOT EXISTS sequence_number integer;
CREATE UNIQUE INDEX IF NOT EXISTS uq_voice_call_event_id ON voice_call_events(event_id) WHERE event_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_voice_call_signal_replay
  ON voice_call_events(session_id,actor_user_id,sequence_number)
  WHERE event_type IN ('SDP_OFFER','SDP_ANSWER','ICE_CANDIDATE','ICE_RESTART');

CREATE TABLE IF NOT EXISTS voice_call_quality_samples (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id uuid NOT NULL REFERENCES voice_call_sessions(id) ON DELETE CASCADE,
  reporter_user_id uuid NOT NULL REFERENCES users(id),
  rtt_ms numeric(10,2) CHECK(rtt_ms IS NULL OR rtt_ms>=0),
  jitter_ms numeric(10,2) CHECK(jitter_ms IS NULL OR jitter_ms>=0),
  packet_loss_percent numeric(6,3) CHECK(packet_loss_percent IS NULL OR packet_loss_percent BETWEEN 0 AND 100),
  bitrate_kbps numeric(12,2) CHECK(bitrate_kbps IS NULL OR bitrate_kbps>=0),
  candidate_type text,
  connection_type text,
  turn_used boolean,
  reconnection_count integer NOT NULL DEFAULT 0 CHECK(reconnection_count>=0),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_voice_quality_session_created ON voice_call_quality_samples(session_id,created_at DESC);
