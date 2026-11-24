-- Migration 044: Smart Scheduling Overlap Prevention, Nurse Calendar, and Recurring Care Plans

-- Nurse calendar blocks (explicit off-duty / busy periods)
CREATE TABLE IF NOT EXISTS nurse_calendar_blocks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nurse_id uuid NOT NULL REFERENCES nurses(id) ON DELETE CASCADE,
  start_time timestamptz NOT NULL,
  end_time timestamptz NOT NULL,
  reason text NOT NULL DEFAULT 'OFF_DUTY',
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (end_time > start_time)
);

CREATE INDEX IF NOT EXISTS idx_nurse_calendar_blocks_range
  ON nurse_calendar_blocks(nurse_id, start_time, end_time);

-- Recurring Care Plans
CREATE TABLE IF NOT EXISTS care_plans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  beneficiary_id uuid NOT NULL REFERENCES beneficiaries(id) ON DELETE CASCADE,
  primary_service_id uuid NOT NULL REFERENCES services(id),
  frequency_type text NOT NULL CHECK (frequency_type IN ('DAILY', 'EVERY_OTHER_DAY', 'THREE_TIMES_A_WEEK', 'SPECIFIC_DAYS')),
  frequency_meta jsonb NOT NULL DEFAULT '{}'::jsonb, -- e.g. {"weekdays": [1, 3, 5]} (1=Monday .. 7=Sunday)
  preferred_time_of_day time NOT NULL, -- e.g. '10:00:00'
  total_visits_planned integer,
  visits_generated integer NOT NULL DEFAULT 0,
  start_date date NOT NULL,
  end_date date,
  status text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'PAUSED', 'COMPLETED', 'CANCELLED')),
  notes text,
  address_text text NOT NULL,
  location geography(Point, 4326) NOT NULL,
  location_source text NOT NULL DEFAULT 'GPS_CONFIRMED',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (end_date IS NULL OR end_date >= start_date)
);

-- Care Plan Occurrences (Rolling Generation Horizon)
CREATE TABLE IF NOT EXISTS care_plan_occurrences (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  care_plan_id uuid NOT NULL REFERENCES care_plans(id) ON DELETE CASCADE,
  occurrence_number integer NOT NULL,
  scheduled_for timestamptz NOT NULL,
  request_id uuid REFERENCES care_requests(id) ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'GENERATED', 'COMPLETED', 'CANCELLED', 'SKIPPED')),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (care_plan_id, occurrence_number)
);

CREATE INDEX IF NOT EXISTS idx_care_plans_patient ON care_plans(patient_user_id, status);
CREATE INDEX IF NOT EXISTS idx_care_plan_occurrences_due ON care_plan_occurrences(scheduled_for, status);
CREATE INDEX IF NOT EXISTS idx_care_plan_occurrences_plan ON care_plan_occurrences(care_plan_id);

-- Helper function to detect nurse schedule overlap
CREATE OR REPLACE FUNCTION nurse_has_schedule_conflict(
  p_nurse_id uuid,
  p_start timestamptz,
  p_end timestamptz,
  p_exclude_request_id uuid DEFAULT NULL
)
RETURNS boolean AS $$
BEGIN
  -- 1. Check calendar unavailable blocks
  IF EXISTS (
    SELECT 1 FROM nurse_calendar_blocks
    WHERE nurse_id = p_nurse_id
      AND tstzrange(start_time, end_time, '[)') && tstzrange(p_start, p_end, '[)')
  ) THEN
    RETURN true;
  END IF;

  -- 2. Check confirmed scheduled visits (with 30m travel buffer)
  IF EXISTS (
    SELECT 1
    FROM request_assignments ra
    JOIN care_requests cr ON cr.id = ra.request_id
    JOIN scheduled_visits sv ON sv.request_id = cr.id
    WHERE ra.nurse_id = p_nurse_id
      AND ra.status = 'ACTIVE'
      AND cr.status IN ('SCHEDULED', 'ASSIGNED', 'EN_ROUTE', 'ARRIVED', 'IN_SERVICE')
      AND (p_exclude_request_id IS NULL OR cr.id <> p_exclude_request_id)
      AND tstzrange(
            sv.appointment_at - interval '30 minutes',
            sv.appointment_at + (coalesce((cr.pricing->>'expectedMinutes')::int, 30) + 30) * interval '1 minute',
            '[)'
          ) && tstzrange(p_start, p_end, '[)')
  ) THEN
    RETURN true;
  END IF;

  RETURN false;
END;
$$ LANGUAGE plpgsql STABLE;
