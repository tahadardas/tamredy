import type { Q } from '../pricing/fees.service.js';

const moneyColumns = [
  'grossBilledByCurrency','commissionRevenueByCurrency','discountExpenseByCurrency',
  'taxPayableByCurrency','cashCollectedByCurrency','outstandingReceivablesByCurrency',
  'nursePayablesByCurrency','roundingAdjustmentsByCurrency',
] as const;

export async function loadFinancialDashboard(q: Q) {
  const result=await q.query(`WITH period AS (
    SELECT date_trunc('day',statement_timestamp() AT TIME ZONE 'Asia/Damascus')
      AT TIME ZONE 'Asia/Damascus' AS day_start
  ), journals AS (
    SELECT e.*,t.posted_at,coalesce(original.transaction_type,t.transaction_type) AS source_type,
      t.reversal_of_transaction_id IS NOT NULL AS reversed
    FROM financial_ledger_entries e JOIN financial_transactions t ON t.id=e.transaction_id
    LEFT JOIN financial_transactions original ON original.id=t.reversal_of_transaction_id
  ), invoice_gross AS (
    SELECT i.currency_code,
      sum(CASE WHEN t.reversal_of_transaction_id IS NULL THEN 1 ELSE -1 END *
        coalesce(l.amount,i.subtotal+i.distance_fee+i.tax_amount)) AS gross
    FROM financial_transactions t LEFT JOIN financial_transactions original ON original.id=t.reversal_of_transaction_id
    JOIN invoices i ON i.id::text=coalesce(original.reference_id,t.reference_id)
      AND i.currency_code=t.currency_code
    LEFT JOIN LATERAL (SELECT sum(line_amount) AS amount FROM invoice_lines
      WHERE invoice_id=i.id AND line_type IN ('SERVICE','SURCHARGE','DISTANCE','TAX','ADJUSTMENT')) l ON true
    CROSS JOIN period
    WHERE coalesce(original.transaction_type,t.transaction_type)='INVOICE_ISSUED'
      AND coalesce(original.reference_type,t.reference_type)='INVOICE' AND t.posted_at>=period.day_start
    GROUP BY i.currency_code
  ), ledger_totals AS (
    SELECT currency,
      sum(credit_amount-debit_amount) FILTER(WHERE account_id='COMMISSION_REVENUE' AND posted_at>=period.day_start) AS commission,
      sum(debit_amount-credit_amount) FILTER(WHERE account_id='DISCOUNTS_EXPENSE' AND posted_at>=period.day_start) AS discount,
      sum(credit_amount-debit_amount) FILTER(WHERE account_id='TAX_PAYABLE') AS tax,
      sum(debit_amount-credit_amount) FILTER(WHERE account_id LIKE 'CASH_HELD_BY_NURSE:%'
        AND source_type='CASH_COLLECTION' AND posted_at>=period.day_start) AS cash,
      sum(debit_amount-credit_amount) FILTER(WHERE account_id='PATIENT_RECEIVABLE') AS receivables,
      sum(credit_amount-debit_amount) FILTER(WHERE account_id LIKE 'NURSE_PAYABLE:%') AS payables,
      sum(credit_amount-debit_amount) FILTER(WHERE account_id='ROUNDING_ADJUSTMENTS' AND posted_at>=period.day_start) AS rounding
    FROM journals CROSS JOIN period GROUP BY currency
  )
  SELECT coalesce(g.currency_code,l.currency) AS currency,g.gross::text AS "grossBilledByCurrency",
    l.commission::text AS "commissionRevenueByCurrency",l.discount::text AS "discountExpenseByCurrency",
    l.tax::text AS "taxPayableByCurrency",l.cash::text AS "cashCollectedByCurrency",
    l.receivables::text AS "outstandingReceivablesByCurrency",l.payables::text AS "nursePayablesByCurrency",
    l.rounding::text AS "roundingAdjustmentsByCurrency"
  FROM invoice_gross g FULL JOIN ledger_totals l ON l.currency=g.currency_code ORDER BY 1`);
  return Object.fromEntries(moneyColumns.map(column=>[column,Object.fromEntries(result.rows
    .filter(row=>row[column]!=null).map(row=>[String(row.currency),String(row[column])]))]));
}
