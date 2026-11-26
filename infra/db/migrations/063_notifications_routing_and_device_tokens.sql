-- Migration 063: Notification routing metadata & role/app-isolated device tokens

ALTER TABLE device_tokens
  ADD COLUMN IF NOT EXISTS device_id text,
  ADD COLUMN IF NOT EXISTS app_type text CHECK (app_type IS NULL OR app_type IN ('PATIENT_APP', 'NURSE_APP')),
  ADD COLUMN IF NOT EXISTS role text CHECK (role IS NULL OR role IN ('PATIENT', 'NURSE', 'ADMIN', 'CLINICAL_REVIEWER')),
  ADD COLUMN IF NOT EXISTS session_id uuid REFERENCES device_sessions(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS active_status text NOT NULL DEFAULT 'ACTIVE' CHECK (active_status IN ('ACTIVE', 'LOGOUT', 'REVOKED')),
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

-- Backfill role/app_type for any existing tokens from users table
UPDATE device_tokens dt
SET role = u.role,
    app_type = CASE WHEN u.role = 'NURSE' THEN 'NURSE_APP' WHEN u.role = 'PATIENT' THEN 'PATIENT_APP' ELSE NULL END
FROM users u
WHERE u.id = dt.user_id
  AND dt.role IS NULL;

CREATE INDEX IF NOT EXISTS idx_device_tokens_routing
  ON device_tokens(user_id, active_status, role, app_type);

CREATE INDEX IF NOT EXISTS idx_device_tokens_device_app
  ON device_tokens(device_id, app_type)
  WHERE device_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_device_tokens_session
  ON device_tokens(session_id)
  WHERE session_id IS NOT NULL;
