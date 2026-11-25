-- Existing requests awaiting dispatch must satisfy the same gate as new ones.
WITH needed AS (
  INSERT INTO request_clinical_reviews(request_id,required_prescription,required_clinical_review)
  SELECT r.id,bool_or(s.requires_prescription),bool_or(s.requires_clinical_review)
  FROM care_requests r JOIN care_request_items i ON i.request_id=r.id
  JOIN services s ON s.id=i.service_id
  WHERE r.status IN ('SCHEDULED','OFFERING','OPEN_FOR_PROPOSALS')
  GROUP BY r.id
  HAVING bool_or(s.requires_prescription OR s.requires_clinical_review)
  ON CONFLICT(request_id) DO NOTHING RETURNING request_id
)
UPDATE care_requests r SET clinical_approval_status='PENDING',version=version+1
FROM needed WHERE needed.request_id=r.id;

CREATE INDEX idx_financial_reservations_held_by_nurse
  ON financial_reservations(nurse_id) WHERE status='HELD';
