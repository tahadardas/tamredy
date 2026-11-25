-- P1: separate future booking reservations from active visit execution.
CREATE EXTENSION IF NOT EXISTS btree_gist;

ALTER TABLE request_assignments DROP CONSTRAINT IF EXISTS request_assignments_status_check;
ALTER TABLE request_assignments ADD CONSTRAINT request_assignments_status_check
  CHECK (status IN ('RESERVED','ACTIVE','RELEASED','CANCELLED')) NOT VALID;
ALTER TABLE request_assignments VALIDATE CONSTRAINT request_assignments_status_check;

ALTER TABLE request_assignments
  ADD COLUMN IF NOT EXISTS planned_start_at timestamptz,
  ADD COLUMN IF NOT EXISTS planned_end_at timestamptz,
  ADD COLUMN IF NOT EXISTS service_duration_minutes integer,
  ADD COLUMN IF NOT EXISTS travel_buffer_before_minutes integer NOT NULL DEFAULT 30,
  ADD COLUMN IF NOT EXISTS travel_buffer_after_minutes integer NOT NULL DEFAULT 30,
  ADD CONSTRAINT chk_assignment_planned_window CHECK (
    (planned_start_at IS NULL AND planned_end_at IS NULL)
    OR (planned_start_at IS NOT NULL AND planned_end_at IS NOT NULL
      AND planned_end_at > planned_start_at AND service_duration_minutes > 0
      AND travel_buffer_before_minutes BETWEEN 0 AND 240
      AND travel_buffer_after_minutes BETWEEN 0 AND 240)
  ) NOT VALID;
ALTER TABLE request_assignments VALIDATE CONSTRAINT chk_assignment_planned_window;

DROP INDEX IF EXISTS uq_active_assignment_per_nurse;
DROP INDEX IF EXISTS uq_active_assignment_per_request;
CREATE UNIQUE INDEX uq_executing_assignment_per_nurse
  ON request_assignments(nurse_id) WHERE status='ACTIVE';
CREATE UNIQUE INDEX uq_open_assignment_per_request
  ON request_assignments(request_id) WHERE status IN ('RESERVED','ACTIVE');

ALTER TABLE request_assignments ADD CONSTRAINT ex_nurse_assignment_planned_overlap
  EXCLUDE USING gist (
    nurse_id WITH =,
    tstzrange(
      planned_start_at-travel_buffer_before_minutes*interval '1 minute',
      planned_end_at+travel_buffer_after_minutes*interval '1 minute','[)'
    ) WITH &&
  ) WHERE (status IN ('RESERVED','ACTIVE') AND planned_start_at IS NOT NULL)
  DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE nurse_calendar_blocks ADD CONSTRAINT ex_nurse_calendar_block_overlap
  EXCLUDE USING gist (nurse_id WITH =, tstzrange(start_time,end_time,'[)') WITH &&)
  DEFERRABLE INITIALLY IMMEDIATE;

CREATE OR REPLACE FUNCTION nurse_has_schedule_conflict(
  p_nurse_id uuid, p_start timestamptz, p_end timestamptz,
  p_exclude_request_id uuid DEFAULT NULL
)
RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT EXISTS (
    SELECT 1 FROM nurse_calendar_blocks b
    WHERE b.nurse_id=p_nurse_id
      AND tstzrange(b.start_time,b.end_time,'[)') && tstzrange(p_start,p_end,'[)')
  ) OR EXISTS (
    SELECT 1 FROM request_assignments a
    WHERE a.nurse_id=p_nurse_id AND a.status IN ('RESERVED','ACTIVE')
      AND a.planned_start_at IS NOT NULL
      AND (p_exclude_request_id IS NULL OR a.request_id<>p_exclude_request_id)
      AND tstzrange(
        a.planned_start_at-a.travel_buffer_before_minutes*interval '1 minute',
        a.planned_end_at+a.travel_buffer_after_minutes*interval '1 minute','[)'
      ) && tstzrange(p_start,p_end,'[)')
  ) OR EXISTS (
    SELECT 1 FROM request_assignments a JOIN care_requests r ON r.id=a.request_id
    WHERE a.nurse_id=p_nurse_id AND a.status='ACTIVE'
      AND r.status IN ('ASSIGNED','EN_ROUTE','ARRIVED','IN_SERVICE')
      AND (p_exclude_request_id IS NULL OR a.request_id<>p_exclude_request_id)
      AND a.planned_start_at IS NULL
  )
$$;
