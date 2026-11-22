-- Nurse administration (number, profile), encrypted staff documents, system settings.

CREATE SEQUENCE IF NOT EXISTS nurse_no_seq START 1001;
ALTER TABLE nurses
  ADD COLUMN IF NOT EXISTS nurse_no integer UNIQUE DEFAULT nextval('nurse_no_seq'),
  ADD COLUMN IF NOT EXISTS area text,
  ADD COLUMN IF NOT EXISTS specialty text,
  ADD COLUMN IF NOT EXISTS national_id_enc text,   -- AES-256-GCM, never returned in clear (only the last 3 digits)
  ADD COLUMN IF NOT EXISTS notes text,
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();

-- Files are stored ENCRYPTED on disk (UPLOADS_DIR); the database keeps only metadata.
CREATE TABLE nurse_documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nurse_id uuid NOT NULL REFERENCES nurses(id),
  kind text NOT NULL CHECK (kind IN ('LICENSE','ID','DEGREE','PHOTO','OTHER')),
  title text,
  original_name text NOT NULL,
  mime text NOT NULL,
  size_bytes integer NOT NULL CHECK (size_bytes > 0),
  sha256 text NOT NULL,
  storage_key text NOT NULL UNIQUE,
  expires_at date,
  uploaded_by uuid NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz
);
CREATE INDEX idx_nurse_docs ON nurse_documents (nurse_id, created_at DESC) WHERE deleted_at IS NULL;
ALTER TABLE nurse_credentials ADD COLUMN IF NOT EXISTS document_id uuid REFERENCES nurse_documents(id);

-- Editable system settings (company, dispatch waves, order pause, security).
CREATE TABLE app_settings (
  key text PRIMARY KEY,
  value jsonb NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid REFERENCES users(id)
);
INSERT INTO app_settings(key, value) VALUES
  ('company',  '{"name":"تمريضي","phone":"","email":"","address":"","currencyLabel":"ل.س"}'),
  ('dispatch', '{"waves":[{"radiusM":3000,"seconds":15,"limit":8},{"radiusM":6000,"seconds":15,"limit":12},{"radiusM":10000,"seconds":20,"limit":20}]}'),
  ('orders',   '{"accepting":true,"pausedMessage":"الخدمة متوقفة مؤقتًا، نعود قريبًا."}'),
  ('security', '{"idleMinutes":20,"passwordMinLength":12}');

CREATE INDEX IF NOT EXISTS idx_audit_time ON audit_log (occurred_at DESC);
