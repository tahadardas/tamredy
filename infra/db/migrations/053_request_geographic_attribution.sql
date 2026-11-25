-- P0: normalized geographic attribution for marketplace filtering and privacy.
-- Exact coordinates remain on the request; public marketplace reads expose only
-- the administrative area name and approximate distance.

ALTER TABLE care_requests
  ADD COLUMN IF NOT EXISTS area_id uuid REFERENCES areas(id);

CREATE INDEX IF NOT EXISTS idx_care_requests_area_status
  ON care_requests(area_id, status, created_at DESC);

WITH nearest AS (
  SELECT cr.id, candidate.id AS area_id
  FROM care_requests cr
  CROSS JOIN LATERAL (
    SELECT a.id
    FROM areas a
    WHERE a.active AND a.lat IS NOT NULL AND a.lng IS NOT NULL
    ORDER BY cr.location <-> ST_SetSRID(ST_MakePoint(a.lng,a.lat),4326)::geography
    LIMIT 1
  ) candidate
  WHERE cr.area_id IS NULL
)
UPDATE care_requests cr SET area_id=nearest.area_id
FROM nearest WHERE cr.id=nearest.id;
