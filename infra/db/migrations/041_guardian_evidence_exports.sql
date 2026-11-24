CREATE TABLE safety_evidence_export_grants (
  user_id uuid PRIMARY KEY REFERENCES users(id),
  granted_by uuid NOT NULL REFERENCES users(id),
  granted_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz
);

CREATE TABLE safety_evidence_approvals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  case_id uuid NOT NULL REFERENCES safety_cases(id),
  approved_by uuid NOT NULL REFERENCES users(id),
  exporter_id uuid NOT NULL REFERENCES safety_evidence_export_grants(user_id),
  purpose varchar(240) NOT NULL,
  recipient varchar(160) NOT NULL,
  case_reference varchar(120),
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL DEFAULT (now()+interval '24 hours'),
  CHECK (approved_by<>exporter_id),
  CHECK (expires_at>created_at)
);

CREATE TABLE safety_evidence_exports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  approval_id uuid NOT NULL UNIQUE REFERENCES safety_evidence_approvals(id),
  exported_by uuid NOT NULL REFERENCES users(id),
  manifest jsonb NOT NULL,
  sealed_bundle bytea NOT NULL,
  sha256 text NOT NULL CHECK (sha256 ~ '^[0-9a-f]{64}$'),
  created_at timestamptz NOT NULL DEFAULT now()
);
