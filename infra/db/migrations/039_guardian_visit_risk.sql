CREATE TABLE safety_visit_reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES care_requests(id),
  assessed_by uuid NOT NULL REFERENCES users(id),
  decision text NOT NULL CHECK (decision IN ('CLEAR','HOLD','REQUIRE_COMPANION')),
  basis text NOT NULL CHECK (basis IN ('VERIFIED_INCIDENT','DOCUMENTED_THREAT','INFORMATION_MISMATCH','SOLO_WORK','REASSESSMENT')),
  reference varchar(120) NOT NULL CHECK (length(btrim(reference))>0),
  effective_until timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX safety_visit_review_latest ON safety_visit_reviews(request_id,created_at DESC,id DESC);

CREATE TABLE safety_visit_companions (
  request_id uuid NOT NULL REFERENCES care_requests(id),
  nurse_id uuid NOT NULL REFERENCES nurses(id),
  companion_id uuid NOT NULL REFERENCES nurses(id),
  nominated_by uuid NOT NULL REFERENCES users(id),
  nominated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  confirmed_at timestamptz,
  PRIMARY KEY(request_id,nurse_id),
  CHECK (nurse_id<>companion_id)
);
CREATE INDEX safety_visit_companion_nurse ON safety_visit_companions(companion_id);

CREATE TABLE safety_companion_reservations (
  assignment_id uuid PRIMARY KEY REFERENCES request_assignments(id),
  companion_id uuid NOT NULL REFERENCES nurses(id),
  reserved_at timestamptz NOT NULL DEFAULT now(),
  released_at timestamptz
);
CREATE UNIQUE INDEX safety_companion_reservations_active ON safety_companion_reservations(companion_id) WHERE released_at IS NULL;

CREATE FUNCTION guardian_release_companion() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status='RELEASED' AND OLD.status='ACTIVE' THEN
    UPDATE safety_companion_reservations SET released_at=now()
      WHERE assignment_id=NEW.id AND released_at IS NULL;
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER guardian_release_companion_on_assignment
AFTER UPDATE OF status ON request_assignments FOR EACH ROW EXECUTE FUNCTION guardian_release_companion();

CREATE FUNCTION guardian_dispatch_denial(target_nurse uuid,target_request uuid,at_time timestamptz)
RETURNS text LANGUAGE sql STABLE AS $$
  WITH request AS (SELECT service_id,status FROM care_requests WHERE id=target_request),
  review AS (
    SELECT decision,effective_until FROM safety_visit_reviews WHERE request_id=target_request
    ORDER BY created_at DESC,id DESC LIMIT 1
  )
  SELECT CASE
    WHEN EXISTS (SELECT 1 FROM safety_companion_reservations x WHERE x.companion_id=target_nurse AND x.released_at IS NULL)
      THEN 'VISIT_COMPANION_BUSY'
    WHEN r.status='OFFERING' AND v.effective_until>at_time AND v.decision='HOLD'
      THEN 'VISIT_SAFETY_REVIEW_REQUIRED'
    WHEN r.status='OFFERING' AND v.effective_until>at_time AND v.decision='REQUIRE_COMPANION'
      AND NOT EXISTS (
        SELECT 1 FROM safety_visit_companions vc JOIN nurses n ON n.id=vc.companion_id
        JOIN users u ON u.id=n.user_id WHERE vc.request_id=target_request AND vc.nurse_id=target_nurse
        AND vc.confirmed_at IS NOT NULL AND n.verified AND u.status='ACTIVE'
        AND n.work_status='AVAILABLE' AND n.availability_intent='AVAILABLE'
        AND n.last_heartbeat_at>at_time-interval '120 seconds'
        AND EXISTS (SELECT 1 FROM nurse_credentials k WHERE k.nurse_id=n.id AND k.approved AND k.expires_at>at_time)
        AND NOT EXISTS (SELECT 1 FROM request_assignments a WHERE a.nurse_id=n.id AND a.status='ACTIVE')
        AND NOT EXISTS (
          SELECT 1 FROM safety_companion_reservations x JOIN request_assignments a ON a.id=x.assignment_id
          WHERE x.companion_id=n.id AND x.released_at IS NULL AND a.request_id<>target_request
        )
      ) THEN 'VISIT_COMPANION_REQUIRED'
    ELSE guardian_night_denial(target_nurse,r.service_id,at_time)
  END FROM request r LEFT JOIN review v ON true;
$$;
