-- P0: central request lifecycle integrity and booking/marketplace state repair.
-- This migration is additive and preserves all historical rows and identifiers.

-- marketplace_status describes the marketplace channel only. It must never
-- mirror booking mode or the complete request lifecycle.
ALTER TABLE care_requests
  DROP CONSTRAINT IF EXISTS care_requests_marketplace_status_check;

UPDATE care_requests
SET marketplace_status = CASE
  WHEN status = 'OPEN_FOR_PROPOSALS' THEN 'OPEN_FOR_PROPOSALS'
  WHEN status = 'ASSIGNED' THEN 'ASSIGNED'
  WHEN status = 'CANCELLED' THEN 'CANCELLED'
  WHEN status IN ('EXPIRED', 'UNFULFILLED') THEN 'EXPIRED'
  WHEN booking_mode = 'INSTANT' AND status = 'OFFERING' THEN 'SEARCHING'
  ELSE 'INITIAL'
END
WHERE marketplace_status NOT IN (
  'INITIAL', 'SEARCHING', 'AWAITING_RECOVERY_CHOICE',
  'OPEN_FOR_PROPOSALS', 'ASSIGNED', 'EXPIRED', 'CANCELLED'
);

ALTER TABLE care_requests
  ADD CONSTRAINT care_requests_marketplace_status_check CHECK (marketplace_status IN (
    'INITIAL', 'SEARCHING', 'AWAITING_RECOVERY_CHOICE',
    'OPEN_FOR_PROPOSALS', 'ASSIGNED', 'EXPIRED', 'CANCELLED'
  )) NOT VALID;
ALTER TABLE care_requests VALIDATE CONSTRAINT care_requests_marketplace_status_check;

ALTER TABLE care_requests
  DROP CONSTRAINT IF EXISTS care_requests_original_booking_mode_check;
ALTER TABLE care_requests
  ADD CONSTRAINT care_requests_original_booking_mode_check
  CHECK (original_booking_mode IN ('INSTANT', 'OPEN', 'SCHEDULED')) NOT VALID;
ALTER TABLE care_requests VALIDATE CONSTRAINT care_requests_original_booking_mode_check;

ALTER TABLE request_cancellations
  DROP CONSTRAINT IF EXISTS request_cancellations_status_at_cancellation_check;
ALTER TABLE request_cancellations
  ADD CONSTRAINT request_cancellations_status_at_cancellation_check
  CHECK (status_at_cancellation IN (
    'SCHEDULED', 'OFFERING', 'AWAITING_RECOVERY_CHOICE', 'OPEN_FOR_PROPOSALS',
    'ASSIGNED', 'EN_ROUTE', 'ARRIVED', 'UNFULFILLED'
  )) NOT VALID;
ALTER TABLE request_cancellations
  VALIDATE CONSTRAINT request_cancellations_status_at_cancellation_check;

CREATE TABLE IF NOT EXISTS request_status_transitions (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  request_id uuid NOT NULL REFERENCES care_requests(id),
  from_status text NOT NULL,
  to_status text NOT NULL,
  from_version integer NOT NULL CHECK (from_version >= 1),
  to_version integer NOT NULL CHECK (to_version = from_version + 1),
  actor_kind text NOT NULL CHECK (actor_kind IN ('PATIENT','NURSE','ADMIN','WORKER','SYSTEM')),
  actor_user_id uuid REFERENCES users(id),
  reason text NOT NULL CHECK (length(btrim(reason)) BETWEEN 1 AND 120),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(metadata) = 'object'),
  occurred_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  CHECK (from_status <> to_status)
);

CREATE INDEX IF NOT EXISTS idx_request_status_transitions_request
  ON request_status_transitions(request_id, id DESC);

CREATE OR REPLACE FUNCTION request_status_transition_allowed(p_from text, p_to text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE p_from
    WHEN 'SCHEDULED' THEN p_to IN ('OFFERING','UNFULFILLED','CANCELLED','EXPIRED')
    WHEN 'OFFERING' THEN p_to IN ('OPEN_FOR_PROPOSALS','ASSIGNED','UNFULFILLED','CANCELLED','EXPIRED')
    WHEN 'AWAITING_RECOVERY_CHOICE' THEN p_to IN ('OFFERING','OPEN_FOR_PROPOSALS','SCHEDULED','CANCELLED','EXPIRED')
    WHEN 'OPEN_FOR_PROPOSALS' THEN p_to IN ('OFFERING','SCHEDULED','ASSIGNED','UNFULFILLED','CANCELLED','EXPIRED')
    WHEN 'ASSIGNED' THEN p_to IN ('EN_ROUTE','CANCELLED','ESCALATED')
    WHEN 'EN_ROUTE' THEN p_to IN ('ARRIVED','CANCELLED','ESCALATED')
    WHEN 'ARRIVED' THEN p_to IN ('IN_SERVICE','ESCALATED')
    WHEN 'IN_SERVICE' THEN p_to IN ('COMPLETED','ESCALATED')
    WHEN 'UNFULFILLED' THEN p_to IN ('OFFERING','OPEN_FOR_PROPOSALS','SCHEDULED','CANCELLED','EXPIRED')
    WHEN 'ESCALATED' THEN p_to IN ('IN_SERVICE','COMPLETED','CANCELLED')
    ELSE false
  END
$$;

CREATE OR REPLACE FUNCTION enforce_request_status_transition()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_actor_kind text;
  v_actor_user_id uuid;
  v_reason text;
  v_metadata jsonb;
BEGIN
  IF NEW.status = OLD.status THEN
    RETURN NEW;
  END IF;

  IF NOT request_status_transition_allowed(OLD.status, NEW.status) THEN
    RAISE EXCEPTION 'REQUEST_STATUS_TRANSITION_NOT_ALLOWED: % -> %', OLD.status, NEW.status
      USING ERRCODE = '23514';
  END IF;

  IF NEW.version <> OLD.version + 1 THEN
    RAISE EXCEPTION 'REQUEST_STATUS_VERSION_MUST_INCREMENT: % -> %', OLD.version, NEW.version
      USING ERRCODE = '23514';
  END IF;

  v_actor_kind := coalesce(nullif(current_setting('app.request_actor_kind', true), ''), 'SYSTEM');
  v_actor_user_id := nullif(current_setting('app.request_actor_user_id', true), '')::uuid;
  v_reason := coalesce(nullif(current_setting('app.request_transition_reason', true), ''), 'LEGACY_CALLER');
  v_metadata := coalesce(nullif(current_setting('app.request_transition_metadata', true), '')::jsonb, '{}'::jsonb);

  INSERT INTO request_status_transitions(
    request_id, from_status, to_status, from_version, to_version,
    actor_kind, actor_user_id, reason, metadata
  ) VALUES (
    OLD.id, OLD.status, NEW.status, OLD.version, NEW.version,
    v_actor_kind, v_actor_user_id, v_reason, v_metadata
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_request_status_transition ON care_requests;
CREATE TRIGGER trg_enforce_request_status_transition
BEFORE UPDATE OF status ON care_requests
FOR EACH ROW
WHEN (OLD.status IS DISTINCT FROM NEW.status)
EXECUTE FUNCTION enforce_request_status_transition();
