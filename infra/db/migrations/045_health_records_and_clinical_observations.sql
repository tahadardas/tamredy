-- Migration 045: Health Records, Beneficiary Profiles, Clinical Observations Engine & Audit

-- Extend beneficiaries with health profile details
ALTER TABLE beneficiaries
  ADD COLUMN IF NOT EXISTS relationship text DEFAULT 'SELF',
  ADD COLUMN IF NOT EXISTS date_of_birth date,
  ADD COLUMN IF NOT EXISTS gender text CHECK (gender IS NULL OR gender IN ('MALE', 'FEMALE')),
  ADD COLUMN IF NOT EXISTS known_allergies text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS chronic_conditions text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS current_medications jsonb NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS care_notes text,
  ADD COLUMN IF NOT EXISTS emergency_contact_phone text,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

-- Observation types registry
CREATE TABLE IF NOT EXISTS clinical_observation_types (
  code text PRIMARY KEY,
  name_ar text NOT NULL,
  name_en text NOT NULL,
  unit text NOT NULL,
  min_value numeric(8,2) NOT NULL,
  max_value numeric(8,2) NOT NULL,
  category text NOT NULL DEFAULT 'VITALS'
);

-- Seed clinical observation types
INSERT INTO clinical_observation_types (code, name_ar, name_en, unit, min_value, max_value, category)
VALUES
  ('SYSTOLIC_BP', 'ضغط الدم الانقباضي', 'Systolic Blood Pressure', 'mmHg', 50, 300, 'VITALS'),
  ('DIASTOLIC_BP', 'ضغط الدم الانبساطي', 'Diastolic Blood Pressure', 'mmHg', 30, 200, 'VITALS'),
  ('HEART_RATE', 'معدل النبض / ضربات القلب', 'Heart Rate', 'bpm', 30, 250, 'VITALS'),
  ('TEMPERATURE', 'درجة الحرارة', 'Body Temperature', '°C', 30.0, 45.0, 'VITALS'),
  ('O2_SATURATION', 'نسبة تشبع الأكسجين', 'Oxygen Saturation (SpO2)', '%', 50, 100, 'RESPIRATORY'),
  ('BLOOD_GLUCOSE', 'سكر الدم', 'Blood Glucose', 'mg/dL', 20, 800, 'METABOLIC'),
  ('RESPIRATORY_RATE', 'معدل التنفس', 'Respiratory Rate', 'breaths/min', 5, 60, 'RESPIRATORY'),
  ('BODY_WEIGHT', 'وزن الجسم', 'Body Weight', 'kg', 1, 300, 'GENERAL'),
  ('PAIN_SCORE', 'مستوى الألم', 'Pain Level', 'scale_0_10', 0, 10, 'GENERAL')
ON CONFLICT (code) DO NOTHING;

-- Clinical observations table
CREATE TABLE IF NOT EXISTS clinical_observations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  beneficiary_id uuid NOT NULL REFERENCES beneficiaries(id) ON DELETE CASCADE,
  request_id uuid REFERENCES care_requests(id) ON DELETE SET NULL,
  recorded_by_user_id uuid NOT NULL REFERENCES users(id),
  observation_type text NOT NULL REFERENCES clinical_observation_types(code),
  numeric_value numeric(8,2) NOT NULL,
  unit text NOT NULL,
  source text NOT NULL DEFAULT 'NURSE_VISIT' CHECK (source IN ('NURSE_VISIT', 'PATIENT_SELF_REPORT', 'CLINICAL_VERIFIED')),
  notes text,
  verification_status text NOT NULL DEFAULT 'RECORDED' CHECK (verification_status IN ('RECORDED', 'VERIFIED', 'DISPUTED')),
  measured_at timestamptz NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT now()
);

-- Nurse clinical visit notes & summary
CREATE TABLE IF NOT EXISTS clinical_visit_notes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL UNIQUE REFERENCES care_requests(id) ON DELETE CASCADE,
  beneficiary_id uuid NOT NULL REFERENCES beneficiaries(id),
  nurse_user_id uuid NOT NULL REFERENCES users(id),
  status text NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT', 'SUBMITTED', 'FINALIZED', 'AMENDED')),
  services_performed jsonb NOT NULL DEFAULT '[]'::jsonb,
  clinical_notes text NOT NULL DEFAULT '',
  materials_used jsonb NOT NULL DEFAULT '[]'::jsonb,
  patient_response text,
  followup_recommendations text,
  amendment_reason text,
  version integer NOT NULL DEFAULT 1,
  created_at timestamptz NOT NULL DEFAULT now(),
  submitted_at timestamptz,
  finalized_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Version history for amended notes (24-hour window / addendums)
CREATE TABLE IF NOT EXISTS clinical_note_versions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  note_id uuid NOT NULL REFERENCES clinical_visit_notes(id) ON DELETE CASCADE,
  version_number integer NOT NULL,
  snapshot jsonb NOT NULL,
  amended_by uuid NOT NULL REFERENCES users(id),
  amendment_reason text NOT NULL,
  amended_at timestamptz NOT NULL DEFAULT now()
);

-- HIPAA-style Health Record Access Audit Trail
CREATE TABLE IF NOT EXISTS health_record_access_audit (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_user_id uuid NOT NULL REFERENCES users(id),
  beneficiary_id uuid NOT NULL REFERENCES beneficiaries(id),
  request_id uuid REFERENCES care_requests(id) ON DELETE SET NULL,
  action text NOT NULL CHECK (action IN (
    'VIEW_PROFILE', 'RECORD_OBSERVATIONS', 'VIEW_OBSERVATIONS',
    'VIEW_VISIT_NOTE', 'SUBMIT_VISIT_NOTE', 'AMEND_VISIT_NOTE', 'EXPORT_REPORT'
  )),
  context_reason text,
  accessed_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_observations_beneficiary_time
  ON clinical_observations(beneficiary_id, measured_at DESC);
CREATE INDEX IF NOT EXISTS idx_observations_request
  ON clinical_observations(request_id);
CREATE INDEX IF NOT EXISTS idx_clinical_visit_notes_beneficiary
  ON clinical_visit_notes(beneficiary_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_health_record_audit_beneficiary
  ON health_record_access_audit(beneficiary_id, accessed_at DESC);
