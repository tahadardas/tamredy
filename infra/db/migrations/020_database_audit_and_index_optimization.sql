-- Migration 020: Comprehensive Database Audit, Deduplication & Foreign Key Index Optimization
-- Aligns schema and indexing with international relational database engineering standards (ISO/IEC 9075, ANSI SQL).
-- 1. Eliminates write amplification and cache bloat by dropping duplicate / prefix-redundant indexes.
-- 2. Indexes unindexed foreign keys to prevent table-level share locks during concurrent updates/deletions.
-- 3. Adds spatial indexing for care requests geo-queries.

-- ============================================================================
-- Section 1: Drop Exact Duplicate and Prefix-Redundant Indexes
-- ============================================================================

-- Table: dispatch_jobs
-- idx_dispatch_jobs_run is an exact duplicate of idx_dispatch_due(next_run_at)
DROP INDEX IF EXISTS idx_dispatch_jobs_run;

-- Table: visit_reviews
-- idx_visit_reviews_visit_role is an exact duplicate of the UNIQUE constraint visit_reviews_visit_id_reviewer_role_key(visit_id, reviewer_role)
DROP INDEX IF EXISTS idx_visit_reviews_visit_role;

-- Table: refresh_tokens
-- idx_refresh_tokens_hash is an exact duplicate of the UNIQUE constraint refresh_tokens_token_hash_key(token_hash)
DROP INDEX IF EXISTS idx_refresh_tokens_hash;

-- Table: device_sessions
-- idx_device_sessions_user(user_id) is completely covered by the unique constraint uq_user_device(user_id, device_id)
DROP INDEX IF EXISTS idx_device_sessions_user;

-- Table: incidents
-- idx_incidents_status(status, created_at) is completely covered by idx_incidents_status_created(status, created_at, id)
DROP INDEX IF EXISTS idx_incidents_status;

-- Table: request_assignments
-- idx_assignments_nurse_accepted(nurse_id, accepted_at) is completely covered by idx_assignments_nurse_history(nurse_id, accepted_at, id)
DROP INDEX IF EXISTS idx_assignments_nurse_accepted;

-- Table: users
-- idx_users_created(created_at) is completely covered by idx_users_created_id(created_at, id)
DROP INDEX IF EXISTS idx_users_created;


-- ============================================================================
-- Section 2: Index High-Priority Foreign Keys (Concurrency & Join Performance)
-- ============================================================================

-- promo_claims: enables efficient reverse lookups by promo_id (PK is user_id, promo_id)
CREATE INDEX IF NOT EXISTS idx_promo_claims_promo 
  ON promo_claims(promo_id);

-- nurse_documents: unconditional foreign key index (replaces partial-only index for referential checks)
CREATE INDEX IF NOT EXISTS idx_nurse_documents_nurse 
  ON nurse_documents(nurse_id);

-- nurses: foreign key index on area_id (currently only second column in idx_nurses_region)
CREATE INDEX IF NOT EXISTS idx_nurses_area 
  ON nurses(area_id);

-- nurse_applications: area, governorate, and nurse foreign key lookups
CREATE INDEX IF NOT EXISTS idx_nurse_applications_area 
  ON nurse_applications(area_id);

CREATE INDEX IF NOT EXISTS idx_nurse_applications_governorate 
  ON nurse_applications(governorate_id);

CREATE INDEX IF NOT EXISTS idx_nurse_applications_nurse 
  ON nurse_applications(nurse_id);

CREATE INDEX IF NOT EXISTS idx_nurse_applications_decided_by 
  ON nurse_applications(decided_by) WHERE decided_by IS NOT NULL;

-- nurse_documents: document uploader lookup
CREATE INDEX IF NOT EXISTS idx_nurse_documents_uploaded_by 
  ON nurse_documents(uploaded_by);

-- nurse_credentials: link to physical stored document
CREATE INDEX IF NOT EXISTS idx_nurse_credentials_document 
  ON nurse_credentials(document_id);

-- audit_log: admin audit queries filtered by administrator
CREATE INDEX IF NOT EXISTS idx_audit_log_actor 
  ON audit_log(actor_user_id, occurred_at DESC);

-- Financial, marketing, and management audit trails
CREATE INDEX IF NOT EXISTS idx_broadcasts_creator 
  ON broadcasts(created_by, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_nurse_settlements_creator 
  ON nurse_settlements(created_by, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_nurse_rewards_creator 
  ON nurse_rewards(created_by, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_pack_grants_creator 
  ON pack_grants(created_by, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_promo_codes_creator 
  ON promo_codes(created_by);

CREATE INDEX IF NOT EXISTS idx_promo_codes_only_user 
  ON promo_codes(only_user_id) WHERE only_user_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_users_creator 
  ON users(created_by);


-- ============================================================================
-- Section 3: Spatial Indexing for Requests (PostGIS)
-- ============================================================================

-- Spatial index on care_requests location for regional clustering, heatmaps, and geographic analytics
CREATE INDEX IF NOT EXISTS idx_care_requests_location_gist 
  ON care_requests USING GIST(location);
