-- Tamreedy 3.1 (BUG-011, BUG-012, BUG-014): backfill nurse financial accounts,
-- store immutable commission policy snapshot on assignment, and track reservation release reasons.

INSERT INTO nurse_financial_accounts (nurse_id)
SELECT id FROM nurses
ON CONFLICT (nurse_id) DO NOTHING;

ALTER TABLE request_assignments
  ADD COLUMN IF NOT EXISTS commission_policy_snapshot jsonb;

ALTER TABLE financial_reservations
  ADD COLUMN IF NOT EXISTS resolution_reason text;
