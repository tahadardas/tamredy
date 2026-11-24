CREATE TABLE emergency_directory (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name varchar(100) NOT NULL,
  category text NOT NULL CHECK (category IN ('POLICE','AMBULANCE','CIVIL_DEFENCE','SAFETY_TEAM','APPROVED_SUPPORT')),
  governorate varchar(80),
  area varchar(80),
  dial_number varchar(16) NOT NULL CHECK (dial_number ~ '^[+]?[0-9]{2,15}$'),
  hours varchar(120),
  official_source varchar(500) NOT NULL CHECK (length(btrim(official_source)) > 0),
  verified_at timestamptz,
  verified_by uuid REFERENCES users(id),
  valid_until timestamptz,
  active boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (area IS NULL OR governorate IS NOT NULL),
  CHECK (NOT active OR (verified_at IS NOT NULL AND verified_by IS NOT NULL AND valid_until IS NOT NULL AND valid_until > verified_at))
);
CREATE INDEX emergency_directory_visible ON emergency_directory(governorate,area,valid_until) WHERE active;
