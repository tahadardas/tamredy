CREATE TABLE worker_heartbeats (
  worker_id text PRIMARY KEY CHECK (length(worker_id) BETWEEN 1 AND 128),
  received_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  started_at timestamptz NOT NULL DEFAULT statement_timestamp()
);
CREATE INDEX idx_worker_heartbeats_received_at ON worker_heartbeats(received_at);
