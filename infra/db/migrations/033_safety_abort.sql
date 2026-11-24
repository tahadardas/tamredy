CREATE TABLE safety_aborts (
  assignment_id uuid PRIMARY KEY REFERENCES request_assignments(id),
  incident_id uuid NOT NULL UNIQUE REFERENCES incidents(id),
  emergency_event_id uuid NOT NULL REFERENCES emergency_events(id),
  actor_user_id uuid NOT NULL REFERENCES users(id),
  reason text CHECK (reason IN (
    'THREAT','HARASSMENT','ASSAULT','UNSAFE_BEHAVIOR','VISIT_MISMATCH','UNSAFE_LOCATION','UNSAFE_PERSONS','OTHER'
  )),
  created_at timestamptz NOT NULL DEFAULT now()
);
