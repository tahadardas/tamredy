-- Tamreedy v0.2: query-driven indexes. PKs and UNIQUE constraints from 001_core.sql
-- already create B-tree indexes: do not duplicate indexes on id, users.phone_e164,
-- nurses.user_id, services.code, unique(request_id,nurse_id), etc.
-- PostgreSQL does NOT automatically index referencing-side foreign keys.

-- Account-scoped history and deterministic keyset pagination (created_at,id).
CREATE INDEX IF NOT EXISTS idx_users_created_id ON users(created_at DESC,id DESC);
CREATE INDEX IF NOT EXISTS idx_requests_owner_created_id
  ON care_requests(requester_user_id,created_at DESC,id DESC);
CREATE INDEX IF NOT EXISTS idx_requests_created_id
  ON care_requests(created_at DESC,id DESC);
CREATE INDEX IF NOT EXISTS idx_requests_status_created_id
  ON care_requests(status,created_at DESC,id DESC);
-- Replaces the earlier prefix-only version to avoid redundant write overhead.
DROP INDEX IF EXISTS idx_care_request_status_created;

-- Referencing-side FK indexes, chosen from concrete joins/deletion paths.
CREATE INDEX IF NOT EXISTS idx_beneficiaries_owner_created
  ON beneficiaries(owner_user_id,created_at DESC,id DESC);
CREATE INDEX IF NOT EXISTS idx_requests_service_created
  ON care_requests(service_id,created_at DESC,id DESC);
CREATE INDEX IF NOT EXISTS idx_requests_beneficiary_created
  ON care_requests(beneficiary_id,created_at DESC,id DESC);
CREATE INDEX IF NOT EXISTS idx_credentials_nurse_expiry
  ON nurse_credentials(nurse_id,approved,expires_at DESC);
CREATE INDEX IF NOT EXISTS idx_credentials_verified_by ON nurse_credentials(verified_by) WHERE verified_by IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_skills_service_approved_nurse
  ON nurse_skills(service_id,nurse_id);
CREATE INDEX IF NOT EXISTS idx_offers_request_status
  ON request_offers(request_id,status);
CREATE INDEX IF NOT EXISTS idx_offers_nurse_open_expiry
  ON request_offers(nurse_id,expires_at ASC,id ASC) WHERE status='OPEN';
CREATE INDEX IF NOT EXISTS idx_assignments_nurse_history
  ON request_assignments(nurse_id,accepted_at DESC,id DESC);
CREATE INDEX IF NOT EXISTS idx_assignments_request_history
  ON request_assignments(request_id,accepted_at DESC,id DESC);
CREATE INDEX IF NOT EXISTS idx_events_actor ON request_events(actor_user_id) WHERE actor_user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_reviews_reviewer_created
  ON visit_reviews(reviewer_user_id,created_at DESC,id DESC);
CREATE INDEX IF NOT EXISTS idx_incidents_request_created
  ON incidents(request_id,created_at DESC,id DESC);
CREATE INDEX IF NOT EXISTS idx_incidents_reporter_created
  ON incidents(reported_by,created_at DESC,id DESC);
CREATE INDEX IF NOT EXISTS idx_incidents_status_created
  ON incidents(status,created_at DESC,id DESC);
CREATE INDEX IF NOT EXISTS idx_cash_collections_nurse_created
  ON cash_collections(collector_nurse_id,created_at DESC,id DESC);
CREATE INDEX IF NOT EXISTS idx_ledger_transactions_visit
  ON ledger_transactions(visit_id) WHERE visit_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_ledger_lines_transaction
  ON ledger_lines(transaction_id);

-- Active nurse discovery; Geospatial index nurse_locations(location) already exists.
CREATE INDEX IF NOT EXISTS idx_nurses_dispatch_ready
  ON nurses(last_heartbeat_at DESC,id)
  WHERE verified=true AND work_status='AVAILABLE' AND availability_intent='AVAILABLE';

-- Dispatcher queue and outbox use existing indexes idx_dispatch_due and idx_outbox_unpublished.
-- Large production tables: schedule CREATE INDEX CONCURRENTLY via a separate, NON-transactional
-- operations migration (and monitor index build); migrate.mjs wraps normal migrations in a transaction.
