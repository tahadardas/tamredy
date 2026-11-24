CREATE TABLE trusted_contacts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_user_id uuid NOT NULL REFERENCES users(id),
  name varchar(80) NOT NULL CHECK (length(btrim(name)) > 0),
  phone_e164 varchar(16) NOT NULL CHECK (phone_e164 ~ '^\+[1-9][0-9]{7,14}$'),
  relationship varchar(60) NOT NULL,
  priority smallint NOT NULL CHECK (priority BETWEEN 1 AND 3),
  communication text NOT NULL CHECK (communication IN ('CALL','SMS')),
  request_location boolean NOT NULL DEFAULT false,
  consent_state text NOT NULL DEFAULT 'PENDING'
    CHECK (consent_state IN ('PENDING','ACCEPTED','DECLINED','REVOKED')),
  location_allowed boolean NOT NULL DEFAULT false,
  verified_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz,
  CHECK (NOT location_allowed OR (request_location AND consent_state='ACCEPTED')),
  CHECK ((consent_state='ACCEPTED') = (verified_at IS NOT NULL))
);
CREATE UNIQUE INDEX trusted_contact_priority_unique ON trusted_contacts(owner_user_id,priority) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX trusted_contact_phone_unique ON trusted_contacts(owner_user_id,phone_e164) WHERE deleted_at IS NULL;

CREATE TABLE trusted_contact_consents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  contact_id uuid NOT NULL REFERENCES trusted_contacts(id),
  actor_user_id uuid NOT NULL REFERENCES users(id),
  decision text NOT NULL CHECK (decision IN ('ACCEPTED','DECLINED','REVOKED','RESET')),
  allows_location boolean NOT NULL DEFAULT false,
  verification_reference varchar(100),
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (NOT allows_location OR decision='ACCEPTED'),
  CHECK (decision NOT IN ('ACCEPTED','DECLINED') OR verification_reference IS NOT NULL)
);
CREATE INDEX trusted_contact_consent_history ON trusted_contact_consents(contact_id,created_at);
