-- Preserve the patient booking constraint separately from the search deadline.
ALTER TABLE care_requests ADD COLUMN original_latest_acceptable_arrival_at timestamptz;
UPDATE care_requests SET original_latest_acceptable_arrival_at=latest_acceptable_arrival_at
WHERE latest_acceptable_arrival_at IS NOT NULL;
