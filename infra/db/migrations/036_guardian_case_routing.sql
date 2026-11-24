ALTER TABLE safety_cases
  ADD COLUMN assigned_shift_id uuid REFERENCES safety_staff_shifts(id),
  ADD COLUMN routing_stage text NOT NULL DEFAULT 'QUEUED'
    CHECK (routing_stage IN ('QUEUED','PRIMARY','BACKUP','SUPERVISOR','UNCOVERED')),
  ADD COLUMN next_route_at timestamptz NOT NULL DEFAULT now();
CREATE INDEX safety_cases_route_due ON safety_cases(next_route_at,id) WHERE state='RECEIVED';

CREATE TABLE safety_case_routes (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  case_id uuid NOT NULL REFERENCES safety_cases(id),
  from_user_id uuid REFERENCES safety_staff_grants(user_id),
  to_user_id uuid REFERENCES safety_staff_grants(user_id),
  shift_id uuid REFERENCES safety_staff_shifts(id),
  route_stage text NOT NULL CHECK (route_stage IN ('PRIMARY','BACKUP','SUPERVISOR','UNCOVERED')),
  routed_at timestamptz NOT NULL DEFAULT now(),
  acknowledge_by timestamptz NOT NULL
);
CREATE INDEX safety_case_routes_history ON safety_case_routes(case_id,id);
