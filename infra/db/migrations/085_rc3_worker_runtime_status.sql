ALTER TABLE worker_heartbeats
  ADD COLUMN worker_version text,
  ADD COLUMN runtime_config_fingerprint text CHECK (runtime_config_fingerprint ~ '^[0-9a-f]{64}$'),
  ADD COLUMN push_configured boolean,
  ADD COLUMN push_operational boolean,
  ADD COLUMN push_last_success_at timestamptz,
  ADD COLUMN push_last_error_at timestamptz,
  ADD COLUMN realtime_operational boolean,
  ADD COLUMN realtime_last_success_at timestamptz,
  ADD COLUMN realtime_last_error_at timestamptz,
  ADD COLUMN dispatch_last_success_at timestamptz,
  ADD COLUMN dispatch_last_error_at timestamptz;
