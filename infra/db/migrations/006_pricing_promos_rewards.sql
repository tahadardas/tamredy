-- Pricing rules per service, bills per request, promo codes, cash receipts per visit, nurse rewards.

-- Time-based pricing: base price covers `included_minutes`; every started `block_minutes` after that adds `block_price`.
ALTER TABLE services
  ADD COLUMN IF NOT EXISTS description_ar text,
  ADD COLUMN IF NOT EXISTS included_minutes integer NOT NULL DEFAULT 30 CHECK (included_minutes > 0),
  ADD COLUMN IF NOT EXISTS block_minutes integer NOT NULL DEFAULT 15 CHECK (block_minutes > 0),
  ADD COLUMN IF NOT EXISTS block_price numeric(18,2) NOT NULL DEFAULT 0 CHECK (block_price >= 0),
  ADD COLUMN IF NOT EXISTS expected_minutes integer NOT NULL DEFAULT 30 CHECK (expected_minutes > 0),
  ADD COLUMN IF NOT EXISTS rounding_step integer NOT NULL DEFAULT 1 CHECK (rounding_step >= 1),
  ADD COLUMN IF NOT EXISTS sort_order integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

CREATE TABLE promo_codes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL,
  description text,
  type text NOT NULL CHECK (type IN ('PERCENT','FIXED')),
  value numeric(18,2) NOT NULL CHECK (value > 0),
  max_discount numeric(18,2) CHECK (max_discount IS NULL OR max_discount > 0),
  min_amount numeric(18,2) NOT NULL DEFAULT 0 CHECK (min_amount >= 0),
  valid_from timestamptz,
  valid_to timestamptz,
  max_redemptions integer CHECK (max_redemptions IS NULL OR max_redemptions > 0),
  per_user_limit integer NOT NULL DEFAULT 1 CHECK (per_user_limit > 0),
  first_order_only boolean NOT NULL DEFAULT false,
  service_ids uuid[],
  active boolean NOT NULL DEFAULT true,
  created_by uuid REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (type <> 'PERCENT' OR value <= 100)
);
CREATE UNIQUE INDEX uq_promo_code_upper ON promo_codes (upper(code));

-- A user can "claim" a code once (e.g. after installing the app); it applies automatically to their next order.
CREATE TABLE promo_claims (
  user_id uuid NOT NULL REFERENCES users(id),
  promo_id uuid NOT NULL REFERENCES promo_codes(id),
  claimed_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, promo_id)
);

-- Pricing snapshot + bill live on the request, so later price edits never change an order in progress.
ALTER TABLE care_requests
  ADD COLUMN IF NOT EXISTS pricing jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS promo_id uuid REFERENCES promo_codes(id),
  ADD COLUMN IF NOT EXISTS promo_snapshot jsonb,
  ADD COLUMN IF NOT EXISTS service_minutes integer,
  ADD COLUMN IF NOT EXISTS gross_amount numeric(18,2),
  ADD COLUMN IF NOT EXISTS discount_amount numeric(18,2),
  ADD COLUMN IF NOT EXISTS amount_due numeric(18,2),
  ADD COLUMN IF NOT EXISTS payment_status text NOT NULL DEFAULT 'NOT_DUE' CHECK (payment_status IN ('NOT_DUE','DUE','PARTIAL','PAID')),
  ADD COLUMN IF NOT EXISTS billed_at timestamptz,
  ADD COLUMN IF NOT EXISTS paid_at timestamptz;
CREATE INDEX idx_requests_promo ON care_requests (promo_id) WHERE promo_id IS NOT NULL;
CREATE INDEX idx_requests_payment ON care_requests (payment_status) WHERE payment_status IN ('DUE','PARTIAL');

-- Several cash entries per visit (partial payments).
ALTER TABLE cash_collections DROP CONSTRAINT IF EXISTS cash_collections_visit_id_key;
CREATE INDEX IF NOT EXISTS idx_cash_visit ON cash_collections (visit_id);

-- Rewards the company grants to top nurses (recorded, paid out of band for now).
CREATE TABLE nurse_rewards (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nurse_id uuid NOT NULL REFERENCES nurses(id),
  period text NOT NULL,
  kind text NOT NULL CHECK (kind IN ('REPUTATION','WORK','REVENUE','OTHER')),
  amount numeric(18,2) NOT NULL CHECK (amount > 0),
  note text,
  created_by uuid NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_rewards_nurse ON nurse_rewards (nurse_id, created_at DESC);
