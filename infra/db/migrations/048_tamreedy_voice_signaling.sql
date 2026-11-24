-- Migration 048: Tamreedy Voice In-App Calling Sessions & WebRTC Signaling Events

CREATE TABLE IF NOT EXISTS voice_call_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES care_requests(id) ON DELETE CASCADE,
  caller_user_id uuid NOT NULL REFERENCES users(id),
  receiver_user_id uuid NOT NULL REFERENCES users(id),
  call_status text NOT NULL DEFAULT 'INITIATED' CHECK (call_status IN (
    'INITIATED', 'RINGING', 'ACCEPTED', 'CONNECTING', 'CONNECTED',
    'REJECTED', 'MISSED', 'FAILED', 'ENDED'
  )),
  room_token text NOT NULL UNIQUE,
  started_at timestamptz NOT NULL DEFAULT now(),
  connected_at timestamptz,
  ended_at timestamptz,
  duration_seconds integer NOT NULL DEFAULT 0 CHECK (duration_seconds >= 0),
  end_reason text,
  ice_servers jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS voice_call_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id uuid NOT NULL REFERENCES voice_call_sessions(id) ON DELETE CASCADE,
  actor_user_id uuid REFERENCES users(id),
  event_type text NOT NULL,
  event_data jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_voice_call_sessions_request ON voice_call_sessions(request_id);
CREATE INDEX IF NOT EXISTS idx_voice_call_sessions_users ON voice_call_sessions(caller_user_id, receiver_user_id, call_status);
CREATE INDEX IF NOT EXISTS idx_voice_call_events_session ON voice_call_events(session_id, created_at ASC);
