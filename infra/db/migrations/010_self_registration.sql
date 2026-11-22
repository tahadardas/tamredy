-- Self-registration switches (admin can close either door).
INSERT INTO app_settings(key, value) VALUES
  ('registration', '{"patients":true,"nurses":true}')
ON CONFLICT (key) DO NOTHING;
CREATE INDEX IF NOT EXISTS idx_users_created ON users (created_at DESC);
