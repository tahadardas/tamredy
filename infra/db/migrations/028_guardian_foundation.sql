CREATE TABLE safety_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  assignment_id uuid NOT NULL UNIQUE REFERENCES request_assignments(id),
  started_at timestamptz NOT NULL DEFAULT now(),
  checked_out_at timestamptz CHECK (checked_out_at >= started_at)
);

CREATE TABLE safety_location_points (
  session_id uuid NOT NULL REFERENCES safety_sessions(id),
  sequence_no integer NOT NULL CHECK (sequence_no >= 0),
  location geography(Point,4326) NOT NULL,
  accuracy_m double precision NOT NULL CHECK (accuracy_m BETWEEN 0 AND 10000),
  captured_at timestamptz NOT NULL,
  received_at timestamptz NOT NULL DEFAULT now(),
  payload_hash text NOT NULL CHECK (length(payload_hash) = 64),
  PRIMARY KEY (session_id, sequence_no)
);

CREATE INDEX safety_location_points_latest
  ON safety_location_points(session_id,captured_at DESC,sequence_no DESC);

CREATE TABLE emergency_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_user_id uuid NOT NULL REFERENCES users(id),
  session_id uuid REFERENCES safety_sessions(id),
  client_event_id uuid NOT NULL,
  silent boolean NOT NULL,
  state text NOT NULL DEFAULT 'RECEIVED' CHECK (state IN (
    'RECEIVED','ACKNOWLEDGED','IN_PROGRESS','ESCALATED','WAITING_FOR_CONTACT','RESOLVED','FALSE_ALARM','CLOSED'
  )),
  location_sequence_no integer,
  received_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(reporter_user_id,client_event_id),
  CHECK (location_sequence_no IS NULL OR session_id IS NOT NULL),
  FOREIGN KEY(session_id,location_sequence_no) REFERENCES safety_location_points(session_id,sequence_no)
);
CREATE INDEX emergency_events_open ON emergency_events(received_at,id)
  WHERE state NOT IN ('RESOLVED','FALSE_ALARM','CLOSED');

CREATE TABLE emergency_event_actions (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  event_id uuid NOT NULL REFERENCES emergency_events(id),
  actor_user_id uuid NOT NULL REFERENCES users(id),
  action text NOT NULL,
  occurred_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX emergency_event_actions_event ON emergency_event_actions(event_id,id);
