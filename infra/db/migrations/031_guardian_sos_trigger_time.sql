ALTER TABLE emergency_events ADD COLUMN triggered_at timestamptz;
ALTER TABLE emergency_events ADD CONSTRAINT emergency_events_trigger_clock
  CHECK (triggered_at IS NULL OR triggered_at <= received_at + interval '1 minute');
