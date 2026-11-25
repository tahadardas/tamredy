-- Read-only queries. Run on a restored database before upgrading from 051.
BEGIN READ ONLY;

SELECT name,applied_at FROM schema_migrations ORDER BY name;

SELECT count(*) AS calendar_conflicts
FROM nurse_calendar_blocks a JOIN nurse_calendar_blocks b
  ON a.nurse_id=b.nurse_id AND a.id<b.id
 AND tstzrange(a.start_time,a.end_time,'[)') && tstzrange(b.start_time,b.end_time,'[)');

SELECT count(*) AS duplicate_reservation_groups
FROM (
  SELECT account_id,reference_id FROM financial_reservations
  GROUP BY account_id,reference_id HAVING count(*)>1
) duplicates;

SELECT currency,count(*) AS unbalanced_transactions
FROM (
  SELECT currency,transaction_id FROM financial_ledger_entries
  GROUP BY currency,transaction_id HAVING sum(debit_amount)<>sum(credit_amount)
) unmatched GROUP BY currency;

SELECT count(*) AS zero_cash_receipts FROM cash_collections WHERE amount=0;
SELECT count(*) AS collections_not_confirmed FROM cash_collections WHERE status<>'CONFIRMED';
SELECT count(*) AS requests_without_item_snapshots
FROM care_requests r WHERE NOT EXISTS (SELECT 1 FROM care_request_items i WHERE i.request_id=r.id);

COMMIT;
