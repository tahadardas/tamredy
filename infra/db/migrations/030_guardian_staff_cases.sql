CREATE TABLE safety_staff_grants (
  user_id uuid PRIMARY KEY REFERENCES users(id),
  permission text NOT NULL CHECK (permission IN ('SAFETY_OPERATOR','SAFETY_SUPERVISOR')),
  granted_by uuid NOT NULL REFERENCES users(id),
  granted_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz
);

CREATE TABLE safety_cases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  emergency_event_id uuid UNIQUE REFERENCES emergency_events(id),
  alert_id uuid UNIQUE REFERENCES safety_alerts(id),
  assigned_user_id uuid REFERENCES safety_staff_grants(user_id),
  state text NOT NULL DEFAULT 'RECEIVED' CHECK (state IN ('RECEIVED','ACKNOWLEDGED','ESCALATED','RESOLVED')),
  version integer NOT NULL DEFAULT 1 CHECK (version > 0),
  opened_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (num_nonnulls(emergency_event_id,alert_id)=1),
  CHECK (state='RECEIVED' OR assigned_user_id IS NOT NULL)
);
CREATE INDEX safety_cases_queue ON safety_cases(state,opened_at,id);
CREATE INDEX safety_cases_assignee ON safety_cases(assigned_user_id,opened_at,id);

CREATE TABLE safety_case_actions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  case_id uuid NOT NULL REFERENCES safety_cases(id),
  actor_user_id uuid NOT NULL REFERENCES users(id),
  client_action_id uuid NOT NULL,
  action text NOT NULL CHECK (action IN ('ACKNOWLEDGED','ESCALATED','RESOLVED')),
  note varchar(500),
  resulting_version integer NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(case_id,actor_user_id,client_action_id)
);

CREATE FUNCTION guardian_enqueue_case() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_TABLE_NAME='emergency_events' THEN
    INSERT INTO safety_cases(emergency_event_id,opened_at) VALUES(NEW.id,NEW.received_at);
  ELSE
    INSERT INTO safety_cases(alert_id,opened_at) VALUES(NEW.id,NEW.created_at);
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER safety_case_from_sos AFTER INSERT ON emergency_events
  FOR EACH ROW EXECUTE FUNCTION guardian_enqueue_case();
CREATE TRIGGER safety_case_from_alert AFTER INSERT ON safety_alerts
  FOR EACH ROW EXECUTE FUNCTION guardian_enqueue_case();
INSERT INTO safety_cases(emergency_event_id,opened_at)
SELECT id,received_at FROM emergency_events WHERE state='RECEIVED' ON CONFLICT DO NOTHING;
INSERT INTO safety_cases(alert_id,opened_at)
SELECT id,created_at FROM safety_alerts ON CONFLICT DO NOTHING;
