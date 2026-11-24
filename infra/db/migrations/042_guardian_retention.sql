CREATE TABLE safety_retention_policies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  point_days integer NOT NULL CHECK (point_days BETWEEN 1 AND 365),
  export_days integer NOT NULL CHECK (export_days BETWEEN 1 AND 365),
  set_by uuid NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE safety_legal_holds (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  case_id uuid NOT NULL REFERENCES safety_cases(id),
  reason varchar(240) NOT NULL CHECK (length(btrim(reason))>0),
  reference varchar(120) NOT NULL CHECK (length(btrim(reference))>0),
  held_by uuid NOT NULL REFERENCES users(id),
  held_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  released_by uuid REFERENCES users(id),
  released_at timestamptz,
  release_reason varchar(240),
  CHECK ((released_at IS NULL AND released_by IS NULL AND release_reason IS NULL) OR
    (released_at IS NOT NULL AND released_by IS NOT NULL AND release_reason IS NOT NULL))
);
CREATE UNIQUE INDEX safety_legal_hold_active ON safety_legal_holds(case_id) WHERE released_at IS NULL;
ALTER TABLE safety_evidence_exports ALTER COLUMN sealed_bundle DROP NOT NULL;
ALTER TABLE safety_evidence_exports ADD COLUMN purged_at timestamptz;
ALTER TABLE safety_evidence_exports ADD CHECK ((sealed_bundle IS NULL)=(purged_at IS NOT NULL));
CREATE INDEX safety_points_retention ON safety_location_points(received_at,session_id,sequence_no);
CREATE INDEX safety_exports_retention ON safety_evidence_exports(created_at,id) WHERE purged_at IS NULL;

CREATE TABLE safety_retention_runs (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  policy_id uuid NOT NULL REFERENCES safety_retention_policies(id),
  point_count integer NOT NULL CHECK (point_count>=0),
  export_count integer NOT NULL CHECK (export_count>=0),
  ran_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
