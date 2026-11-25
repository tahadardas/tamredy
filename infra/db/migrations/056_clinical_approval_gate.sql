-- P1: enforce clinical approval as a dispatch gate, not a presentation flag.
ALTER TABLE care_requests
  ADD COLUMN IF NOT EXISTS clinical_approval_status text NOT NULL DEFAULT 'NOT_REQUIRED',
  ADD CONSTRAINT care_requests_clinical_approval_status_check CHECK (
    clinical_approval_status IN ('NOT_REQUIRED','PENDING','APPROVED','REJECTED')
  ) NOT VALID;
ALTER TABLE care_requests VALIDATE CONSTRAINT care_requests_clinical_approval_status_check;

CREATE TABLE request_clinical_evidence (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES care_requests(id),
  uploaded_by uuid NOT NULL REFERENCES users(id),
  evidence_type text NOT NULL CHECK(evidence_type IN ('PRESCRIPTION','CLINICAL_REPORT','REFERRAL','OTHER')),
  storage_key text NOT NULL UNIQUE,
  original_filename text NOT NULL,
  mime_type text NOT NULL CHECK(mime_type IN ('application/pdf','image/jpeg','image/png')),
  file_size_bytes integer NOT NULL CHECK(file_size_bytes BETWEEN 1 AND 8388608),
  sha256 text NOT NULL CHECK(sha256 ~ '^[a-f0-9]{64}$'),
  created_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  deleted_at timestamptz
);
CREATE INDEX idx_clinical_evidence_request ON request_clinical_evidence(request_id,created_at);

CREATE TABLE request_clinical_reviews (
  request_id uuid PRIMARY KEY REFERENCES care_requests(id),
  status text NOT NULL DEFAULT 'PENDING' CHECK(status IN ('PENDING','APPROVED','REJECTED')),
  required_prescription boolean NOT NULL,
  required_clinical_review boolean NOT NULL,
  reviewed_by uuid REFERENCES users(id),
  decision_note text,
  created_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  reviewed_at timestamptz,
  version integer NOT NULL DEFAULT 1,
  CHECK ((status='PENDING' AND reviewed_by IS NULL AND reviewed_at IS NULL)
    OR (status<>'PENDING' AND reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL
      AND length(btrim(decision_note))>=3))
);
CREATE INDEX idx_clinical_reviews_pending ON request_clinical_reviews(created_at,request_id)
  WHERE status='PENDING';

CREATE TABLE clinical_review_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  request_id uuid NOT NULL REFERENCES care_requests(id),
  actor_user_id uuid NOT NULL REFERENCES users(id),
  previous_status text NOT NULL,
  next_status text NOT NULL,
  note text NOT NULL,
  occurred_at timestamptz NOT NULL DEFAULT statement_timestamp()
);

CREATE TABLE clinical_access_audit (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  request_id uuid NOT NULL REFERENCES care_requests(id),
  evidence_id uuid REFERENCES request_clinical_evidence(id),
  actor_user_id uuid NOT NULL REFERENCES users(id),
  action text NOT NULL CHECK(action IN ('LIST_QUEUE','LIST_EVIDENCE','VIEW_EVIDENCE','UPLOAD_EVIDENCE','DECIDE')),
  occurred_at timestamptz NOT NULL DEFAULT statement_timestamp()
);
