ALTER TABLE care_requests DROP CONSTRAINT care_requests_status_check;
ALTER TABLE care_requests ADD CONSTRAINT care_requests_status_check CHECK (status IN
  ('SCHEDULED','OFFERING','ASSIGNED','EN_ROUTE','ARRIVED','IN_SERVICE','COMPLETED','CANCELLED','UNFULFILLED','ESCALATED'));

CREATE TABLE scheduled_visits (
  request_id uuid PRIMARY KEY REFERENCES care_requests(id) ON DELETE CASCADE,
  appointment_at timestamptz NOT NULL,
  release_at timestamptz NOT NULL CHECK (release_at < appointment_at),
  released_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX scheduled_visits_due ON scheduled_visits(release_at,request_id) WHERE released_at IS NULL;

ALTER TABLE request_cancellations DROP CONSTRAINT request_cancellations_status_at_cancellation_check;
ALTER TABLE request_cancellations ADD CONSTRAINT request_cancellations_status_at_cancellation_check
  CHECK (status_at_cancellation IN ('SCHEDULED','OFFERING','ASSIGNED','EN_ROUTE','ARRIVED','UNFULFILLED'));
