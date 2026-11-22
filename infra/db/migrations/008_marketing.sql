-- Marketing: feature switches, automatic discounts (off-peak / loyalty / visit packs), broadcasts, win-back, consent.

CREATE TABLE marketing_features (
  key text PRIMARY KEY,
  enabled boolean NOT NULL DEFAULT false,
  config jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid REFERENCES users(id)
);
-- Every feature starts OFF; the administrator switches each one on and sets the values.
INSERT INTO marketing_features(key, config) VALUES
  ('offpeak',  '{"percent":15,"days":[0,1,2,3,4,5,6],"start":"13:00","end":"16:00","maxDiscount":1000}'),
  ('loyalty',  '{"everyN":5,"percent":20,"maxDiscount":1500}'),
  ('packs',    '{"templates":[{"name":"باقة 4 زيارات","visits":4,"percent":15,"validDays":60},{"name":"باقة 8 زيارات","visits":8,"percent":20,"validDays":90}]}'),
  ('winback',  '{"inactiveDays":30,"percent":15,"validDays":14,"maxDiscount":1000,"maxPerRun":200}'),
  ('badge',    '{"minReputation":4.6,"minReviews":15}'),
  ('broadcasts','{}'),
  ('alarm','{}');
-- The new-request alarm for nearby nurses is ON by default (it is operational, not promotional); it can be switched off.
UPDATE marketing_features SET enabled=true WHERE key='alarm';

-- Visit packs granted by the administrator (e.g. after the patient pays the company in cash).
CREATE TABLE pack_grants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id),
  name text NOT NULL,
  visits integer NOT NULL CHECK (visits > 0),
  percent numeric(6,2) NOT NULL CHECK (percent > 0 AND percent <= 100),
  expires_at timestamptz NOT NULL,
  created_by uuid NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_pack_grants_user ON pack_grants (user_id, expires_at);

-- Marketing consent (patients must opt in) + win-back bookkeeping.
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS marketing_opt_in boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS last_winback_at timestamptz;

-- Win-back codes are system-generated and personal, like referral rewards.
ALTER TABLE promo_codes DROP CONSTRAINT IF EXISTS promo_codes_source_check;
ALTER TABLE promo_codes ADD CONSTRAINT promo_codes_source_check CHECK (source IN ('ADMIN','REFERRAL','WINBACK'));

-- Broadcast messages to all patients / nurses; the worker delivers them.
CREATE TABLE broadcasts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  audience text NOT NULL CHECK (audience IN ('ALL_PATIENTS','ALL_NURSES','AVAILABLE_NURSES')),
  title text NOT NULL CHECK (char_length(title) BETWEEN 2 AND 80),
  body text NOT NULL CHECK (char_length(body) BETWEEN 2 AND 300),
  promo_code text,
  status text NOT NULL DEFAULT 'QUEUED' CHECK (status IN ('QUEUED','SENDING','DONE','FAILED')),
  total integer NOT NULL DEFAULT 0,
  sent integer NOT NULL DEFAULT 0,
  failed integer NOT NULL DEFAULT 0,
  created_by uuid NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  finished_at timestamptz
);
CREATE INDEX idx_broadcasts_status ON broadcasts (status, created_at);
