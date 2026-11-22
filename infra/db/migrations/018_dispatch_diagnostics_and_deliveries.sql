-- Migration 018: Dispatch diagnostics, decoupled notification deliveries & reliability indexes
-- P0: Complete visibility into dispatch candidate matching, exclusions, and FCM delivery attempts

CREATE TABLE IF NOT EXISTS dispatch_diagnostics (
  id BIGSERIAL PRIMARY KEY,
  request_id UUID NOT NULL REFERENCES care_requests(id) ON DELETE CASCADE,
  wave_no INT NOT NULL,
  radius_m INT NOT NULL,
  candidates_found INT NOT NULL DEFAULT 0,
  offers_created INT NOT NULL DEFAULT 0,
  exclusion_reasons JSONB NOT NULL DEFAULT '{}'::jsonb,
  excluded_nurses JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_dispatch_diagnostics_req
  ON dispatch_diagnostics(request_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_dispatch_diagnostics_created
  ON dispatch_diagnostics(created_at DESC);

-- Separate delivery ledger for device pushes (FCM) and notifications
CREATE TABLE IF NOT EXISTS notification_deliveries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id BIGINT REFERENCES outbox_events(id) ON DELETE CASCADE,
  recipient_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_token TEXT,
  channel VARCHAR(32) NOT NULL DEFAULT 'FCM_PUSH', -- 'FCM_PUSH', 'SOCKET_IO'
  status VARCHAR(32) NOT NULL DEFAULT 'PENDING',    -- 'PENDING', 'SENT', 'FAILED', 'UNREGISTERED', 'ACKNOWLEDGED'
  attempts INT NOT NULL DEFAULT 0,
  max_attempts INT NOT NULL DEFAULT 3,
  next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_error_code TEXT,
  last_error_detail TEXT,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  sent_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_notification_deliveries_pending
  ON notification_deliveries(status, next_attempt_at)
  WHERE status IN ('PENDING', 'FAILED');

CREATE INDEX IF NOT EXISTS idx_notification_deliveries_event
  ON notification_deliveries(event_id);

CREATE INDEX IF NOT EXISTS idx_notification_deliveries_recipient
  ON notification_deliveries(recipient_user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_notification_deliveries_created
  ON notification_deliveries(created_at DESC);

-- Decouple outbox events: track realtime (Redis/Socket.IO) and Push (FCM) independently
ALTER TABLE outbox_events ADD COLUMN IF NOT EXISTS realtime_published_at TIMESTAMPTZ;
ALTER TABLE outbox_events ADD COLUMN IF NOT EXISTS push_published_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_outbox_unrealtime
  ON outbox_events(id) WHERE realtime_published_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_outbox_unpush
  ON outbox_events(id) WHERE push_published_at IS NULL;

-- High performance indexing for candidate matching and dispatch worker
CREATE INDEX IF NOT EXISTS idx_nurses_dispatch_eval
  ON nurses(work_status, availability_intent, last_heartbeat_at)
  WHERE verified = true;

CREATE INDEX IF NOT EXISTS idx_nurse_locations_eval
  ON nurse_locations(recorded_at, accuracy_m);

CREATE INDEX IF NOT EXISTS idx_nurse_skills_lookup
  ON nurse_skills(nurse_id, service_id)
  WHERE approved = true;

CREATE INDEX IF NOT EXISTS idx_nurse_credentials_lookup
  ON nurse_credentials(nurse_id, expires_at)
  WHERE approved = true;

CREATE INDEX IF NOT EXISTS idx_request_offers_status_expires
  ON request_offers(status, expires_at);

CREATE INDEX IF NOT EXISTS idx_dispatch_jobs_run
  ON dispatch_jobs(next_run_at);
