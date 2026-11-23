-- Migration 019: Device sessions, persistent authentication, and sliding refresh window
-- P0: Ensure trusted devices retain their sessions over months without unexpected logouts.

CREATE TABLE IF NOT EXISTS device_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id TEXT NOT NULL,
  device_name TEXT,
  platform TEXT DEFAULT 'android',
  app_kind TEXT,
  trusted BOOLEAN NOT NULL DEFAULT true,
  revoked_at TIMESTAMPTZ,
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_user_device UNIQUE(user_id, device_id)
);

CREATE INDEX IF NOT EXISTS idx_device_sessions_user ON device_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_device_sessions_device ON device_sessions(device_id);

-- Enhance refresh_tokens with device session linkage and rotation grace tracking
ALTER TABLE refresh_tokens ADD COLUMN IF NOT EXISTS device_session_id UUID REFERENCES device_sessions(id) ON DELETE CASCADE;
ALTER TABLE refresh_tokens ADD COLUMN IF NOT EXISTS replaced_by_hash TEXT;

CREATE INDEX IF NOT EXISTS idx_refresh_tokens_hash ON refresh_tokens(token_hash);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_device ON refresh_tokens(device_session_id);
