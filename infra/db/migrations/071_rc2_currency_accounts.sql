-- Legacy balances have no authoritative currency column. Preserve them for
-- administrative reconciliation; never assign money or limits to an inferred currency.
ALTER TABLE nurse_financial_accounts ADD COLUMN reconciliation_required boolean NOT NULL DEFAULT true;
CREATE TABLE nurse_financial_currency_accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nurse_id uuid NOT NULL REFERENCES nurses(id),
  currency_code text NOT NULL CHECK (length(currency_code) BETWEEN 3 AND 16),
  financial_model text NOT NULL CHECK (financial_model IN ('RECEIVABLES','PREPAID','HYBRID')),
  prepaid_balance numeric(18,2) NOT NULL DEFAULT 0 CHECK (prepaid_balance>=0),
  reserved_balance numeric(18,2) NOT NULL DEFAULT 0 CHECK (reserved_balance>=0),
  credit_limit numeric(18,2) NOT NULL DEFAULT 0 CHECK (credit_limit>=0),
  settlement_required boolean NOT NULL DEFAULT false,
  version integer NOT NULL DEFAULT 1 CHECK (version>0),
  created_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  created_by uuid REFERENCES users(id),
  updated_by uuid REFERENCES users(id),
  UNIQUE(nurse_id,currency_code), UNIQUE(id,nurse_id,currency_code)
);
ALTER TABLE financial_reservations ADD COLUMN currency_account_id uuid;
ALTER TABLE financial_reservations ADD CONSTRAINT fk_reservation_currency_account
 FOREIGN KEY(currency_account_id,nurse_id,currency_code) REFERENCES nurse_financial_currency_accounts(id,nurse_id,currency_code);
CREATE INDEX idx_reservations_currency_account ON financial_reservations(currency_account_id) WHERE status='HELD';
CREATE TABLE commission_reconciliations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reservation_id uuid NOT NULL UNIQUE REFERENCES financial_reservations(id),
  invoice_id uuid NOT NULL REFERENCES invoices(id),
  currency_code text NOT NULL,
  estimated_commission numeric(18,2) NOT NULL CHECK(estimated_commission>=0),
  final_commission numeric(18,2) NOT NULL CHECK(final_commission>=0),
  reserved_prepaid numeric(18,2) NOT NULL CHECK(reserved_prepaid>=0),
  reserved_credit numeric(18,2) NOT NULL CHECK(reserved_credit>=0),
  prepaid_applied numeric(18,2) NOT NULL CHECK(prepaid_applied>=0),
  credit_applied numeric(18,2) NOT NULL CHECK(credit_applied>=0),
  released_amount numeric(18,2) NOT NULL CHECK(released_amount>=0),
  uncovered_commission numeric(18,2) NOT NULL CHECK(uncovered_commission>=0),
  created_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  CHECK(prepaid_applied+credit_applied+uncovered_commission=final_commission)
);
