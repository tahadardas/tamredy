-- Tamreedy 3.1 (BUG-017): store idempotency key on proposal acceptance for deterministic replay.

ALTER TABLE marketplace_proposals
  ADD COLUMN IF NOT EXISTS accepted_idempotency_key text;

CREATE UNIQUE INDEX IF NOT EXISTS uq_proposal_accept_idempotency
  ON marketplace_proposals(request_id, accepted_idempotency_key)
  WHERE accepted_idempotency_key IS NOT NULL;
