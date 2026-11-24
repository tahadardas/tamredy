-- Migration 050: Tamreedy Smart Booking, Open Marketplace, and Intelligent Request Recovery

-- 1. Extend care_requests status check constraint
ALTER TABLE care_requests DROP CONSTRAINT IF EXISTS care_requests_status_check;
ALTER TABLE care_requests ADD CONSTRAINT care_requests_status_check CHECK (status IN (
  'SCHEDULED', 'OFFERING', 'AWAITING_RECOVERY_CHOICE', 'OPEN_FOR_PROPOSALS',
  'ASSIGNED', 'EN_ROUTE', 'ARRIVED', 'IN_SERVICE', 'COMPLETED', 'CANCELLED',
  'UNFULFILLED', 'EXPIRED', 'ESCALATED'
));

-- 2. Add booking mode and marketplace columns to care_requests
ALTER TABLE care_requests
  ADD COLUMN IF NOT EXISTS booking_mode text NOT NULL DEFAULT 'INSTANT' CHECK (booking_mode IN ('INSTANT', 'OPEN', 'SCHEDULED')),
  ADD COLUMN IF NOT EXISTS original_booking_mode text NOT NULL DEFAULT 'INSTANT',
  ADD COLUMN IF NOT EXISTS marketplace_status text NOT NULL DEFAULT 'INITIAL' CHECK (marketplace_status IN ('INITIAL', 'SEARCHING', 'AWAITING_RECOVERY_CHOICE', 'OPEN_FOR_PROPOSALS', 'ASSIGNED', 'EXPIRED', 'CANCELLED')),
  ADD COLUMN IF NOT EXISTS published_at timestamptz,
  ADD COLUMN IF NOT EXISTS open_expires_at timestamptz,
  ADD COLUMN IF NOT EXISTS latest_acceptable_arrival_at timestamptz,
  ADD COLUMN IF NOT EXISTS scheduled_start_at timestamptz,
  ADD COLUMN IF NOT EXISTS scheduled_end_at timestamptz,
  ADD COLUMN IF NOT EXISTS booking_mode_version integer NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS last_mode_change_at timestamptz;

CREATE INDEX IF NOT EXISTS idx_care_requests_marketplace_open
  ON care_requests(status, open_expires_at) WHERE status = 'OPEN_FOR_PROPOSALS';

CREATE INDEX IF NOT EXISTS idx_care_requests_booking_mode
  ON care_requests(booking_mode, status, created_at DESC);

-- 3. Request Booking Transitions Audit Log
CREATE TABLE IF NOT EXISTS request_booking_transitions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES care_requests(id) ON DELETE CASCADE,
  from_mode text NOT NULL,
  to_mode text NOT NULL,
  from_status text NOT NULL,
  to_status text NOT NULL,
  triggered_by_user_id uuid NOT NULL REFERENCES users(id),
  transition_reason text NOT NULL,
  transition_metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_req_transitions_req
  ON request_booking_transitions(request_id, created_at DESC);

-- 4. Marketplace Nurse Readiness Proposals
CREATE TABLE IF NOT EXISTS marketplace_proposals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES care_requests(id) ON DELETE CASCADE,
  nurse_id uuid NOT NULL REFERENCES nurses(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'ACCEPTED', 'DECLINED', 'WITHDRAWN', 'EXPIRED', 'SUPERSEDED', 'INVALIDATED')),
  proposed_arrival_at timestamptz NOT NULL,
  proposed_service_start_at timestamptz,
  estimated_service_minutes integer NOT NULL DEFAULT 30,
  estimated_nurse_earning numeric(18,2) NOT NULL,
  note text,
  pricing_version integer NOT NULL DEFAULT 1,
  request_version integer NOT NULL DEFAULT 1,
  proposal_version integer NOT NULL DEFAULT 1,
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  accepted_at timestamptz,
  withdrawn_at timestamptz,
  invalidated_at timestamptz,
  invalidation_reason text
);

-- Ensure a nurse has at most one active PENDING proposal per request
CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_active_proposal_per_nurse_req
  ON marketplace_proposals(request_id, nurse_id) WHERE status = 'PENDING';

CREATE INDEX IF NOT EXISTS idx_marketplace_proposals_request
  ON marketplace_proposals(request_id, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_marketplace_proposals_nurse
  ON marketplace_proposals(nurse_id, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_marketplace_proposals_expiry
  ON marketplace_proposals(expires_at) WHERE status = 'PENDING';

-- 5. Saved Requests for Nurses (Bookmarks)
CREATE TABLE IF NOT EXISTS marketplace_saved_requests (
  nurse_id uuid NOT NULL REFERENCES nurses(id) ON DELETE CASCADE,
  request_id uuid NOT NULL REFERENCES care_requests(id) ON DELETE CASCADE,
  saved_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (nurse_id, request_id)
);

-- 6. Smart Recovery Notification Deliveries (Cooldown & Throttling)
CREATE TABLE IF NOT EXISTS smart_recovery_deliveries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nurse_id uuid NOT NULL REFERENCES nurses(id) ON DELETE CASCADE,
  request_ids uuid[] NOT NULL,
  trigger_event text NOT NULL,
  delivery_channel text NOT NULL DEFAULT 'PUSH_SILENT',
  delivered_at timestamptz NOT NULL DEFAULT now(),
  cooldown_until timestamptz NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_smart_recovery_nurse_cooldown
  ON smart_recovery_deliveries(nurse_id, cooldown_until DESC);

-- 7. Seed Default Smart Booking & Marketplace Policies in app_settings
INSERT INTO app_settings(key, value)
VALUES('booking_policies', jsonb_build_object(
  'instantEnabled', true,
  'openMarketplaceEnabled', true,
  'scheduledBookingEnabled', true,
  'allowModeConversion', true,
  'instantSearchTimeoutSeconds', 60,
  'openRequestDurationMinutes', 120,
  'proposalDurationMinutes', 5,
  'maxConcurrentProposalsPerNurse', 5,
  'smartRecoveryEnabled', true,
  'recoveryCooldownMinutes', 15,
  'recoveryMaxDaily', 8,
  'recoveryAggregationSeconds', 60
))
ON CONFLICT (key) DO UPDATE
SET value = EXCLUDED.value || app_settings.value;
