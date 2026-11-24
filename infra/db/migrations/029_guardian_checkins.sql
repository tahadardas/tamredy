CREATE TABLE safety_policies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE safety_policy_versions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  policy_id uuid NOT NULL REFERENCES safety_policies(id),
  version integer NOT NULL CHECK (version > 0),
  interval_seconds integer NOT NULL CHECK (interval_seconds BETWEEN 60 AND 7200),
  reminder_seconds integer NOT NULL CHECK (reminder_seconds BETWEEN 10 AND 1200),
  grace_seconds integer NOT NULL CHECK (grace_seconds BETWEEN 10 AND 1200),
  extension_seconds integer NOT NULL CHECK (extension_seconds BETWEEN 60 AND 1800),
  effective_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(policy_id,version),
  UNIQUE(policy_id,effective_at)
);
WITH policy AS (INSERT INTO safety_policies(code) VALUES('STANDARD') RETURNING id)
INSERT INTO safety_policy_versions(policy_id,version,interval_seconds,reminder_seconds,grace_seconds,extension_seconds)
SELECT id,1,1200,120,180,300 FROM policy;

ALTER TABLE safety_sessions
  ADD COLUMN policy_version_id uuid REFERENCES safety_policy_versions(id),
  ADD COLUMN next_checkin_at timestamptz;
CREATE INDEX safety_sessions_checkin_due ON safety_sessions(next_checkin_at,id)
  WHERE checked_out_at IS NULL AND next_checkin_at IS NOT NULL;

CREATE TABLE safety_checkins (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id uuid NOT NULL REFERENCES safety_sessions(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  remind_at timestamptz NOT NULL,
  deadline_at timestamptz NOT NULL CHECK (deadline_at > remind_at),
  reminded_at timestamptz,
  snoozed_at timestamptz,
  state text NOT NULL DEFAULT 'PENDING' CHECK (state IN ('PENDING','ANSWERED','MISSED','CANCELLED')),
  UNIQUE(id,session_id)
);
CREATE UNIQUE INDEX safety_checkins_one_pending ON safety_checkins(session_id) WHERE state='PENDING';
CREATE INDEX safety_checkins_deadline ON safety_checkins(deadline_at) WHERE state='PENDING';

CREATE TABLE safety_checkin_responses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id uuid NOT NULL,
  checkin_id uuid NOT NULL,
  client_response_id uuid NOT NULL,
  response text NOT NULL CHECK (response IN ('OK','MORE_TIME','HELP','SAFE_EXIT')),
  responded_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY(checkin_id,session_id) REFERENCES safety_checkins(id,session_id),
  UNIQUE(session_id,client_response_id)
);

CREATE TABLE safety_alerts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id uuid NOT NULL,
  checkin_id uuid NOT NULL,
  kind text NOT NULL CHECK (kind IN ('CHECKIN_MISSED','CHECKIN_HELP','SAFE_EXIT_REQUESTED')),
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY(checkin_id,session_id) REFERENCES safety_checkins(id,session_id),
  UNIQUE(checkin_id,kind)
);
