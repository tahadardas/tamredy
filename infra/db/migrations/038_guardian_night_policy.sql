CREATE TABLE guardian_night_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  governorate_id uuid REFERENCES governorates(id),
  area_id uuid REFERENCES areas(id),
  service_id uuid REFERENCES services(id),
  mode text NOT NULL CHECK (mode IN ('ALLOW','RESTRICT','REQUIRE_COVERAGE','REQUIRE_OPT_IN_AND_COVERAGE')),
  starts_at time NOT NULL,
  ends_at time NOT NULL,
  created_by uuid NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CHECK (starts_at<>ends_at),
  CHECK (area_id IS NULL OR governorate_id IS NOT NULL)
);
CREATE INDEX guardian_night_rule_scope ON guardian_night_rules(governorate_id,area_id,service_id,created_at DESC);

CREATE TABLE nurse_night_preferences (
  nurse_id uuid PRIMARY KEY REFERENCES nurses(id),
  opted_in boolean NOT NULL DEFAULT false,
  recorded_at timestamptz NOT NULL DEFAULT now()
);

CREATE FUNCTION guardian_night_denial(target_nurse uuid,target_service uuid,at_time timestamptz)
RETURNS text LANGUAGE sql STABLE AS $$
  WITH local_clock AS (SELECT (at_time AT TIME ZONE 'Asia/Damascus')::time AS t),
  scope AS (SELECT governorate_id,area_id FROM nurses WHERE id=target_nurse),
  latest AS (
    SELECT DISTINCT ON (r.governorate_id,r.area_id,r.service_id) r.*
    FROM guardian_night_rules r CROSS JOIN scope s
    WHERE (r.governorate_id IS NULL OR r.governorate_id=s.governorate_id)
      AND (r.area_id IS NULL OR r.area_id=s.area_id)
      AND (r.service_id IS NULL OR r.service_id=target_service)
    ORDER BY r.governorate_id,r.area_id,r.service_id,r.created_at DESC,r.id DESC
  ), rule AS (
    SELECT r.* FROM latest r CROSS JOIN local_clock
    WHERE CASE WHEN r.starts_at<r.ends_at THEN t>=r.starts_at AND t<r.ends_at
      ELSE t>=r.starts_at OR t<r.ends_at END
    ORDER BY (r.area_id IS NOT NULL) DESC,(r.governorate_id IS NOT NULL) DESC,
      (r.service_id IS NOT NULL) DESC,r.created_at DESC,r.id DESC LIMIT 1
  )
  SELECT CASE
    WHEN r.mode='ALLOW' THEN NULL
    WHEN r.mode='RESTRICT' THEN 'NIGHT_POLICY_RESTRICTED'
    WHEN r.mode='REQUIRE_OPT_IN_AND_COVERAGE' AND NOT EXISTS (
      SELECT 1 FROM nurse_night_preferences p WHERE p.nurse_id=target_nurse AND p.opted_in
    ) THEN 'NIGHT_POLICY_OPT_IN_REQUIRED'
    WHEN NOT EXISTS (
      SELECT 1 FROM safety_staff_shifts sh JOIN safety_staff_shift_presence p ON p.shift_id=sh.id
      JOIN safety_staff_grants g ON g.user_id=p.user_id JOIN users u ON u.id=p.user_id
      WHERE sh.cancelled_at IS NULL AND sh.starts_at<=at_time AND sh.ends_at>at_time
      AND (sh.governorate_id IS NULL OR sh.governorate_id=s.governorate_id)
      AND p.user_id IN (sh.primary_user_id,sh.backup_user_id) AND p.checked_out_at IS NULL
      AND p.heartbeat_at>at_time-interval '90 seconds' AND p.heartbeat_at<=at_time
      AND g.revoked_at IS NULL AND u.status='ACTIVE' AND u.role IN ('ADMIN','CLINICAL_REVIEWER')
    ) THEN 'NIGHT_POLICY_COVERAGE_REQUIRED'
    ELSE NULL END
  FROM rule r CROSS JOIN scope s;
$$;
