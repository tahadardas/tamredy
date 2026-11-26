-- Tamreedy 3.1 (BUG-024, BUG-025): preserve requested open marketplace duration
-- during clinical review and support structured rejection/resubmission outcomes.

ALTER TABLE care_requests
  ADD COLUMN IF NOT EXISTS open_duration_minutes integer NOT NULL DEFAULT 120;

ALTER TABLE request_clinical_reviews
  ADD COLUMN IF NOT EXISTS decision_outcome text;
