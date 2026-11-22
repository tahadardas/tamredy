-- Automatic fees (distance / night / holiday), optional tax, tips, tiered commission, nurse dues, referrals, promo protection.
-- Every automatic fee is OFF by default: the administrator decides the values and switches each one on.

CREATE TABLE pricing_settings (
  id smallint PRIMARY KEY CHECK (id = 1),
  tz text NOT NULL DEFAULT 'Asia/Damascus',
  -- distance fee: automatic from the distance the nurse travelled to reach the patient
  distance_enabled boolean NOT NULL DEFAULT false,
  free_km numeric(8,2) NOT NULL DEFAULT 3 CHECK (free_km >= 0),
  per_km numeric(18,2) NOT NULL DEFAULT 0 CHECK (per_km >= 0),
  max_distance_fee numeric(18,2) NOT NULL DEFAULT 0 CHECK (max_distance_fee >= 0),
  -- night surcharge (percent of the service value), window may wrap midnight
  night_enabled boolean NOT NULL DEFAULT false,
  night_start text NOT NULL DEFAULT '22:00' CHECK (night_start ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'),
  night_end text NOT NULL DEFAULT '06:00' CHECK (night_end ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'),
  night_percent numeric(6,2) NOT NULL DEFAULT 25 CHECK (night_percent >= 0 AND night_percent <= 300),
  -- holiday surcharge: weekly days off (0=Sunday..6=Saturday) + dates listed in `holidays`
  holiday_enabled boolean NOT NULL DEFAULT false,
  holiday_percent numeric(6,2) NOT NULL DEFAULT 25 CHECK (holiday_percent >= 0 AND holiday_percent <= 300),
  weekend_days smallint[] NOT NULL DEFAULT '{5}',
  stack_surcharges boolean NOT NULL DEFAULT false,
  -- tax: can be switched on/off at any time
  tax_enabled boolean NOT NULL DEFAULT false,
  tax_percent numeric(6,2) NOT NULL DEFAULT 0 CHECK (tax_percent >= 0 AND tax_percent <= 100),
  tax_label text NOT NULL DEFAULT 'ضريبة',
  -- tips (100% to the nurse)
  tips_enabled boolean NOT NULL DEFAULT true,
  -- nurse cash dues: nurses owing more than this cannot receive new requests (0 = no limit)
  nurse_debt_limit numeric(18,2) NOT NULL DEFAULT 0 CHECK (nurse_debt_limit >= 0),
  -- referrals
  referral_enabled boolean NOT NULL DEFAULT false,
  referral_referred_percent numeric(6,2) NOT NULL DEFAULT 15 CHECK (referral_referred_percent > 0 AND referral_referred_percent <= 100),
  referral_referrer_percent numeric(6,2) NOT NULL DEFAULT 15 CHECK (referral_referrer_percent > 0 AND referral_referrer_percent <= 100),
  referral_max_discount numeric(18,2) NOT NULL DEFAULT 1000 CHECK (referral_max_discount > 0),
  referral_max_rewards_per_month integer NOT NULL DEFAULT 5 CHECK (referral_max_rewards_per_month >= 0),
  -- promo-code abuse protection
  promo_attempts_per_hour integer NOT NULL DEFAULT 10 CHECK (promo_attempts_per_hour > 0),
  promo_max_orders_30d integer NOT NULL DEFAULT 0 CHECK (promo_max_orders_30d >= 0), -- 0 = unlimited
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid REFERENCES users(id)
);
INSERT INTO pricing_settings (id) VALUES (1);

CREATE TABLE holidays (
  day date PRIMARY KEY,
  name text NOT NULL,
  active boolean NOT NULL DEFAULT true
);

-- Lower company cut for top-reputation nurses (tiers only ever reduce the service's default commission).
CREATE TABLE commission_tiers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  min_reputation numeric(4,2) NOT NULL CHECK (min_reputation BETWEEN 1 AND 5),
  min_reviews integer NOT NULL DEFAULT 10 CHECK (min_reviews >= 0),
  commission_bps integer NOT NULL CHECK (commission_bps BETWEEN 0 AND 10000),
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE care_requests
  ADD COLUMN IF NOT EXISTS travel_distance_m integer,
  ADD COLUMN IF NOT EXISTS surcharge_amount numeric(18,2),
  ADD COLUMN IF NOT EXISTS distance_fee numeric(18,2),
  ADD COLUMN IF NOT EXISTS tax_amount numeric(18,2),
  ADD COLUMN IF NOT EXISTS commission_bps_applied integer,
  ADD COLUMN IF NOT EXISTS commission_amount numeric(18,2),
  ADD COLUMN IF NOT EXISTS nurse_earning numeric(18,2),
  ADD COLUMN IF NOT EXISTS owed_to_company numeric(18,2),
  ADD COLUMN IF NOT EXISTS tip_amount numeric(18,2) NOT NULL DEFAULT 0 CHECK (tip_amount >= 0);

-- Settlement of cash dues between nurse and company.
CREATE TABLE nurse_settlements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nurse_id uuid NOT NULL REFERENCES nurses(id),
  direction text NOT NULL CHECK (direction IN ('FROM_NURSE','TO_NURSE')),
  amount numeric(18,2) NOT NULL CHECK (amount > 0),
  note text,
  created_by uuid NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_settlements_nurse ON nurse_settlements (nurse_id, created_at DESC);

-- Referrals: personal code per patient.
ALTER TABLE users ADD COLUMN IF NOT EXISTS referral_code text;
CREATE UNIQUE INDEX uq_users_referral_code ON users (referral_code) WHERE referral_code IS NOT NULL;
CREATE TABLE referrals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  referrer_id uuid NOT NULL REFERENCES users(id),
  referred_id uuid NOT NULL UNIQUE REFERENCES users(id),   -- a user can be referred only once
  rewarded_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (referrer_id <> referred_id)
);
CREATE INDEX idx_referrals_referrer ON referrals (referrer_id);

-- Promo codes generated by the system (referral rewards) belong to one user only.
ALTER TABLE promo_codes
  ADD COLUMN IF NOT EXISTS source text NOT NULL DEFAULT 'ADMIN' CHECK (source IN ('ADMIN','REFERRAL')),
  ADD COLUMN IF NOT EXISTS only_user_id uuid REFERENCES users(id);

-- Failed/successful promo attempts, for rate limiting and abuse review.
CREATE TABLE promo_attempts (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES users(id),
  ok boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_promo_attempts_user ON promo_attempts (user_id, created_at DESC);
