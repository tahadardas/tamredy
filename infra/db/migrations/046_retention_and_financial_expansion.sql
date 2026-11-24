-- Migration 046: Retention, Favorite Nurses, Dedicated Requests, Packages & Multi-Factor Reviews

-- Multi-factor review ratings
ALTER TABLE visit_reviews
  ADD COLUMN IF NOT EXISTS punctuality_stars integer CHECK (punctuality_stars IS NULL OR punctuality_stars BETWEEN 1 AND 5),
  ADD COLUMN IF NOT EXISTS conduct_stars integer CHECK (conduct_stars IS NULL OR conduct_stars BETWEEN 1 AND 5),
  ADD COLUMN IF NOT EXISTS clinical_stars integer CHECK (clinical_stars IS NULL OR clinical_stars BETWEEN 1 AND 5),
  ADD COLUMN IF NOT EXISTS hygiene_stars integer CHECK (hygiene_stars IS NULL OR hygiene_stars BETWEEN 1 AND 5),
  ADD COLUMN IF NOT EXISTS overall_stars integer CHECK (overall_stars IS NULL OR overall_stars BETWEEN 1 AND 5);

-- Patient favorite nurses
CREATE TABLE IF NOT EXISTS patient_favorite_nurses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  nurse_id uuid NOT NULL REFERENCES nurses(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (patient_user_id, nurse_id)
);

CREATE INDEX IF NOT EXISTS idx_patient_favorite_nurses_patient
  ON patient_favorite_nurses(patient_user_id);

-- Dedicated nurse request support
ALTER TABLE care_requests
  ADD COLUMN IF NOT EXISTS preferred_nurse_id uuid REFERENCES nurses(id),
  ADD COLUMN IF NOT EXISTS dispatch_mode text NOT NULL DEFAULT 'OPEN' CHECK (dispatch_mode IN ('OPEN', 'DIRECT_NURSE')),
  ADD COLUMN IF NOT EXISTS direct_nurse_timeout_at timestamptz;

-- Care Packages & Service Bundles
CREATE TABLE IF NOT EXISTS care_packages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE,
  title_ar text NOT NULL,
  title_en text NOT NULL,
  description_ar text,
  visit_count integer NOT NULL CHECK (visit_count > 0),
  price_amount numeric(18,2) NOT NULL CHECK (price_amount > 0),
  currency_code text NOT NULL DEFAULT 'SYP_NEW',
  validity_days integer NOT NULL DEFAULT 60 CHECK (validity_days > 0),
  eligible_service_ids uuid[],
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS user_package_grants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  package_id uuid NOT NULL REFERENCES care_packages(id),
  total_visits integer NOT NULL,
  remaining_visits integer NOT NULL CHECK (remaining_visits >= 0),
  purchased_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  status text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'EXHAUSTED', 'EXPIRED', 'CANCELLED')),
  payment_reference text
);

CREATE TABLE IF NOT EXISTS package_redemptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  grant_id uuid NOT NULL REFERENCES user_package_grants(id) ON DELETE CASCADE,
  request_id uuid NOT NULL UNIQUE REFERENCES care_requests(id) ON DELETE CASCADE,
  redeemed_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_user_package_grants_user_status
  ON user_package_grants(user_id, status);

-- Seed Care Packages
INSERT INTO care_packages(code, title_ar, title_en, description_ar, visit_count, price_amount, currency_code, validity_days)
VALUES
  ('PKG_5_VISITS', 'باقة الرعاية 5 زيارات', '5-Visit Care Package', 'باقة تشمل 5 زيارات تمريضية منزلية بخصم مميز وصالحة لمدة 60 يوماً', 5, 110000, 'SYP_NEW', 60),
  ('PKG_10_VISITS', 'باقة الرعاية الشاملة 10 زيارات', '10-Visit Comprehensive Package', 'باقة اقتصادية تشمل 10 زيارات للرعاية المنتظمة أو بعد العمليات صالحة لمدة 90 يوماً', 10, 200000, 'SYP_NEW', 90),
  ('PKG_CHRONIC_MONTHLY', 'باقة رعاية الحالات المزمنة الشهرية', 'Monthly Chronic Care Package', '4 زيارات دورية شهرياً لمتابعة السكري والضغط والعلامات الحيوية', 4, 90000, 'SYP_NEW', 30)
ON CONFLICT (code) DO NOTHING;
