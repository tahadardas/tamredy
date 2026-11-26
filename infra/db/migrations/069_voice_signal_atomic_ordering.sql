-- Migration 069: Atomic ordering & deduplication guarantees for WebRTC signaling (BUG-038)

CREATE UNIQUE INDEX IF NOT EXISTS uq_voice_signal_session_actor_seq
  ON voice_call_events(session_id, actor_user_id, sequence_number)
  WHERE sequence_number IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_voice_call_events_session_seq
  ON voice_call_events(session_id, sequence_number ASC, created_at ASC)
  WHERE sequence_number IS NOT NULL;
