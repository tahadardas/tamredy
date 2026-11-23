-- Opt-in departure reminders. Existing assigned requests receive no invented deadline.
ALTER TABLE request_assignments
  ADD COLUMN departure_due_at timestamptz,
  ADD COLUMN departure_alerted_at timestamptz,
  ADD CONSTRAINT chk_departure_reminder CHECK (
    (departure_due_at IS NULL AND departure_alerted_at IS NULL)
    OR (departure_due_at IS NOT NULL AND departure_due_at >= accepted_at
      AND (departure_alerted_at IS NULL OR departure_alerted_at >= departure_due_at))
  );
CREATE INDEX idx_departure_reminders_due ON request_assignments(departure_due_at,request_id)
  WHERE status='ACTIVE' AND departed_at IS NULL AND departure_alerted_at IS NULL AND departure_due_at IS NOT NULL;
