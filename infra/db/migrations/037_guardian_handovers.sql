CREATE TABLE safety_shift_handovers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  case_id uuid NOT NULL REFERENCES safety_cases(id),
  requested_by uuid NOT NULL REFERENCES users(id),
  from_user_id uuid NOT NULL REFERENCES safety_staff_grants(user_id),
  to_user_id uuid NOT NULL REFERENCES safety_staff_grants(user_id),
  to_shift_id uuid NOT NULL REFERENCES safety_staff_shifts(id),
  case_version int NOT NULL CHECK (case_version > 0),
  state text NOT NULL DEFAULT 'PENDING' CHECK (state IN ('PENDING','ACCEPTED','EXPIRED')),
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL DEFAULT (now()+interval '10 minutes'),
  accepted_at timestamptz,
  CHECK (from_user_id <> to_user_id),
  CHECK ((state='ACCEPTED')=(accepted_at IS NOT NULL))
);
CREATE UNIQUE INDEX safety_handover_pending_case ON safety_shift_handovers(case_id) WHERE state='PENDING';
CREATE INDEX safety_handover_inbox ON safety_shift_handovers(to_user_id,expires_at) WHERE state='PENDING';
