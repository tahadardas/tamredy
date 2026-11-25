CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE OR REPLACE FUNCTION tamreedy_ar_normalize(value text)
RETURNS text
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
RETURNS NULL ON NULL INPUT
AS $$
  SELECT trim(regexp_replace(
    regexp_replace(
      translate(lower(value), 'أإآٱىؤئ', 'اااايوي'),
      '[ًٌٍَُِّْـٰ]', '', 'g'
    ),
    '\s+', ' ', 'g'
  ));
$$;

CREATE INDEX IF NOT EXISTS idx_users_display_name_ar_trgm
  ON users USING gin(tamreedy_ar_normalize(display_name) gin_trgm_ops)
  WHERE status<>'DELETED';
CREATE INDEX IF NOT EXISTS idx_services_title_ar_trgm
  ON services USING gin(tamreedy_ar_normalize(title_ar) gin_trgm_ops)
  WHERE active;
CREATE INDEX IF NOT EXISTS idx_services_description_ar_trgm
  ON services USING gin(tamreedy_ar_normalize(description_ar) gin_trgm_ops)
  WHERE active;
CREATE INDEX IF NOT EXISTS idx_areas_name_ar_trgm
  ON areas USING gin(tamreedy_ar_normalize(name_ar) gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_beneficiaries_name_ar_trgm
  ON beneficiaries USING gin(tamreedy_ar_normalize(display_name) gin_trgm_ops);
