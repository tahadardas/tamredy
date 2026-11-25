-- P2: security/session/privacy invariants. This migration is additive and does
-- not delete legacy sessions; clients may exchange an unbound refresh token
-- once to create a bound device session.

UPDATE users
SET temporary_password_expires_at=statement_timestamp()+interval '24 hours'
WHERE must_change_password AND temporary_password_expires_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_refresh_tokens_family_active
  ON refresh_tokens(family_id) WHERE revoked_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_device_sessions_user_active
  ON device_sessions(user_id,last_seen_at DESC) WHERE revoked_at IS NULL;

CREATE OR REPLACE FUNCTION prevent_security_audit_mutation()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'SECURITY_AUDIT_IMMUTABLE' USING ERRCODE='55000';
END $$;

CREATE TRIGGER trg_audit_log_immutable
BEFORE UPDATE OR DELETE ON audit_log FOR EACH ROW
EXECUTE FUNCTION prevent_security_audit_mutation();
CREATE TRIGGER trg_health_record_access_audit_immutable
BEFORE UPDATE OR DELETE ON health_record_access_audit FOR EACH ROW
EXECUTE FUNCTION prevent_security_audit_mutation();
CREATE TRIGGER trg_clinical_access_audit_immutable
BEFORE UPDATE OR DELETE ON clinical_access_audit FOR EACH ROW
EXECUTE FUNCTION prevent_security_audit_mutation();
CREATE TRIGGER trg_clinical_review_events_immutable
BEFORE UPDATE OR DELETE ON clinical_review_events FOR EACH ROW
EXECUTE FUNCTION prevent_security_audit_mutation();

CREATE TABLE authorization_policy_versions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version integer NOT NULL UNIQUE,
  policy jsonb NOT NULL CHECK(jsonb_typeof(policy)='object'),
  effective_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  created_at timestamptz NOT NULL DEFAULT statement_timestamp()
);

INSERT INTO authorization_policy_versions(version,policy) VALUES(1,$policy$
{
  "PATIENT":["health_record.read_own","health_record.write_own"],
  "NURSE":["health_record.read_assigned","health_record.write_assigned","safety.respond"],
  "CLINICAL_REVIEWER":["clinical_review.queue","clinical_review.evidence","clinical_review.decide","credential.review"],
  "ADMIN":["platform.admin","financial.admin","safety.respond"]
}
$policy$::jsonb) ON CONFLICT(version) DO NOTHING;

CREATE INDEX IF NOT EXISTS idx_health_record_audit_actor_time
  ON health_record_access_audit(actor_user_id,accessed_at DESC);
CREATE INDEX IF NOT EXISTS idx_clinical_access_audit_actor_time
  ON clinical_access_audit(actor_user_id,occurred_at DESC);
