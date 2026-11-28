-- Preserve legacy positions and record audited, currency-proven reconciliation.
ALTER TABLE nurse_financial_currency_accounts
  ADD COLUMN administratively_restricted boolean NOT NULL DEFAULT false,
  ADD COLUMN restriction_reason text,
  ADD CONSTRAINT chk_financial_restriction_reason CHECK (
    NOT administratively_restricted OR nullif(btrim(restriction_reason),'') IS NOT NULL
  );

CREATE TABLE nurse_financial_admin_operations (
  actor_user_id uuid NOT NULL REFERENCES users(id),
  idempotency_key text NOT NULL CHECK (length(idempotency_key) BETWEEN 1 AND 128),
  payload_digest text NOT NULL CHECK (payload_digest ~ '^[a-f0-9]{64}$'),
  result jsonb,
  created_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  PRIMARY KEY(actor_user_id,idempotency_key)
);

CREATE TABLE nurse_legacy_financial_reconciliations (
  nurse_id uuid PRIMARY KEY REFERENCES nurse_financial_accounts(nurse_id),
  currency_account_id uuid NOT NULL,
  currency_code text NOT NULL,
  legacy_prepaid_balance numeric(18,2) NOT NULL CHECK (legacy_prepaid_balance>=0),
  proof_transaction_id uuid UNIQUE REFERENCES financial_transactions(id),
  evidence_reference text NOT NULL CHECK (length(btrim(evidence_reference)) BETWEEN 4 AND 200),
  reconciled_by uuid NOT NULL REFERENCES users(id),
  reconciled_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  FOREIGN KEY(currency_account_id,nurse_id,currency_code)
    REFERENCES nurse_financial_currency_accounts(id,nurse_id,currency_code),
  CHECK (legacy_prepaid_balance=0 OR proof_transaction_id IS NOT NULL)
);

CREATE TABLE nurse_commission_settlement_allocations (
  reconciliation_id uuid NOT NULL REFERENCES commission_reconciliations(id),
  transaction_id uuid NOT NULL REFERENCES financial_transactions(id),
  amount numeric(18,2) NOT NULL CHECK (amount>0),
  created_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  PRIMARY KEY(reconciliation_id,transaction_id)
);
CREATE INDEX idx_commission_settlement_transaction
  ON nurse_commission_settlement_allocations(transaction_id);

CREATE FUNCTION nurse_uncovered_commission(p_currency_account_id uuid)
RETURNS TABLE(reconciliation_id uuid, outstanding numeric) LANGUAGE sql STABLE AS $$
  SELECT c.id,greatest(0,c.uncovered_commission-coalesce((
    SELECT sum(sa.amount) FROM nurse_commission_settlement_allocations sa
    WHERE sa.reconciliation_id=c.id AND NOT EXISTS (
      SELECT 1 FROM financial_transactions x WHERE x.reversal_of_transaction_id=sa.transaction_id
    )
  ),0))
  FROM commission_reconciliations c
  JOIN financial_reservations r ON r.id=c.reservation_id
  WHERE r.currency_account_id=p_currency_account_id AND c.uncovered_commission>0
  AND NOT EXISTS (
    SELECT 1 FROM financial_transactions t
    JOIN financial_transactions x ON x.reversal_of_transaction_id=t.id
    WHERE t.transaction_type='INVOICE_ISSUED' AND t.reference_type='INVOICE'
      AND t.reference_id=c.invoice_id::text
  )
  ORDER BY c.created_at,c.id
$$;

CREATE FUNCTION recompute_nurse_financial_eligibility(p_nurse_id uuid,p_currency_code text)
RETURNS text[] LANGUAGE plpgsql AS $$
DECLARE a nurse_financial_currency_accounts%ROWTYPE; ledger_position numeric;
  held_prepaid numeric; held_credit numeric; reasons text[] := '{}';
BEGIN
  SELECT * INTO a FROM nurse_financial_currency_accounts
    WHERE nurse_id=p_nurse_id AND currency_code=p_currency_code FOR UPDATE;
  IF NOT FOUND THEN RETURN ARRAY['FINANCIAL_SETUP_REQUIRED']; END IF;
  SELECT greatest(0,coalesce(sum(debit_amount-credit_amount),0)) INTO ledger_position
    FROM financial_ledger_entries WHERE currency=a.currency_code AND account_id IN
    ('CASH_HELD_BY_NURSE:'||a.nurse_id::text,'NURSE_PAYABLE:'||a.nurse_id::text);
  SELECT coalesce(sum(prepaid_amount),0),coalesce(sum(credit_amount),0)
    INTO held_prepaid,held_credit FROM financial_reservations
    WHERE currency_account_id=a.id AND status='HELD';
  IF a.administratively_restricted THEN reasons:=array_append(reasons,'ADMINISTRATIVE_RESTRICTION'); END IF;
  IF held_prepaid>a.prepaid_balance THEN reasons:=array_append(reasons,'PREPAID_RESERVATIONS_EXCEED_BALANCE'); END IF;
  IF (a.credit_limit>0 AND ledger_position+held_credit>a.credit_limit) OR held_credit>a.credit_limit
    THEN reasons:=array_append(reasons,'CREDIT_LIMIT_EXCEEDED'); END IF;
  IF EXISTS (SELECT 1 FROM nurse_uncovered_commission(a.id) x WHERE x.outstanding>0)
    THEN reasons:=array_append(reasons,'UNCOVERED_COMMISSION'); END IF;
  UPDATE nurse_financial_currency_accounts
    SET settlement_required=(cardinality(reasons)>0),updated_at=statement_timestamp(),version=version+1
    WHERE id=a.id AND settlement_required IS DISTINCT FROM (cardinality(reasons)>0);
  IF EXISTS(SELECT 1 FROM nurse_financial_accounts l WHERE l.nurse_id=p_nurse_id AND l.reconciliation_required)
    THEN reasons:=array_append(reasons,'LEGACY_RECONCILIATION_REQUIRED'); END IF;
  RETURN reasons;
END $$;
