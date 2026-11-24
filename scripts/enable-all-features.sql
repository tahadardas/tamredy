-- Switches on every marketing feature and automatic fee with starting values (edit them later from the dashboard).
-- Run once on the server after the migrations:
--   docker compose -f infra/docker/docker-compose.prod.yml --env-file infra/docker/.env exec -T db \
--     psql -U tamreedy -d tamreedy < scripts/enable-all-features.sql
-- Tax is left OFF on purpose: it needs the legal rate; enable it from "الرسوم والضرائب" once you know it.

UPDATE marketing_features SET enabled = true, updated_at = now()
 WHERE key IN ('offpeak','loyalty','packs','winback','badge','broadcasts','alarm');

UPDATE pricing_settings SET
  distance_enabled = true,  free_km = 3, per_km = 200, max_distance_fee = 3000,
  night_enabled = true,     night_start = '22:00', night_end = '06:00', night_percent = 25,
  holiday_enabled = true,   holiday_percent = 25, weekend_days = '{5}',
  tips_enabled = true,
  referral_enabled = true,  referral_referred_percent = 15, referral_referrer_percent = 15,
  referral_max_discount = 1000, referral_max_rewards_per_month = 5,
  promo_attempts_per_hour = 10,
  updated_at = now()
WHERE id = 1;

-- Reputation tiers for the commission (lower company cut for top-rated nurses).
INSERT INTO commission_tiers (min_reputation, min_reviews, commission_bps)
SELECT 4.5, 20, 1600 WHERE NOT EXISTS (SELECT 1 FROM commission_tiers WHERE min_reputation = 4.5);
INSERT INTO commission_tiers (min_reputation, min_reviews, commission_bps)
SELECT 4.8, 40, 1200 WHERE NOT EXISTS (SELECT 1 FROM commission_tiers WHERE min_reputation = 4.8);

-- Ensure all ADMIN users have full safety supervisor and export permissions
INSERT INTO safety_staff_grants (user_id, permission, granted_by, granted_at)
SELECT id, 'SAFETY_SUPERVISOR', id, now()
FROM users
WHERE role = 'ADMIN'
ON CONFLICT (user_id) DO UPDATE SET permission = 'SAFETY_SUPERVISOR', revoked_at = NULL;

INSERT INTO safety_evidence_export_grants (user_id, granted_by, granted_at)
SELECT id, id, now()
FROM users
WHERE role = 'ADMIN'
ON CONFLICT (user_id) DO UPDATE SET revoked_at = NULL;
