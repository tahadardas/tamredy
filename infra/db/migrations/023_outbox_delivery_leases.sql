-- Short outbox claims persist across worker restarts and expire after a crash.
ALTER TABLE outbox_events
  ADD COLUMN push_lease_token uuid,
  ADD COLUMN push_lease_until timestamptz,
  ADD COLUMN realtime_lease_token uuid,
  ADD COLUMN realtime_lease_until timestamptz,
  ADD CONSTRAINT chk_push_outbox_lease CHECK ((push_lease_token IS NULL) = (push_lease_until IS NULL)),
  ADD CONSTRAINT chk_realtime_outbox_lease CHECK ((realtime_lease_token IS NULL) = (realtime_lease_until IS NULL));

ALTER TABLE notification_deliveries
  ADD COLUMN retry_lease_token uuid,
  ADD COLUMN retry_lease_until timestamptz,
  ADD CONSTRAINT chk_push_retry_lease CHECK ((retry_lease_token IS NULL) = (retry_lease_until IS NULL));
