-- Tamreedy 3.1 (BUG-022): permanently separate revoked device sessions from new logins
-- by disallowing reactivation of revoked rows and enforcing session generation checks.

ALTER TABLE device_sessions
  ADD COLUMN IF NOT EXISTS session_generation integer NOT NULL DEFAULT 1;

ALTER TABLE refresh_tokens
  ADD COLUMN IF NOT EXISTS device_session_generation integer;

ALTER TABLE device_sessions
  DROP CONSTRAINT IF EXISTS device_sessions_user_id_device_id_key;

ALTER TABLE device_sessions
  DROP CONSTRAINT IF EXISTS uq_user_device;

CREATE UNIQUE INDEX IF NOT EXISTS uq_active_device_session_per_user_device
  ON device_sessions(user_id, device_id)
  WHERE revoked_at IS NULL;
