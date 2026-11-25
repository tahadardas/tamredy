ALTER TABLE outbox_events
  DROP CONSTRAINT chk_push_outbox_lease,
  DROP CONSTRAINT chk_realtime_outbox_lease,
  ADD CONSTRAINT chk_push_outbox_lease CHECK (push_lease_token IS NULL OR push_lease_until IS NOT NULL),
  ADD CONSTRAINT chk_realtime_outbox_lease CHECK (realtime_lease_token IS NULL OR realtime_lease_until IS NOT NULL),
  ADD COLUMN push_attempts integer NOT NULL DEFAULT 0 CHECK (push_attempts>=0),
  ADD COLUMN realtime_attempts integer NOT NULL DEFAULT 0 CHECK (realtime_attempts>=0),
  ADD COLUMN push_dead_at timestamptz,
  ADD COLUMN realtime_dead_at timestamptz;

CREATE INDEX idx_marketplace_approved_created
  ON care_requests(created_at DESC,id DESC)
  WHERE status='OPEN_FOR_PROPOSALS' AND clinical_approval_status IN ('NOT_REQUIRED','APPROVED');
