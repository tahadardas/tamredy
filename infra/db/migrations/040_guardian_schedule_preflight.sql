CREATE FUNCTION guardian_schedule_denial(target_service uuid,at_time timestamptz)
RETURNS text LANGUAGE sql STABLE AS $$
  WITH local_clock AS (SELECT (at_time AT TIME ZONE 'Asia/Damascus')::time AS t),
  latest AS (
    SELECT DISTINCT ON (service_id) * FROM guardian_night_rules
    WHERE governorate_id IS NULL AND area_id IS NULL
      AND (service_id IS NULL OR service_id=target_service)
    ORDER BY service_id,created_at DESC,id DESC
  ), matched AS (
    SELECT r.mode FROM latest r CROSS JOIN local_clock
    WHERE CASE WHEN r.starts_at<r.ends_at THEN t>=r.starts_at AND t<r.ends_at
      ELSE t>=r.starts_at OR t<r.ends_at END
    ORDER BY (service_id IS NOT NULL) DESC LIMIT 1
  )
  SELECT CASE
    WHEN EXISTS(SELECT 1 FROM matched WHERE mode='RESTRICT') THEN 'SCHEDULE_NIGHT_RESTRICTED'
    WHEN EXISTS(SELECT 1 FROM matched WHERE mode IN ('REQUIRE_COVERAGE','REQUIRE_OPT_IN_AND_COVERAGE'))
      AND NOT EXISTS (
        SELECT 1 FROM safety_staff_shifts s
        JOIN safety_staff_grants g ON g.user_id IN (s.primary_user_id,s.backup_user_id)
        JOIN users u ON u.id=g.user_id
        WHERE s.cancelled_at IS NULL AND s.starts_at<=at_time AND s.ends_at>at_time
          AND g.revoked_at IS NULL AND u.status='ACTIVE' AND u.role IN ('ADMIN','CLINICAL_REVIEWER')
      ) THEN 'SCHEDULE_SAFETY_COVERAGE_NOT_PLANNED'
    ELSE NULL END;
$$;
