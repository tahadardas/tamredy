-- Store eligibility thresholds on each opt-in request so edits apply to new searches.
ALTER TABLE care_requests
  ADD COLUMN search_max_heartbeat_seconds integer,
  ADD COLUMN search_max_location_seconds integer,
  ADD COLUMN search_max_accuracy_meters integer,
  ADD CONSTRAINT chk_open_dispatch_eligibility_policy CHECK (
    (search_expires_at IS NULL AND search_max_heartbeat_seconds IS NULL
      AND search_max_location_seconds IS NULL AND search_max_accuracy_meters IS NULL)
    OR (search_expires_at IS NOT NULL
      AND search_max_heartbeat_seconds IS NOT NULL AND search_max_heartbeat_seconds BETWEEN 15 AND 300
      AND search_max_location_seconds IS NOT NULL AND search_max_location_seconds BETWEEN 15 AND 600
      AND search_max_accuracy_meters IS NOT NULL AND search_max_accuracy_meters BETWEEN 10 AND 5000)
  );

-- A wake-up is durable in the existing job row. Only nearby open searches for approved
-- skills are accelerated. Skipped locks are deliberately recovered by periodic reconciliation.
CREATE FUNCTION wake_open_dispatch(target_nurse uuid) RETURNS void LANGUAGE sql AS $$
  WITH due AS (
    SELECT j.request_id
    FROM nurses n
    JOIN nurse_locations nl ON nl.nurse_id = n.id
    JOIN care_requests r ON ST_DWithin(r.location, nl.location, 50000)
    JOIN dispatch_jobs j ON j.request_id = r.id
    WHERE n.id = target_nurse
      AND n.verified AND n.work_status = 'AVAILABLE' AND n.availability_intent = 'AVAILABLE'
      AND r.status = 'OFFERING' AND r.search_expires_at > clock_timestamp()
      AND j.next_run_at > clock_timestamp()
      AND ST_DWithin(r.location, nl.location, r.search_radius_meters)
      AND EXISTS (SELECT 1 FROM nurse_skills k
        WHERE k.nurse_id = n.id AND k.service_id = r.service_id AND k.approved)
      AND NOT EXISTS (SELECT 1 FROM request_offers o WHERE o.request_id = r.id AND o.nurse_id = n.id)
    ORDER BY j.request_id
    FOR UPDATE OF j SKIP LOCKED
  )
  UPDATE dispatch_jobs j SET next_run_at = clock_timestamp()
  FROM due WHERE j.request_id = due.request_id;
$$;

CREATE FUNCTION notify_open_dispatch_eligibility() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_TABLE_NAME = 'nurses' THEN
    PERFORM wake_open_dispatch(NEW.id);
  ELSE
    PERFORM wake_open_dispatch(NEW.nurse_id);
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER nurse_open_dispatch_eligibility
  AFTER UPDATE OF verified, availability_intent, work_status ON nurses
  FOR EACH ROW WHEN (
    NEW.verified AND NEW.work_status = 'AVAILABLE' AND NEW.availability_intent = 'AVAILABLE'
    AND (OLD.verified, OLD.availability_intent, OLD.work_status)
      IS DISTINCT FROM (NEW.verified, NEW.availability_intent, NEW.work_status)
  ) EXECUTE FUNCTION notify_open_dispatch_eligibility();

CREATE TRIGGER nurse_first_dispatch_location
  AFTER INSERT ON nurse_locations FOR EACH ROW EXECUTE FUNCTION notify_open_dispatch_eligibility();
CREATE TRIGGER nurse_changed_dispatch_location
  AFTER UPDATE ON nurse_locations FOR EACH ROW WHEN (
    OLD.location IS DISTINCT FROM NEW.location OR OLD.accuracy_m IS DISTINCT FROM NEW.accuracy_m
    OR NEW.recorded_at - OLD.recorded_at >= interval '15 seconds'
  ) EXECUTE FUNCTION notify_open_dispatch_eligibility();

CREATE TRIGGER nurse_dispatch_skill
  AFTER INSERT OR UPDATE OF approved, service_id ON nurse_skills
  FOR EACH ROW WHEN (NEW.approved) EXECUTE FUNCTION notify_open_dispatch_eligibility();
CREATE TRIGGER nurse_dispatch_credential
  AFTER INSERT OR UPDATE OF approved, expires_at ON nurse_credentials
  FOR EACH ROW WHEN (NEW.approved) EXECUTE FUNCTION notify_open_dispatch_eligibility();
CREATE TRIGGER nurse_dispatch_settlement
  AFTER INSERT ON nurse_settlements FOR EACH ROW EXECUTE FUNCTION notify_open_dispatch_eligibility();
