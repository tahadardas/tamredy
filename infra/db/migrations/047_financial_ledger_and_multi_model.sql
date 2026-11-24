-- Migration 047: Double-Entry Financial Ledger, Multi-Model Accounts, Reservations & Patient Wallets

-- Double-Entry Financial Ledger
CREATE TABLE IF NOT EXISTS financial_ledger_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  transaction_id uuid NOT NULL,
  reference_type text NOT NULL,
  reference_id text,
  account_id text NOT NULL,
  debit_amount numeric(18,2) NOT NULL DEFAULT 0 CHECK (debit_amount >= 0),
  credit_amount numeric(18,2) NOT NULL DEFAULT 0 CHECK (credit_amount >= 0),
  currency text NOT NULL DEFAULT 'SYP_NEW',
  idempotency_key text,
  reversal_of_entry_id uuid REFERENCES financial_ledger_entries(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK ((debit_amount > 0 AND credit_amount = 0) OR (credit_amount > 0 AND debit_amount = 0))
);

CREATE INDEX IF NOT EXISTS idx_ledger_account_time ON financial_ledger_entries(account_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ledger_transaction ON financial_ledger_entries(transaction_id);
CREATE INDEX IF NOT EXISTS idx_ledger_idempotency ON financial_ledger_entries(idempotency_key) WHERE idempotency_key IS NOT NULL;

-- Commission / Credit Reservations
CREATE TABLE IF NOT EXISTS financial_reservations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id text NOT NULL,
  amount numeric(18,2) NOT NULL CHECK (amount > 0),
  reference_id text NOT NULL,
  status text NOT NULL DEFAULT 'HELD' CHECK (status IN ('HELD', 'COMMITTED', 'RELEASED')),
  created_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_reservations_account ON financial_reservations(account_id, status);

-- Nurse multi-model financial accounts
CREATE TABLE IF NOT EXISTS nurse_financial_accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nurse_id uuid NOT NULL UNIQUE REFERENCES nurses(id) ON DELETE CASCADE,
  financial_model text NOT NULL DEFAULT 'RECEIVABLES' CHECK (financial_model IN ('RECEIVABLES', 'PREPAID', 'HYBRID')),
  credit_limit numeric(18,2) NOT NULL DEFAULT 100000 CHECK (credit_limit >= 0),
  prepaid_balance numeric(18,2) NOT NULL DEFAULT 0 CHECK (prepaid_balance >= 0),
  reserved_balance numeric(18,2) NOT NULL DEFAULT 0 CHECK (reserved_balance >= 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Patient multi-compartment wallets
CREATE TABLE IF NOT EXISTS patient_wallets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_user_id uuid NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
  promotional_credit numeric(18,2) NOT NULL DEFAULT 0 CHECK (promotional_credit >= 0),
  refund_credit numeric(18,2) NOT NULL DEFAULT 0 CHECK (refund_credit >= 0),
  cash_balance numeric(18,2) NOT NULL DEFAULT 0 CHECK (cash_balance >= 0),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Periodic reconciliation view: verifies every transaction is balanced (Sum(Debit) == Sum(Credit))
CREATE OR REPLACE VIEW financial_unbalanced_transactions AS
SELECT transaction_id,
       sum(debit_amount) AS total_debit,
       sum(credit_amount) AS total_credit,
       (sum(debit_amount) - sum(credit_amount)) AS difference
FROM financial_ledger_entries
GROUP BY transaction_id
HAVING sum(debit_amount) <> sum(credit_amount);
