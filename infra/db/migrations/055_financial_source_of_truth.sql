-- P1: immutable, idempotent double-entry source of truth.
CREATE TABLE financial_accounts (
  code text PRIMARY KEY,
  name_ar text NOT NULL,
  account_type text NOT NULL CHECK (account_type IN ('ASSET','LIABILITY','EQUITY','REVENUE','EXPENSE')),
  normal_balance text NOT NULL CHECK (normal_balance IN ('DEBIT','CREDIT')),
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO financial_accounts(code,name_ar,account_type,normal_balance) VALUES
  ('CASH_CLEARING','النقد قيد التسوية','ASSET','DEBIT'),
  ('CASH_HELD_BY_NURSE','النقد المحصل لدى الممرض','ASSET','DEBIT'),
  ('PATIENT_RECEIVABLE','ذمم المرضى المدينة','ASSET','DEBIT'),
  ('PATIENT_WALLET_LIABILITY','التزامات محافظ المرضى','LIABILITY','CREDIT'),
  ('PROMOTIONAL_CREDIT_EXPENSE','تكلفة الأرصدة الترويجية','EXPENSE','DEBIT'),
  ('NURSE_RECEIVABLE','ذمم الممرضين المدينة','ASSET','DEBIT'),
  ('NURSE_PAYABLE','ذمم الممرضين الدائنة','LIABILITY','CREDIT'),
  ('PREPAID_LIABILITY','التزامات الأرصدة المدفوعة مسبقاً','LIABILITY','CREDIT'),
  ('COMMISSION_REVENUE','إيراد عمولة المنصة','REVENUE','CREDIT'),
  ('TAX_PAYABLE','الضرائب المستحقة','LIABILITY','CREDIT'),
  ('DISCOUNTS_EXPENSE','الخصومات والتعديلات','EXPENSE','DEBIT'),
  ('REFUNDS_PAYABLE','المبالغ المستردة المستحقة','LIABILITY','CREDIT'),
  ('SETTLEMENT_CLEARING','التسويات قيد المطابقة','ASSET','DEBIT'),
  ('ROUNDING_ADJUSTMENTS','فروقات التقريب','EXPENSE','DEBIT')
ON CONFLICT(code) DO NOTHING;

CREATE TABLE financial_transactions (
  id uuid PRIMARY KEY,
  transaction_type text NOT NULL,
  reference_type text NOT NULL,
  reference_id text,
  currency_code text NOT NULL,
  idempotency_key text NOT NULL UNIQUE,
  payload_digest text NOT NULL CHECK (payload_digest ~ '^[a-f0-9]{64}$'),
  reversal_of_transaction_id uuid REFERENCES financial_transactions(id),
  posted_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  created_by uuid REFERENCES users(id),
  CHECK (reversal_of_transaction_id IS NULL OR reversal_of_transaction_id<>id)
);

INSERT INTO financial_transactions(
  id,transaction_type,reference_type,reference_id,currency_code,idempotency_key,payload_digest,posted_at
)
SELECT e.transaction_id,'LEGACY_IMPORT',min(e.reference_type),min(e.reference_id),min(e.currency),
  'legacy:'||e.transaction_id::text,encode(digest(e.transaction_id::text,'sha256'),'hex'),min(e.created_at)
FROM financial_ledger_entries e
GROUP BY e.transaction_id
ON CONFLICT(id) DO NOTHING;

ALTER TABLE financial_ledger_entries
  ADD CONSTRAINT fk_financial_entries_transaction
  FOREIGN KEY(transaction_id) REFERENCES financial_transactions(id) NOT VALID;
ALTER TABLE financial_ledger_entries VALIDATE CONSTRAINT fk_financial_entries_transaction;

CREATE OR REPLACE FUNCTION assert_financial_transaction_balanced()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_transaction_id uuid; v_currency text; v_debit numeric(18,2); v_credit numeric(18,2);
BEGIN
  v_transaction_id:=coalesce(NEW.transaction_id,OLD.transaction_id);
  FOR v_currency,v_debit,v_credit IN
    SELECT currency,sum(debit_amount),sum(credit_amount)
    FROM financial_ledger_entries WHERE transaction_id=v_transaction_id GROUP BY currency
  LOOP
    IF v_debit<>v_credit THEN
      RAISE EXCEPTION 'FINANCIAL_TRANSACTION_UNBALANCED: %, %, % <> %',
        v_transaction_id,v_currency,v_debit,v_credit USING ERRCODE='23514';
    END IF;
  END LOOP;
  RETURN NULL;
END $$;

CREATE CONSTRAINT TRIGGER trg_financial_transaction_balanced
AFTER INSERT OR UPDATE OR DELETE ON financial_ledger_entries
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
EXECUTE FUNCTION assert_financial_transaction_balanced();

CREATE OR REPLACE FUNCTION prevent_financial_history_mutation()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'FINANCIAL_HISTORY_IMMUTABLE' USING ERRCODE='55000';
END $$;

CREATE TRIGGER trg_financial_entries_immutable
BEFORE UPDATE OR DELETE ON financial_ledger_entries FOR EACH ROW
EXECUTE FUNCTION prevent_financial_history_mutation();
CREATE TRIGGER trg_financial_transactions_immutable
BEFORE UPDATE OR DELETE ON financial_transactions FOR EACH ROW
EXECUTE FUNCTION prevent_financial_history_mutation();

CREATE UNIQUE INDEX uq_financial_reservation_reference
  ON financial_reservations(account_id,reference_id);

ALTER TABLE financial_reservations
  ADD COLUMN nurse_id uuid REFERENCES nurses(id),
  ADD COLUMN prepaid_amount numeric(18,2) NOT NULL DEFAULT 0 CHECK(prepaid_amount>=0),
  ADD COLUMN credit_amount numeric(18,2) NOT NULL DEFAULT 0 CHECK(credit_amount>=0),
  ADD COLUMN currency_code text NOT NULL DEFAULT 'SYP_NEW',
  ADD CONSTRAINT chk_financial_reservation_allocation CHECK(prepaid_amount+credit_amount=amount) NOT VALID;
UPDATE financial_reservations SET credit_amount=amount WHERE prepaid_amount+credit_amount<>amount;
ALTER TABLE financial_reservations VALIDATE CONSTRAINT chk_financial_reservation_allocation;

ALTER TABLE cash_collections DROP CONSTRAINT IF EXISTS cash_collections_visit_id_key;
ALTER TABLE cash_collections
  ADD COLUMN idempotency_key text,
  ADD COLUMN payload_digest text,
  ADD COLUMN received_amount numeric(18,2),
  ADD COLUMN applied_amount numeric(18,2),
  ADD COLUMN change_amount numeric(18,2),
  ADD COLUMN transaction_id uuid REFERENCES financial_transactions(id);

UPDATE cash_collections SET
  idempotency_key='legacy:'||id::text,
  payload_digest=encode(digest(id::text||':'||amount::text,'sha256'),'hex'),
  received_amount=amount,applied_amount=amount,change_amount=0
WHERE idempotency_key IS NULL;

INSERT INTO financial_transactions(
  id,transaction_type,reference_type,reference_id,currency_code,
  idempotency_key,payload_digest,posted_at
)
SELECT cc.id,'CASH_COLLECTION','VISIT',cc.visit_id::text,coalesce(cr.currency_code,'SYP_NEW'),
  'legacy:cash-collection:'||cc.id::text,
  encode(digest(cc.id::text||':'||cc.amount::text,'sha256'),'hex'),cc.created_at
FROM cash_collections cc
JOIN visits v ON v.id=cc.visit_id
JOIN request_assignments a ON a.id=v.assignment_id
JOIN care_requests cr ON cr.id=a.request_id
WHERE cc.amount>0
ON CONFLICT(id) DO NOTHING;

INSERT INTO financial_ledger_entries(transaction_id,reference_type,reference_id,account_id,debit_amount,credit_amount,currency)
SELECT cc.id,'VISIT',cc.visit_id::text,'CASH_HELD_BY_NURSE:'||cc.collector_nurse_id::text,
  cc.amount,0,coalesce(cr.currency_code,'SYP_NEW')
FROM cash_collections cc
JOIN visits v ON v.id=cc.visit_id JOIN request_assignments a ON a.id=v.assignment_id
JOIN care_requests cr ON cr.id=a.request_id
WHERE cc.amount>0 AND NOT EXISTS(SELECT 1 FROM financial_ledger_entries e
  WHERE e.transaction_id=cc.id AND e.account_id='CASH_HELD_BY_NURSE:'||cc.collector_nurse_id::text);
INSERT INTO financial_ledger_entries(transaction_id,reference_type,reference_id,account_id,debit_amount,credit_amount,currency)
SELECT cc.id,'VISIT',cc.visit_id::text,'PATIENT_RECEIVABLE',0,cc.amount,coalesce(cr.currency_code,'SYP_NEW')
FROM cash_collections cc
JOIN visits v ON v.id=cc.visit_id JOIN request_assignments a ON a.id=v.assignment_id
JOIN care_requests cr ON cr.id=a.request_id
WHERE cc.amount>0 AND NOT EXISTS(SELECT 1 FROM financial_ledger_entries e
  WHERE e.transaction_id=cc.id AND e.account_id='PATIENT_RECEIVABLE');

ALTER TABLE cash_collections
  ALTER COLUMN idempotency_key SET NOT NULL,
  ALTER COLUMN payload_digest SET NOT NULL,
  ALTER COLUMN received_amount SET NOT NULL,
  ALTER COLUMN applied_amount SET NOT NULL,
  ALTER COLUMN change_amount SET NOT NULL,
  ADD CONSTRAINT chk_collection_payload_digest CHECK (payload_digest ~ '^[a-f0-9]{64}$'),
  ADD CONSTRAINT chk_collection_amounts CHECK (
    received_amount>0 AND applied_amount>=0 AND change_amount>=0
    AND received_amount=applied_amount+change_amount AND amount=applied_amount
  ),
  ADD CONSTRAINT uq_cash_collection_idempotency UNIQUE(collector_nurse_id,idempotency_key);

UPDATE cash_collections SET transaction_id=id WHERE amount>0 AND transaction_id IS NULL;

CREATE INDEX idx_cash_collections_visit_time ON cash_collections(visit_id,created_at,id);

ALTER TABLE nurse_settlements
  ADD COLUMN transaction_id uuid REFERENCES financial_transactions(id);
CREATE UNIQUE INDEX uq_nurse_settlement_transaction
  ON nurse_settlements(transaction_id) WHERE transaction_id IS NOT NULL;

-- Preserve historical settlements in the authoritative ledger. The deterministic
-- transaction id makes this expansion restart-safe before the migration is recorded.
INSERT INTO financial_transactions(
  id,transaction_type,reference_type,reference_id,currency_code,
  idempotency_key,payload_digest,posted_at,created_by
)
SELECT s.id,
  CASE s.direction WHEN 'FROM_NURSE' THEN 'NURSE_SETTLEMENT_FROM_NURSE' ELSE 'NURSE_SETTLEMENT_TO_NURSE' END,
  'NURSE',s.nurse_id::text,'SYP_NEW','legacy:nurse-settlement:'||s.id::text,
  encode(digest(s.id::text||':'||s.direction||':'||s.amount::text,'sha256'),'hex'),s.created_at,s.created_by
FROM nurse_settlements s
ON CONFLICT(id) DO NOTHING;

INSERT INTO financial_ledger_entries(transaction_id,reference_type,reference_id,account_id,debit_amount,credit_amount,currency)
SELECT s.id,'NURSE',s.nurse_id::text,'CASH_CLEARING',s.amount,0,'SYP_NEW'
FROM nurse_settlements s
WHERE s.direction='FROM_NURSE'
  AND NOT EXISTS(SELECT 1 FROM financial_ledger_entries e WHERE e.transaction_id=s.id AND e.account_id='CASH_CLEARING');
INSERT INTO financial_ledger_entries(transaction_id,reference_type,reference_id,account_id,debit_amount,credit_amount,currency)
SELECT s.id,'NURSE',s.nurse_id::text,'CASH_HELD_BY_NURSE:'||s.nurse_id::text,0,s.amount,'SYP_NEW'
FROM nurse_settlements s
WHERE s.direction='FROM_NURSE'
  AND NOT EXISTS(SELECT 1 FROM financial_ledger_entries e WHERE e.transaction_id=s.id AND e.account_id='CASH_HELD_BY_NURSE:'||s.nurse_id::text);
INSERT INTO financial_ledger_entries(transaction_id,reference_type,reference_id,account_id,debit_amount,credit_amount,currency)
SELECT s.id,'NURSE',s.nurse_id::text,'NURSE_PAYABLE:'||s.nurse_id::text,s.amount,0,'SYP_NEW'
FROM nurse_settlements s
WHERE s.direction='TO_NURSE'
  AND NOT EXISTS(SELECT 1 FROM financial_ledger_entries e WHERE e.transaction_id=s.id AND e.account_id='NURSE_PAYABLE:'||s.nurse_id::text);
INSERT INTO financial_ledger_entries(transaction_id,reference_type,reference_id,account_id,debit_amount,credit_amount,currency)
SELECT s.id,'NURSE',s.nurse_id::text,'CASH_CLEARING',0,s.amount,'SYP_NEW'
FROM nurse_settlements s
WHERE s.direction='TO_NURSE'
  AND NOT EXISTS(SELECT 1 FROM financial_ledger_entries e WHERE e.transaction_id=s.id AND e.account_id='CASH_CLEARING');
UPDATE nurse_settlements SET transaction_id=id WHERE transaction_id IS NULL;

CREATE TABLE invoices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL UNIQUE REFERENCES care_requests(id),
  visit_id uuid NOT NULL UNIQUE REFERENCES visits(id),
  invoice_number bigint GENERATED ALWAYS AS IDENTITY UNIQUE,
  status text NOT NULL CHECK(status IN ('ISSUED','PARTIALLY_PAID','PAID','VOID')),
  currency_code text NOT NULL,
  subtotal numeric(18,2) NOT NULL CHECK(subtotal>=0),
  discount_amount numeric(18,2) NOT NULL CHECK(discount_amount>=0),
  surcharge_amount numeric(18,2) NOT NULL CHECK(surcharge_amount>=0),
  distance_fee numeric(18,2) NOT NULL CHECK(distance_fee>=0),
  tax_amount numeric(18,2) NOT NULL CHECK(tax_amount>=0),
  tip_amount numeric(18,2) NOT NULL DEFAULT 0 CHECK(tip_amount>=0),
  total_amount numeric(18,2) NOT NULL CHECK(total_amount>=0),
  paid_amount numeric(18,2) NOT NULL DEFAULT 0 CHECK(paid_amount>=0),
  pricing_snapshot jsonb NOT NULL CHECK(jsonb_typeof(pricing_snapshot)='object'),
  issued_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  paid_at timestamptz,
  version integer NOT NULL DEFAULT 1,
  CHECK(paid_amount<=total_amount+tip_amount)
);

CREATE TABLE invoice_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_id uuid NOT NULL REFERENCES invoices(id),
  request_item_id uuid REFERENCES care_request_items(id),
  line_type text NOT NULL CHECK(line_type IN ('SERVICE','SURCHARGE','DISTANCE','DISCOUNT','TAX','TIP','ADJUSTMENT')),
  description_ar text NOT NULL,
  quantity integer NOT NULL DEFAULT 1 CHECK(quantity>0),
  unit_amount numeric(18,2) NOT NULL,
  line_amount numeric(18,2) NOT NULL,
  created_at timestamptz NOT NULL DEFAULT statement_timestamp()
);

-- Expand historical completed visits into normalized invoices without changing
-- their legacy financial columns. Reconciliation can compare both sources.
INSERT INTO invoices(
  request_id,visit_id,status,currency_code,subtotal,discount_amount,surcharge_amount,
  distance_fee,tax_amount,tip_amount,total_amount,paid_amount,pricing_snapshot,issued_at,paid_at
)
SELECT DISTINCT ON (cr.id) cr.id,v.id,
  CASE cr.payment_status WHEN 'PAID' THEN 'PAID' WHEN 'PARTIAL' THEN 'PARTIALLY_PAID' ELSE 'ISSUED' END,
  coalesce(cr.currency_code,'SYP_NEW'),coalesce(cr.gross_amount,cr.price_amount,0),
  coalesce(cr.discount_amount,0),coalesce(cr.surcharge_amount,0),coalesce(cr.distance_fee,0),
  coalesce(cr.tax_amount,0),coalesce(cr.tip_amount,0),coalesce(cr.amount_due,cr.price_amount,0),
  least(coalesce((SELECT sum(cc.amount) FROM cash_collections cc WHERE cc.visit_id=v.id),0),
    coalesce(cr.amount_due,cr.price_amount,0)+coalesce(cr.tip_amount,0)),
  coalesce(cr.pricing,'{}'::jsonb),coalesce(cr.billed_at,v.completed_at),cr.paid_at
FROM care_requests cr JOIN request_assignments a ON a.request_id=cr.id
JOIN visits v ON v.assignment_id=a.id AND v.completed_at IS NOT NULL
WHERE cr.amount_due IS NOT NULL
ORDER BY cr.id,v.completed_at DESC
ON CONFLICT(request_id) DO NOTHING;

INSERT INTO invoice_lines(invoice_id,line_type,description_ar,unit_amount,line_amount)
SELECT i.id,'ADJUSTMENT','فاتورة تاريخية مرحّلة',i.total_amount,i.total_amount
FROM invoices i WHERE NOT EXISTS(SELECT 1 FROM invoice_lines l WHERE l.invoice_id=i.id);

INSERT INTO financial_transactions(
  id,transaction_type,reference_type,reference_id,currency_code,idempotency_key,payload_digest,posted_at
)
SELECT i.id,'INVOICE_ISSUED','INVOICE',i.id::text,i.currency_code,'legacy:invoice:'||i.request_id::text,
  encode(digest(i.request_id::text||':'||i.total_amount::text,'sha256'),'hex'),i.issued_at
FROM invoices i
WHERE i.total_amount+i.discount_amount>0
ON CONFLICT(id) DO NOTHING;

INSERT INTO financial_ledger_entries(transaction_id,reference_type,reference_id,account_id,debit_amount,credit_amount,currency)
SELECT i.id,'INVOICE',i.id::text,'PATIENT_RECEIVABLE',i.total_amount,0,i.currency_code
FROM invoices i WHERE i.total_amount>0
  AND NOT EXISTS(SELECT 1 FROM financial_ledger_entries e WHERE e.transaction_id=i.id AND e.account_id='PATIENT_RECEIVABLE');
INSERT INTO financial_ledger_entries(transaction_id,reference_type,reference_id,account_id,debit_amount,credit_amount,currency)
SELECT i.id,'INVOICE',i.id::text,'DISCOUNTS_EXPENSE',i.discount_amount,0,i.currency_code
FROM invoices i WHERE i.discount_amount>0
  AND NOT EXISTS(SELECT 1 FROM financial_ledger_entries e WHERE e.transaction_id=i.id AND e.account_id='DISCOUNTS_EXPENSE');
INSERT INTO financial_ledger_entries(transaction_id,reference_type,reference_id,account_id,debit_amount,credit_amount,currency)
SELECT i.id,'INVOICE',i.id::text,'COMMISSION_REVENUE',0,cr.commission_amount,i.currency_code
FROM invoices i JOIN care_requests cr ON cr.id=i.request_id WHERE coalesce(cr.commission_amount,0)>0
  AND NOT EXISTS(SELECT 1 FROM financial_ledger_entries e WHERE e.transaction_id=i.id AND e.account_id='COMMISSION_REVENUE');
INSERT INTO financial_ledger_entries(transaction_id,reference_type,reference_id,account_id,debit_amount,credit_amount,currency)
SELECT i.id,'INVOICE',i.id::text,'TAX_PAYABLE',0,i.tax_amount,i.currency_code
FROM invoices i WHERE i.tax_amount>0
  AND NOT EXISTS(SELECT 1 FROM financial_ledger_entries e WHERE e.transaction_id=i.id AND e.account_id='TAX_PAYABLE');
INSERT INTO financial_ledger_entries(transaction_id,reference_type,reference_id,account_id,debit_amount,credit_amount,currency)
SELECT i.id,'INVOICE',i.id::text,'NURSE_PAYABLE:'||a.nurse_id::text,0,cr.nurse_earning,i.currency_code
FROM invoices i JOIN care_requests cr ON cr.id=i.request_id
JOIN request_assignments a ON a.request_id=i.request_id JOIN visits v ON v.assignment_id=a.id AND v.id=i.visit_id
WHERE coalesce(cr.nurse_earning,0)>0
  AND NOT EXISTS(SELECT 1 FROM financial_ledger_entries e WHERE e.transaction_id=i.id AND e.account_id='NURSE_PAYABLE:'||a.nurse_id::text);
INSERT INTO financial_ledger_entries(transaction_id,reference_type,reference_id,account_id,debit_amount,credit_amount,currency)
SELECT i.id,'INVOICE',i.id::text,'ROUNDING_ADJUSTMENTS',
  greatest(0,coalesce(cr.commission_amount,0)+i.tax_amount+coalesce(cr.nurse_earning,0)-i.total_amount-i.discount_amount),
  greatest(0,i.total_amount+i.discount_amount-coalesce(cr.commission_amount,0)-i.tax_amount-coalesce(cr.nurse_earning,0)),i.currency_code
FROM invoices i JOIN care_requests cr ON cr.id=i.request_id
WHERE i.total_amount+i.discount_amount<>coalesce(cr.commission_amount,0)+i.tax_amount+coalesce(cr.nurse_earning,0)
  AND NOT EXISTS(SELECT 1 FROM financial_ledger_entries e WHERE e.transaction_id=i.id AND e.account_id='ROUNDING_ADJUSTMENTS');

ALTER TABLE care_request_items
  ADD COLUMN IF NOT EXISTS performed_quantity integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS actual_minutes integer,
  ADD COLUMN IF NOT EXISTS completion_note text,
  ADD COLUMN IF NOT EXISTS status_reason text,
  ADD COLUMN IF NOT EXISTS completed_at timestamptz,
  ADD CONSTRAINT chk_request_item_execution CHECK (
    performed_quantity BETWEEN 0 AND quantity
    AND (actual_minutes IS NULL OR actual_minutes>=0)
    AND (item_status='PENDING' OR status_reason IS NOT NULL OR item_status='COMPLETED')
  ) NOT VALID;
ALTER TABLE care_request_items VALIDATE CONSTRAINT chk_request_item_execution;
