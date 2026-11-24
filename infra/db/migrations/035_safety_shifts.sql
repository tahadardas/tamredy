CREATE TABLE safety_staff_shifts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  governorate_id uuid REFERENCES governorates(id),
  shift_kind text NOT NULL CHECK (shift_kind IN ('DAY','NIGHT')),
  primary_user_id uuid NOT NULL REFERENCES safety_staff_grants(user_id),
  backup_user_id uuid NOT NULL REFERENCES safety_staff_grants(user_id),
  starts_at timestamptz NOT NULL,
  ends_at timestamptz NOT NULL,
  created_by uuid NOT NULL REFERENCES users(id),
  updated_at timestamptz NOT NULL DEFAULT now(),
  cancelled_at timestamptz,
  CHECK (primary_user_id<>backup_user_id),
  CHECK (ends_at>starts_at AND ends_at<=starts_at+interval '24 hours')
);
CREATE INDEX safety_staff_shifts_window ON safety_staff_shifts(starts_at,ends_at) WHERE cancelled_at IS NULL;
CREATE INDEX safety_staff_shifts_region ON safety_staff_shifts(governorate_id,starts_at,ends_at) WHERE cancelled_at IS NULL;

CREATE TABLE safety_staff_shift_presence (
  shift_id uuid NOT NULL REFERENCES safety_staff_shifts(id),
  user_id uuid NOT NULL REFERENCES safety_staff_grants(user_id),
  checked_in_at timestamptz NOT NULL DEFAULT now(),
  heartbeat_at timestamptz NOT NULL DEFAULT now(),
  checked_out_at timestamptz,
  PRIMARY KEY(shift_id,user_id),
  CHECK (heartbeat_at >= checked_in_at)
);
