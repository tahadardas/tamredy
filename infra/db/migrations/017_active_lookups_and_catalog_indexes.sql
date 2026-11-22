-- Migration 017: High-performance indexes for active session recovery, public catalog & reviews
-- Eliminates table scans for high-frequency mobile lifecycles

CREATE INDEX IF NOT EXISTS idx_requests_active_recovery
  ON care_requests(requester_user_id, status, created_at DESC)
  WHERE status IN ('REQUESTED', 'OFFERING', 'ASSIGNED', 'EN_ROUTE', 'ARRIVED', 'IN_SERVICE');

CREATE INDEX IF NOT EXISTS idx_assignments_active_recovery
  ON request_assignments(nurse_id, status, assigned_at DESC)
  WHERE status = 'ACTIVE';

CREATE INDEX IF NOT EXISTS idx_services_catalog_public
  ON services(sort_order, title_ar)
  WHERE active = true AND dispatch_approved = true;

CREATE INDEX IF NOT EXISTS idx_visit_reviews_visit_role
  ON visit_reviews(visit_id, reviewer_role);
