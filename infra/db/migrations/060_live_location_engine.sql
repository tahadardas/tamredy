ALTER TABLE nurse_locations
  ADD COLUMN IF NOT EXISTS captured_at timestamptz,
  ADD COLUMN IF NOT EXISTS received_at timestamptz,
  ADD COLUMN IF NOT EXISTS sequence_number integer,
  ADD COLUMN IF NOT EXISTS session_id uuid REFERENCES device_sessions(id),
  ADD COLUMN IF NOT EXISTS speed_mps numeric(7,3),
  ADD COLUMN IF NOT EXISTS heading_degrees numeric(6,2),
  ADD COLUMN IF NOT EXISTS location_source text;

UPDATE nurse_locations SET
  captured_at=coalesce(captured_at,recorded_at),
  received_at=coalesce(received_at,recorded_at),
  sequence_number=coalesce(sequence_number,0),
  location_source=coalesce(location_source,'GPS')
WHERE captured_at IS NULL OR received_at IS NULL OR sequence_number IS NULL OR location_source IS NULL;

ALTER TABLE nurse_locations
  ALTER COLUMN captured_at SET NOT NULL,
  ALTER COLUMN received_at SET NOT NULL,
  ALTER COLUMN sequence_number SET NOT NULL,
  ALTER COLUMN location_source SET NOT NULL,
  ADD CONSTRAINT chk_nurse_location_sequence CHECK(sequence_number >= 0),
  ADD CONSTRAINT chk_nurse_location_speed CHECK(speed_mps IS NULL OR speed_mps BETWEEN 0 AND 150),
  ADD CONSTRAINT chk_nurse_location_heading CHECK(heading_degrees IS NULL OR heading_degrees BETWEEN 0 AND 360),
  ADD CONSTRAINT chk_nurse_location_source CHECK(location_source IN ('GPS','NETWORK','PASSIVE','LAST_KNOWN'));

CREATE INDEX IF NOT EXISTS idx_nurse_locations_fresh_matching
  ON nurse_locations(captured_at DESC,nurse_id) INCLUDE(accuracy_m,sequence_number);

