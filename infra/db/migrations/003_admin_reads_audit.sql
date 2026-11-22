-- Phase 2 groundwork: credential review state + immutable audit log for sensitive admin decisions.
ALTER TABLE nurse_credentials
  ADD COLUMN IF NOT EXISTS review_status text NOT NULL DEFAULT 'PENDING'
    CHECK (review_status IN ('PENDING','APPROVED','REJECTED','NEEDS_INFO')),
  ADD COLUMN IF NOT EXISTS review_reason text,
  ADD COLUMN IF NOT EXISTS submitted_at timestamptz NOT NULL DEFAULT now();
UPDATE nurse_credentials SET review_status='APPROVED' WHERE approved=true AND review_status='PENDING';
CREATE INDEX IF NOT EXISTS idx_credentials_review ON nurse_credentials(review_status, submitted_at);
CREATE TABLE IF NOT EXISTS audit_log (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  actor_user_id uuid NOT NULL REFERENCES users(id),
  action text NOT NULL,
  target_type text NOT NULL,
  target_id uuid NOT NULL,
  detail jsonb NOT NULL DEFAULT '{}'::jsonb,
  occurred_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_audit_target ON audit_log(target_type, target_id, id);
CREATE INDEX IF NOT EXISTS idx_incidents_status ON incidents(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_assignments_nurse_accepted ON request_assignments(nurse_id, accepted_at DESC);
