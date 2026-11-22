-- Phase 1 database. Clinical certification, payments, real SMS, location provider and deployment require further work.
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  phone_e164 text NOT NULL UNIQUE,
  role text NOT NULL CHECK(role IN ('PATIENT','NURSE','ADMIN','CLINICAL_REVIEWER')),
  status text NOT NULL DEFAULT 'ACTIVE' CHECK(status IN ('ACTIVE','SUSPENDED','DELETED')),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE beneficiaries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_user_id uuid NOT NULL REFERENCES users(id),
  display_name text NOT NULL,
  consent_status text NOT NULL CHECK(consent_status IN ('GRANTED','PENDING','REVOKED')),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE services (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE,
  title_ar text NOT NULL,
  active boolean NOT NULL DEFAULT false,
  dispatch_approved boolean NOT NULL DEFAULT false,
  requires_prescription boolean NOT NULL DEFAULT false,
  price_amount numeric(18,2) NOT NULL CHECK(price_amount>=0),
  currency_code text NOT NULL DEFAULT 'SYP_NEW',
  commission_bps integer NOT NULL DEFAULT 2000 CHECK(commission_bps BETWEEN 0 AND 10000)
);
CREATE TABLE nurses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL UNIQUE REFERENCES users(id),
  verified boolean NOT NULL DEFAULT false,
  availability_intent text NOT NULL DEFAULT 'OFFLINE' CHECK(availability_intent IN ('OFFLINE','AVAILABLE','PAUSED')),
  work_status text NOT NULL DEFAULT 'OFFLINE' CHECK(work_status IN ('OFFLINE','AVAILABLE','PAUSED','RESERVED','EN_ROUTE','IN_SERVICE','SUSPENDED')),
  last_heartbeat_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE nurse_credentials (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nurse_id uuid NOT NULL REFERENCES nurses(id),
  license_ref text NOT NULL,
  expires_at timestamptz NOT NULL,
  approved boolean NOT NULL DEFAULT false,
  verified_at timestamptz,
  verified_by uuid REFERENCES users(id)
);
CREATE TABLE nurse_skills (
  nurse_id uuid NOT NULL REFERENCES nurses(id),
  service_id uuid NOT NULL REFERENCES services(id),
  approved boolean NOT NULL DEFAULT false,
  PRIMARY KEY(nurse_id, service_id)
);
CREATE TABLE nurse_locations (
  nurse_id uuid PRIMARY KEY REFERENCES nurses(id),
  location geography(Point,4326) NOT NULL,
  accuracy_m numeric(8,2) NOT NULL CHECK(accuracy_m BETWEEN 0 AND 100000),
  recorded_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_nurse_locations_gist ON nurse_locations USING GIST(location);
CREATE TABLE care_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  requester_user_id uuid NOT NULL REFERENCES users(id),
  beneficiary_id uuid NOT NULL REFERENCES beneficiaries(id),
  service_id uuid NOT NULL REFERENCES services(id),
  location geography(Point,4326) NOT NULL,
  location_source text NOT NULL CHECK(location_source IN ('GPS_CONFIRMED','MANUAL_PIN')),
  address_text text NOT NULL,
  status text NOT NULL DEFAULT 'OFFERING' CHECK(status IN ('OFFERING','ASSIGNED','EN_ROUTE','ARRIVED','IN_SERVICE','COMPLETED','CANCELLED','UNFULFILLED','ESCALATED')),
  version integer NOT NULL DEFAULT 1,
  price_amount numeric(18,2) NOT NULL,
  currency_code text NOT NULL,
  commission_bps integer NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_care_request_status_created ON care_requests(status, created_at DESC);
CREATE TABLE request_create_keys (
  user_id uuid NOT NULL REFERENCES users(id),
  key text NOT NULL,
  request_hash text NOT NULL,
  request_id uuid UNIQUE REFERENCES care_requests(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(user_id,key)
);
CREATE TABLE request_offers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES care_requests(id),
  nurse_id uuid NOT NULL REFERENCES nurses(id),
  wave_no integer NOT NULL CHECK(wave_no BETWEEN 1 AND 3),
  status text NOT NULL DEFAULT 'OPEN' CHECK(status IN ('OPEN','ACCEPTED','DECLINED','CLOSED','EXPIRED')),
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(request_id,nurse_id)
);
CREATE INDEX idx_offers_nurse_status ON request_offers(nurse_id,status,expires_at);
CREATE TABLE request_assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES care_requests(id),
  nurse_id uuid NOT NULL REFERENCES nurses(id),
  status text NOT NULL DEFAULT 'ACTIVE' CHECK(status IN ('ACTIVE','RELEASED')),
  accepted_at timestamptz NOT NULL DEFAULT now(),
  released_at timestamptz,
  reason text
);
CREATE UNIQUE INDEX uq_active_assignment_per_request ON request_assignments(request_id) WHERE status='ACTIVE';
CREATE UNIQUE INDEX uq_active_assignment_per_nurse ON request_assignments(nurse_id) WHERE status='ACTIVE';
CREATE TABLE visits (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  assignment_id uuid NOT NULL UNIQUE REFERENCES request_assignments(id),
  arrived_at timestamptz,
  started_at timestamptz,
  completed_at timestamptz,
  outcome text CHECK(outcome IN ('COMPLETED','NOT_PERFORMED','ESCALATED'))
);
CREATE TABLE dispatch_jobs (
  request_id uuid PRIMARY KEY REFERENCES care_requests(id),
  next_wave integer NOT NULL DEFAULT 1 CHECK(next_wave BETWEEN 1 AND 4),
  next_run_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_dispatch_due ON dispatch_jobs(next_run_at);
CREATE TABLE request_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  request_id uuid NOT NULL REFERENCES care_requests(id),
  actor_user_id uuid REFERENCES users(id),
  event_type text NOT NULL,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  occurred_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_request_events ON request_events(request_id,id);
CREATE TABLE outbox_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  event_type text NOT NULL,
  aggregate_id uuid NOT NULL,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  published_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_outbox_unpublished ON outbox_events(id) WHERE published_at IS NULL;
CREATE TABLE visit_reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  visit_id uuid NOT NULL REFERENCES visits(id),
  reviewer_user_id uuid NOT NULL REFERENCES users(id),
  reviewer_role text NOT NULL CHECK(reviewer_role IN ('PATIENT','NURSE')),
  stars integer CHECK(stars BETWEEN 1 AND 5),
  punctuality boolean,
  professionalism boolean,
  behavior_notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(visit_id,reviewer_role),
  CHECK((reviewer_role='PATIENT' AND stars IS NOT NULL) OR reviewer_role='NURSE')
);
CREATE TABLE incidents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES care_requests(id),
  reported_by uuid NOT NULL REFERENCES users(id),
  severity text NOT NULL CHECK(severity IN ('LOW','MEDIUM','HIGH','CRITICAL')),
  description text NOT NULL,
  status text NOT NULL DEFAULT 'OPEN' CHECK(status IN ('OPEN','IN_REVIEW','RESOLVED')),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE cash_collections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  visit_id uuid NOT NULL UNIQUE REFERENCES visits(id),
  collector_nurse_id uuid NOT NULL REFERENCES nurses(id),
  amount numeric(18,2) NOT NULL CHECK(amount>=0),
  status text NOT NULL DEFAULT 'PENDING_CONFIRMATION' CHECK(status IN ('PENDING_CONFIRMATION','CONFIRMED','DISPUTED')),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE ledger_transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  visit_id uuid REFERENCES visits(id),
  type text NOT NULL,
  currency_code text NOT NULL,
  external_reference text UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE ledger_lines (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  transaction_id uuid NOT NULL REFERENCES ledger_transactions(id),
  account_code text NOT NULL,
  debit numeric(18,2) NOT NULL DEFAULT 0 CHECK(debit>=0),
  credit numeric(18,2) NOT NULL DEFAULT 0 CHECK(credit>=0),
  CHECK((debit>0 AND credit=0) OR (credit>0 AND debit=0))
);
-- Not activated: licensed-provider wallet operations and balances deliberately NOT implemented.
