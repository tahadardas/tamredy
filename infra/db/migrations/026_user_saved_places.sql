CREATE TABLE user_saved_places (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  label varchar(80) NOT NULL CHECK (length(btrim(label)) > 0),
  place_type text NOT NULL CHECK (place_type IN ('HOME', 'WORK', 'PARENTS', 'CUSTOM')),
  latitude double precision NOT NULL CHECK (latitude BETWEEN -90 AND 90),
  longitude double precision NOT NULL CHECK (longitude BETWEEN -180 AND 180),
  accuracy double precision NOT NULL DEFAULT 0 CHECK (accuracy BETWEEN 0 AND 100000),
  formatted_address varchar(300) NOT NULL CHECK (length(btrim(formatted_address)) > 0),
  floor varchar(40),
  building varchar(80),
  landmark varchar(150),
  notes varchar(300),
  is_default boolean NOT NULL DEFAULT false,
  last_used_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX user_saved_places_one_default
  ON user_saved_places (user_id) WHERE is_default;
CREATE INDEX user_saved_places_owner_recent
  ON user_saved_places (user_id, is_default DESC, last_used_at DESC NULLS LAST, created_at DESC, id);
