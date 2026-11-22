-- 1) Practice certificate becomes its own document category (separate folder, separate label).
ALTER TABLE nurse_documents DROP CONSTRAINT IF EXISTS nurse_documents_kind_check;
ALTER TABLE nurse_documents ADD CONSTRAINT nurse_documents_kind_check
  CHECK (kind IN ('LICENSE','PRACTICE_CERT','ID','DEGREE','PHOTO','OTHER'));
ALTER TABLE nurse_credentials ADD COLUMN IF NOT EXISTS doc_kind text NOT NULL DEFAULT 'LICENSE'
  CHECK (doc_kind IN ('LICENSE','PRACTICE_CERT'));

-- 2) Join applications from the nurse app. NO user account exists until staff approve the application.
CREATE TABLE nurse_applications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  phone_e164 text NOT NULL,
  display_name text NOT NULL,
  governorate_id uuid REFERENCES governorates(id),
  area_id uuid REFERENCES areas(id),
  specialty text,
  national_id_enc text,                     -- AES-256-GCM
  doc_kind text NOT NULL CHECK (doc_kind IN ('LICENSE','PRACTICE_CERT')),
  license_ref text NOT NULL,
  expires_at date NOT NULL,
  accepted_terms_at timestamptz NOT NULL,   -- the applicant took legal responsibility for the data and images
  status text NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','INTERVIEW','APPROVED','REJECTED')),
  interview_at timestamptz,
  staff_note text,
  decided_by uuid REFERENCES users(id),
  decided_at timestamptz,
  nurse_id uuid REFERENCES nurses(id),      -- set on approval
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_applications_status ON nurse_applications (status, created_at DESC);
-- one open application per phone
CREATE UNIQUE INDEX uq_applications_open_phone ON nurse_applications (phone_e164) WHERE status IN ('PENDING','INTERVIEW');

CREATE TABLE application_documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id uuid NOT NULL REFERENCES nurse_applications(id),
  kind text NOT NULL CHECK (kind IN ('LICENSE','PRACTICE_CERT','ID')),
  original_name text NOT NULL,
  mime text NOT NULL,
  size_bytes integer NOT NULL CHECK (size_bytes > 0),
  sha256 text NOT NULL,
  storage_key text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_application_docs ON application_documents (application_id);
