-- Additive foundation. Existing waves, assignments and historical cancellations retain their semantics.
ALTER TABLE care_requests
  ADD COLUMN search_started_at timestamptz,
  ADD COLUMN search_expires_at timestamptz,
  ADD COLUMN search_radius_meters integer,
  ADD COLUMN closed_at timestamptz,
  ADD COLUMN close_reason text,
  ADD CONSTRAINT chk_care_request_search_window CHECK (
    (search_started_at IS NULL AND search_expires_at IS NULL AND search_radius_meters IS NULL)
    OR (search_started_at IS NOT NULL AND search_expires_at IS NOT NULL
      AND search_expires_at > search_started_at
      AND search_radius_meters IS NOT NULL AND search_radius_meters BETWEEN 500 AND 50000)
  ),
  ADD CONSTRAINT chk_care_request_search_closure CHECK (
    (closed_at IS NULL AND close_reason IS NULL)
    OR (closed_at IS NOT NULL AND close_reason IS NOT NULL
      AND close_reason IN ('ASSIGNED', 'CANCELLED', 'EXPIRED')
      AND (search_started_at IS NULL OR closed_at >= search_started_at))
  );

CREATE INDEX idx_open_dispatch_deadline ON care_requests(search_expires_at, id)
  WHERE status = 'OFFERING' AND search_expires_at IS NOT NULL;

ALTER TABLE request_assignments
  ADD COLUMN departed_at timestamptz,
  ADD COLUMN eta_reference_at timestamptz,
  ADD COLUMN eta_duration_seconds integer,
  ADD COLUMN expected_arrival_at timestamptz,
  ADD COLUMN eta_provider text,
  ADD COLUMN eta_status text,
  ADD COLUMN eta_version integer,
  ADD CONSTRAINT uq_assignment_request_reference UNIQUE (request_id, id),
  ADD CONSTRAINT chk_assignment_departure_eta CHECK (
    (departed_at IS NULL AND eta_reference_at IS NULL AND eta_duration_seconds IS NULL
      AND expected_arrival_at IS NULL AND eta_provider IS NULL AND eta_status IS NULL AND eta_version IS NULL)
    OR (departed_at IS NOT NULL AND departed_at >= accepted_at
      AND eta_version IS NOT NULL AND eta_version >= 1
      AND eta_reference_at IS NOT NULL AND eta_reference_at >= accepted_at
      AND eta_reference_at <= departed_at AND eta_status IS NOT NULL
      AND (
        (eta_status = 'AVAILABLE' AND eta_provider IS NOT NULL AND length(btrim(eta_provider)) > 0
          AND eta_duration_seconds IS NOT NULL AND eta_duration_seconds > 0
          AND expected_arrival_at IS NOT NULL
          AND expected_arrival_at = eta_reference_at + eta_duration_seconds * interval '1 second')
        OR (eta_status = 'ETA_UNAVAILABLE' AND eta_duration_seconds IS NULL
          AND expected_arrival_at IS NULL AND eta_provider IS NULL)
      ))
  );

CREATE TABLE request_cancellations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL UNIQUE REFERENCES care_requests(id),
  cancelled_by_user_id uuid NOT NULL REFERENCES users(id),
  assignment_id uuid,
  reason_code text NOT NULL CHECK (reason_code IN (
    'NO_LONGER_NEEDED', 'CREATED_BY_MISTAKE', 'FOUND_ANOTHER_NURSE',
    'TIME_NOT_SUITABLE', 'CHANGE_SERVICE_OR_LOCATION', 'WAITED_TOO_LONG',
    'HEALTH_CIRCUMSTANCE_CHANGED', 'OTHER', 'NURSE_DELAY_OVER_THRESHOLD',
    'SYSTEM_OR_LOCATION_ERROR', 'LEGACY_UNSPECIFIED'
  )),
  reason_note text CHECK (length(reason_note) <= 500),
  status_at_cancellation text NOT NULL CHECK (status_at_cancellation IN (
    'OFFERING', 'ASSIGNED', 'EN_ROUTE', 'ARRIVED', 'UNFULFILLED'
  )),
  cancelled_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  nurse_departed_at timestamptz,
  eta_reference_at timestamptz,
  expected_arrival_at timestamptz,
  delay_seconds integer,
  classification text NOT NULL CHECK (classification IN (
    'BEFORE_ASSIGNMENT', 'BEFORE_DEPARTURE', 'EN_ROUTE_COUNTED', 'NURSE_DELAY',
    'ETA_UNAVAILABLE', 'SYSTEM_ERROR', 'ARRIVAL_REVIEW', 'EXCUSED', 'LEGACY_UNCLASSIFIED'
  )),
  commitment_impact boolean NOT NULL DEFAULT false,
  policy_version integer NOT NULL CHECK (policy_version >= 1),
  idempotency_key text NOT NULL CHECK (length(btrim(idempotency_key)) BETWEEN 1 AND 128),
  payload_digest text NOT NULL CHECK (payload_digest ~ '^[a-f0-9]{64}$'),
  CONSTRAINT fk_cancellation_request_assignment
    FOREIGN KEY (request_id, assignment_id) REFERENCES request_assignments(request_id, id),
  CONSTRAINT uq_cancellation_actor_key UNIQUE (cancelled_by_user_id, idempotency_key),
  CONSTRAINT chk_cancellation_counted_evidence CHECK (
    NOT commitment_impact OR (
      classification = 'EN_ROUTE_COUNTED' AND status_at_cancellation = 'EN_ROUTE'
      AND assignment_id IS NOT NULL AND nurse_departed_at IS NOT NULL
      AND eta_reference_at IS NOT NULL AND expected_arrival_at IS NOT NULL
      AND eta_reference_at <= nurse_departed_at AND nurse_departed_at <= cancelled_at
      AND expected_arrival_at > eta_reference_at
      AND cancelled_at < expected_arrival_at + interval '30 minutes'
    )
  )
);

CREATE INDEX idx_cancellations_commitment ON request_cancellations(cancelled_by_user_id, cancelled_at DESC)
  WHERE commitment_impact;

CREATE TABLE cancellation_appeals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cancellation_id uuid NOT NULL REFERENCES request_cancellations(id),
  submitted_by_user_id uuid NOT NULL REFERENCES users(id),
  submitter_role text NOT NULL CHECK (submitter_role IN ('PATIENT', 'NURSE')),
  description text NOT NULL CHECK (length(btrim(description)) BETWEEN 1 AND 2000),
  status text NOT NULL DEFAULT 'SUBMITTED' CHECK (
    status IN ('SUBMITTED', 'UNDER_REVIEW', 'NEEDS_INFORMATION', 'APPROVED', 'REJECTED', 'CLOSED')
  ),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT uq_cancellation_appeal_submitter UNIQUE (cancellation_id, submitted_by_user_id)
);

CREATE INDEX idx_appeals_review_queue ON cancellation_appeals(created_at, id)
  WHERE status IN ('SUBMITTED', 'UNDER_REVIEW', 'NEEDS_INFORMATION');

CREATE TABLE cancellation_appeal_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  appeal_id uuid NOT NULL REFERENCES cancellation_appeals(id),
  actor_user_id uuid NOT NULL REFERENCES users(id),
  previous_status text NOT NULL CHECK (
    previous_status IN ('SUBMITTED', 'UNDER_REVIEW', 'NEEDS_INFORMATION', 'APPROVED', 'REJECTED', 'CLOSED')
  ),
  next_status text NOT NULL CHECK (
    next_status IN ('SUBMITTED', 'UNDER_REVIEW', 'NEEDS_INFORMATION', 'APPROVED', 'REJECTED', 'CLOSED')
  ),
  decision_note text NOT NULL CHECK (length(btrim(decision_note)) BETWEEN 1 AND 2000),
  occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CHECK (previous_status <> next_status)
);

CREATE INDEX idx_cancellation_appeal_events ON cancellation_appeal_events(appeal_id, id);

CREATE TABLE cancellation_classification_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  cancellation_id uuid NOT NULL REFERENCES request_cancellations(id),
  actor_user_id uuid NOT NULL REFERENCES users(id),
  previous_classification text NOT NULL,
  next_classification text NOT NULL,
  previous_impact boolean NOT NULL,
  next_impact boolean NOT NULL,
  decision_note text NOT NULL CHECK (length(btrim(decision_note)) BETWEEN 1 AND 2000),
  occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CHECK (previous_classification <> next_classification OR previous_impact <> next_impact)
);

CREATE INDEX idx_cancellation_classification_events ON cancellation_classification_events(cancellation_id, id);
